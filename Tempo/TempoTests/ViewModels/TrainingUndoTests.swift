//
// TrainingUndoTests.swift
// Tempo
//
// Undo for a logged set and for skipped sets: the set, its feedback row, the
// cursor and the rest timer go back to where they were, and Undo is not
// offered where it could not be exact (a record was set, a calibration set,
// the log ended the workout) or once something else has been logged.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainingUndoTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            SetFeedback.self,
            PersonalRecord.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVM(engine: TrainingEngineProtocol = MockTrainingEngine(), autoRest: Bool = true) -> TrainingViewModel {
        let vm = TrainingViewModel(
            trainingEngine: engine,
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        vm.autoStartRest = autoRest
        return vm
    }

    /// One exercise with `sets` working sets (plus `warmups` ramp sets first)
    /// and, optionally, a second exercise with one set.
    private func seed(
        sets: Int,
        warmups: Int = 0,
        second: Bool = false,
        calibrationFirst: Bool = false,
        context: ModelContext
    ) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest,
            equipment: .barbell, movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        var rows: [PlannedSet] = []
        var number = 1
        for _ in 0 ..< warmups {
            rows.append(PlannedSet(setNumber: number, targetReps: 8, targetWeight: 40, isWarmup: true, plannedExercise: slot))
            number += 1
        }
        for index in 0 ..< sets {
            rows.append(PlannedSet(
                setNumber: number, targetReps: 8, targetWeight: 80,
                isCalibration: calibrationFirst && index == 0, plannedExercise: slot
            ))
            number += 1
        }
        slot.sets = rows
        if second {
            let raise = Exercise(
                name: "Lateral Raise", muscleGroup: .shoulders,
                equipment: .dumbbell, movementPattern: .isolation, isCompound: false
            )
            context.insert(raise)
            let other = PlannedExercise(order: 1, workoutPlan: plan, exercise: raise)
            other.sets = [PlannedSet(setNumber: 1, targetReps: 12, targetWeight: 10, plannedExercise: other)]
        }
        try? context.save()
        return plan
    }

    private func enterSetActive(_ vm: TrainingViewModel, exercise: Int = 0, set: Int = 0) {
        vm.currentExerciseIndex = exercise
        vm.currentSetIndex = set
        vm.sessionState = .exercise(.setActive(exerciseIndex: exercise, setIndex: set))
    }

    private func feedbackCount(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<SetFeedback>())) ?? -1
    }

    // MARK: Logged set

    func testUndoReopensTheSetAndPutsTheSessionBackOnIt() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        let sets = plan.orderedExercises[0].orderedSets
        XCTAssertTrue(sets[0].completed)
        XCTAssertEqual(feedbackCount(context), 1)
        guard case .exercise(.resting) = vm.sessionState else {
            return XCTFail("a set that is not the last starts a rest, got \(vm.sessionState)")
        }

        XCTAssertTrue(vm.undoLoggedSet(undo, modelContext: context))

        XCTAssertFalse(sets[0].completed)
        XCTAssertNil(sets[0].actualWeight)
        XCTAssertNil(sets[0].actualReps)
        XCTAssertNil(sets[0].completedAt)
        XCTAssertEqual(feedbackCount(context), 0, "the feedback row the log created is removed")
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))
        XCTAssertEqual(vm.currentSetIndex, 0)
        XCTAssertEqual(vm.restTimerRemaining, 0, "the rest the log started is stopped")
        XCTAssertNil(vm.lastCompletedSet)
        XCTAssertNil(vm.currentFeedback)
    }

    func testUndoThenLoggingAgainWorksLikeTheFirstTime() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 2, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        vm.undoLoggedSet(undo, modelContext: context)
        vm.logSet(weight: 82.5, reps: 7, modelContext: context)

        let first = plan.orderedExercises[0].orderedSets[0]
        XCTAssertTrue(first.completed)
        XCTAssertEqual(first.actualWeight, 82.5)
        XCTAssertEqual(first.actualReps, 7)
        XCTAssertEqual(feedbackCount(context), 1, "one feedback row, not two")
    }

    func testUndoWorksAfterTheRestHasEndedToo() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        vm.skipRest()
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 1)))

        XCTAssertTrue(vm.undoLoggedSet(undo, modelContext: context))
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))
        XCTAssertFalse(plan.orderedExercises[0].orderedSets[0].completed)
        XCTAssertFalse(plan.orderedExercises[0].orderedSets[1].completed)
    }

    func testUndoWithRestOffGoesBackToTheSameSet() throws {
        let context = try makeContext()
        let vm = makeVM(autoRest: false)
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 1)))

        XCTAssertTrue(vm.undoLoggedSet(undo, modelContext: context))
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))
    }

    func testUndoGoesBackAcrossAnExerciseBoundary() throws {
        let context = try makeContext()
        let vm = makeVM(autoRest: false)
        let plan = seed(sets: 1, second: true, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        XCTAssertTrue(vm.undoLoggedSet(undo, modelContext: context))
        XCTAssertEqual(vm.currentExerciseIndex, 0)
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))
        XCTAssertFalse(plan.orderedExercises[0].orderedSets[0].completed)
    }

    func testNoUndoWhenTheLogEndedTheWorkout() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        XCTAssertNil(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        XCTAssertEqual(vm.sessionState, .summary)
    }

    func testNoUndoForACalibrationSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 3, calibrationFirst: true, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        XCTAssertNil(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        XCTAssertTrue(plan.orderedExercises[0].orderedSets[0].completed, "the set is still logged")
    }

    func testNoUndoWhenTheSetWasARecord() throws {
        let context = try makeContext()
        // The real engine finds a record once the lift has an older best to beat.
        let vm = makeVM(engine: TrainingEngine())
        let plan = seed(sets: 3, context: context)
        let bench = try XCTUnwrap(plan.orderedExercises[0].exercise)
        context.insert(ExerciseHistory(
            date: Date().addingTimeInterval(-7 * 86400),
            estimated1RM: StrengthStandards.epleyE1RM(weight: 80, reps: 5),
            bestSetWeight: 80, bestSetReps: 5, workoutPlanID: UUID(), exercise: bench
        ))
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = vm.logSetCapturingUndo(weight: 100, reps: 5, modelContext: context)
        XCTAssertFalse(vm.detectedPRs.isEmpty, "this log should have set a record, or the test proves nothing")
        XCTAssertNil(undo, "a record cannot be put back exactly, so no Undo is offered")
    }

    func testAnOlderUndoIsRefusedOnceAnotherSetIsLogged() throws {
        let context = try makeContext()
        let vm = makeVM(autoRest: false)
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let first = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        let second = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))

        XCTAssertFalse(vm.undoLoggedSet(first, modelContext: context))
        XCTAssertTrue(plan.orderedExercises[0].orderedSets[0].completed, "the earlier set is left alone")
        XCTAssertTrue(vm.undoLoggedSet(second, modelContext: context))
        XCTAssertFalse(plan.orderedExercises[0].orderedSets[1].completed)
        XCTAssertTrue(plan.orderedExercises[0].orderedSets[0].completed)
    }

    func testUndoTwiceDoesNothingTheSecondTime() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = try XCTUnwrap(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
        XCTAssertTrue(vm.undoLoggedSet(undo, modelContext: context))
        XCTAssertFalse(vm.undoLoggedSet(undo, modelContext: context))
    }

    func testUndoKeepsTheLoggedValuesOfAWarmupSetToo() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 2, warmups: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let undo = try XCTUnwrap(vm.logSetCapturingUndo(weight: 40, reps: 8, modelContext: context))
        XCTAssertEqual(feedbackCount(context), 0, "a warm-up set has no feedback row")
        XCTAssertTrue(vm.undoLoggedSet(undo, modelContext: context))
        XCTAssertFalse(plan.orderedExercises[0].orderedSets[0].completed)
        XCTAssertEqual(undo.weightKg, 40)
        XCTAssertEqual(undo.reps, 8)
    }

    func testLoggingWithNothingToLogGivesNoUndo() throws {
        let context = try makeContext()
        let vm = makeVM()
        XCTAssertNil(vm.logSetCapturingUndo(weight: 80, reps: 8, modelContext: context))
    }

    // MARK: Skipped sets

    func testUndoPutsASkippedSetBackAndLandsOnIt() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        let original = plan.orderedExercises[0].orderedSets[0]
        let (id, number, target) = (original.id, original.setNumber, original.targetWeight)

        let undo = try XCTUnwrap(vm.skipCurrentSetCapturingUndo(modelContext: context))
        XCTAssertEqual(plan.orderedExercises[0].orderedSets.count, 2)

        XCTAssertTrue(vm.undoSkippedSets(undo, modelContext: context))
        let sets = plan.orderedExercises[0].orderedSets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[0].id, id)
        XCTAssertEqual(sets[0].setNumber, number)
        XCTAssertEqual(sets[0].targetWeight, target)
        XCTAssertFalse(sets[0].completed)
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))
    }

    func testUndoingASkipInTheMiddleKeepsTheOrder() throws {
        let context = try makeContext()
        let vm = makeVM(autoRest: false)
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        let ids = plan.orderedExercises[0].orderedSets.map(\.id)

        let undo = try XCTUnwrap(vm.skipCurrentSetCapturingUndo(modelContext: context))
        XCTAssertTrue(vm.undoSkippedSets(undo, modelContext: context))

        XCTAssertEqual(plan.orderedExercises[0].orderedSets.map(\.id), ids)
        XCTAssertEqual(vm.currentSetIndex, 1)
    }

    func testUndoBringsBackSkippedWarmups() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 2, warmups: 2, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        let ids = plan.orderedExercises[0].orderedSets.map(\.id)

        let undo = try XCTUnwrap(vm.skipRemainingWarmupsCapturingUndo(modelContext: context))
        XCTAssertEqual(plan.orderedExercises[0].orderedSets.count, 2)

        XCTAssertTrue(vm.undoSkippedSets(undo, modelContext: context))
        let sets = plan.orderedExercises[0].orderedSets
        XCTAssertEqual(sets.map(\.id), ids)
        XCTAssertEqual(sets.filter(\.isWarmup).count, 2, "they come back as warm-ups")
        XCTAssertEqual(vm.currentSetIndex, 0)
    }

    func testTheSkipMessageNamesWhatWasSkipped() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 3, warmups: 2, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        let ramp = try XCTUnwrap(vm.skipRemainingWarmupsCapturingUndo(modelContext: context))
        XCTAssertEqual(ramp.message, "Skipped 2 warm-up sets")

        enterSetActive(vm)
        let working = try XCTUnwrap(vm.skipCurrentSetCapturingUndo(modelContext: context))
        XCTAssertEqual(working.message, "Skipped a set of Bench Press")
    }

    func testNoUndoWhenTheSkipEndedTheWorkout() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 2, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        vm.skipRest()

        XCTAssertNil(vm.skipCurrentSetCapturingUndo(modelContext: context))
        XCTAssertEqual(vm.sessionState, .summary)
    }

    func testSkippingAnAlreadyLoggedSetOffersNoUndo() throws {
        let context = try makeContext()
        let vm = makeVM(autoRest: false)
        let plan = seed(sets: 2, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        // Rest state: nothing to skip.
        vm.sessionState = .exercise(.resting(exerciseIndex: 0, setIndex: 0, remainingSeconds: 30))
        XCTAssertNil(vm.skipCurrentSetCapturingUndo(modelContext: context))
        XCTAssertEqual(plan.orderedExercises[0].orderedSets.count, 2)
    }

    func testUndoingASkipTwiceDoesNotDuplicateTheSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        let undo = try XCTUnwrap(vm.skipCurrentSetCapturingUndo(modelContext: context))
        vm.undoSkippedSets(undo, modelContext: context)
        vm.undoSkippedSets(undo, modelContext: context)
        XCTAssertEqual(plan.orderedExercises[0].orderedSets.count, 3)
    }
}
