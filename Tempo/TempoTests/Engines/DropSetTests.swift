//
// DropSetTests.swift
// Tempo
//
// Drop sets: chained -20% steps snapped to loadable weights, logged with no
// rest, excluded from PR/e1RM/best-set but counted in volume.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class DropSetTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            SetFeedback.self,
            PersonalRecord.self,
            ExerciseHistory.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVM(engine: any TrainingEngineProtocol = MockTrainingEngine()) -> TrainingViewModel {
        let vm = TrainingViewModel(
            trainingEngine: engine,
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        vm.autoStartRest = false
        return vm
    }

    /// Single barbell exercise with `working` sets (100kg × 5 by default).
    private func seedSingleExercise(working: Int, context: ModelContext) -> (WorkoutPlan, PlannedExercise) {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let bench = Exercise(
            name: "Bench Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.sets = (1 ... working).map {
            PlannedSet(setNumber: $0, targetReps: 5, targetWeight: 100, plannedExercise: slot)
        }
        try? context.save()
        return (plan, slot)
    }

    private func enterSetActive(_ vm: TrainingViewModel, exercise: Int = 0, set: Int = 0) {
        vm.currentExerciseIndex = exercise
        vm.currentSetIndex = set
        vm.sessionState = .exercise(.setActive(exerciseIndex: exercise, setIndex: set))
    }

    // MARK: - Adding / Chaining

    func testAddDropSetInsertsReducedWeightStepAfterCurrent() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.addDropSet(modelContext: context)

        let sets = slot.orderedSets
        XCTAssertEqual(sets.count, 2)
        XCTAssertNil(sets[0].dropStepIndex, "The original set is untouched")
        XCTAssertEqual(sets[1].dropStepIndex, 1)
        XCTAssertEqual(sets[1].targetWeight, 80, "100kg snapped -20% → 80kg (already loadable)")
        XCTAssertTrue(sets[1].isDropStep)
    }

    func testChainedDropSetsReduceFurtherFromThePreviousStep() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.addDropSet(modelContext: context) // Drop 1: 80kg
        enterSetActive(vm, set: 1) // simulate having advanced onto Drop 1
        vm.addDropSet(modelContext: context) // Drop 2: reduces off Drop 1's 80kg

        let sets = slot.orderedSets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[1].dropStepIndex, 1)
        XCTAssertEqual(sets[2].dropStepIndex, 2)
        XCTAssertEqual(sets[2].targetWeight, 65, "80kg × 0.8 = 64 → snapped up to 65 (2.5kg lattice)")
    }

    func testAddDropSetNoOpsOnWarmupSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let bench = Exercise(
            name: "Bench Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.sets = [PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 40, isWarmup: true, plannedExercise: slot)]
        try? context.save()
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.addDropSet(modelContext: context)

        XCTAssertEqual(slot.orderedSets.count, 1, "A ramp set is never turned into a drop set")
    }

    func testRemoveTrailingDropSetUndoesQueuedDrop() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.addDropSet(modelContext: context)
        XCTAssertEqual(slot.orderedSets.count, 2)

        vm.removeTrailingDropSet(modelContext: context)

        XCTAssertEqual(slot.orderedSets.count, 1, "The queued drop is removed")
    }

    func testRemoveTrailingDropSetRefusesACompletedDrop() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.addDropSet(modelContext: context)
        slot.orderedSets[1].completed = true

        vm.removeTrailingDropSet(modelContext: context)

        XCTAssertEqual(slot.orderedSets.count, 2, "Logged work is history — never silently deleted")
    }

    // MARK: - No-rest continuation

    func testLogSetContinuesIntoQueuedDropWithNoRestEvenWithAutoRestOn() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.addDropSet(modelContext: context)
        vm.autoStartRest = true // even ON, a drop chain takes no rest

        vm.logSet(weight: 100, reps: 5, modelContext: context)

        XCTAssertEqual(vm.currentExerciseIndex, 0)
        XCTAssertEqual(vm.currentSetIndex, 1)
        XCTAssertEqual(
            vm.sessionState,
            .exercise(.setActive(exerciseIndex: 0, setIndex: 1)),
            "Straight into the drop step — no resting state in between"
        )
        XCTAssertTrue(slot.orderedSets[0].completed)
    }

    func testFinishingLastDropStepEndsSessionNormally() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.addDropSet(modelContext: context)
        vm.autoStartRest = true

        vm.logSet(weight: 100, reps: 5, modelContext: context) // top set → Drop 1, no rest
        vm.logSet(weight: 80, reps: 8, modelContext: context) // Drop 1 — last set, last exercise

        XCTAssertEqual(vm.sessionState, .summary)
        XCTAssertTrue(slot.orderedSets[1].completed)
    }

    // MARK: - PR / e1RM exclusion

    /// Records every `detectPersonalRecord` call and always "finds" a PR for
    /// a positive weight — isolates whether `logSet` even ATTEMPTS detection
    /// for a given set, independent of the real PR math.
    private final class PRRecordingTrainingEngine: TrainingEngineProtocol, @unchecked Sendable {
        var recordedWeights: [Double] = []

        func generateWorkout(
            for date: Date,
            recoveryScore: Double?,
            footballDays: ActiveDays,
            split: TrainingSplit,
            customWeekdayMap: [WorkoutType]?
        ) -> WorkoutPlan {
            WorkoutPlan(date: date, type: .push, status: .planned)
        }

        func calculateProgressiveOverload(
            for exercise: Exercise,
            history: [ExerciseHistory],
            learnedIncrement: Double?
        ) -> ProgressionDecision {
            ProgressionDecision(weight: 80, reps: 10, deltaApplied: 0, rationale: .standardProgression)
        }

        func restMultiplier(history: [ExerciseHistory]) -> Double {
            1.0
        }

        func detectPersonalRecord(exercise: Exercise, weight: Double, reps: Int) -> PersonalRecord? {
            recordedWeights.append(weight)
            guard weight > 0 else {
                return nil
            }
            return PersonalRecord(type: .oneRepMax, value: weight, date: Date(), context: "", exercise: exercise)
        }

        func generateWeekPlan(
            startDate: Date,
            recoveryScores: [Date: Double],
            footballDays: ActiveDays,
            split: TrainingSplit,
            customWeekdayMap: [WorkoutType]?,
            recoveryThresholdOffset: Double,
            matchDayKeys: Set<Date>,
            competitiveMatchDayKeys: Set<Date>?,
            emphasis: BlockEmphasis,
            easyModalityPreference: [WorkoutType],
            referenceDate: Date
        ) -> [WorkoutPlan] {
            []
        }

        func isDeloadWeek(
            date: Date,
            deloadFrequencyWeeks: Int,
            trainingStartDate: Date?,
            fatigueEWMA: Double?
        ) -> Bool {
            false
        }

        func deloadWeightMultiplier() -> Double {
            0.6
        }
    }

    func testPRDetectionIsNeverAttemptedForADropStep() throws {
        let context = try makeContext()
        let engine = PRRecordingTrainingEngine()
        let vm = makeVM(engine: engine)
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.addDropSet(modelContext: context)

        vm.logSet(weight: 100, reps: 5, modelContext: context) // top set → detection runs
        vm.logSet(weight: 80, reps: 8, modelContext: context) // drop step → must be skipped

        XCTAssertEqual(engine.recordedWeights, [100], "Only the top set reaches detectPersonalRecord")
        XCTAssertEqual(vm.detectedPRs.count, 1)
        XCTAssertTrue(slot.orderedSets[1].completed, "The drop step is still logged as work")
    }

    func testEstimated1RMExcludesDropSteps() {
        let drop = PlannedSet(
            setNumber: 2,
            targetReps: 8,
            actualReps: 8,
            actualWeight: 500,
            completed: true,
            dropStepIndex: 1
        )
        XCTAssertNil(drop.estimated1RM, "A reduced-weight backoff set is never an e1RM signal")

        let working = PlannedSet(setNumber: 1, targetReps: 5, actualReps: 5, actualWeight: 100, completed: true)
        XCTAssertNotNil(working.estimated1RM, "A normal working set still contributes e1RM")
    }

    func testBestSetExcludesDropStepsEvenWhenHeavier() {
        let plan = WorkoutPlan(date: Date(), type: .push)
        let exercise = Exercise(
            name: "Bench Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        let working = PlannedSet(setNumber: 1, targetReps: 5, actualReps: 5, actualWeight: 100, completed: true)
        // Contrived: a "drop" heavier than the working set — even so, it must
        // never be reported as the exercise's best set.
        let drop = PlannedSet(
            setNumber: 2,
            targetReps: 8,
            actualReps: 8,
            actualWeight: 150,
            completed: true,
            dropStepIndex: 1
        )
        slot.sets = [working, drop]

        XCTAssertEqual(slot.bestSet?.id, working.id)
    }

    // MARK: - persistCompletion aggregation

    func testPersistCompletionIncludesDropInVolumeButExcludesFromBestAndE1RM() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.addDropSet(modelContext: context)
        vm.autoStartRest = true

        vm.logSet(weight: 100, reps: 5, modelContext: context) // top set
        vm.logSet(weight: 80, reps: 8, modelContext: context) // drop — ends in .summary

        XCTAssertTrue(vm.persistCompletion(modelContext: context))

        let planID = plan.id
        let rows = try context.fetch(FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate<ExerciseHistory> { $0.workoutPlanID == planID }
        ))
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)

        XCTAssertEqual(row.bestSetWeight, 100, "The drop is never the 'best' set")
        XCTAssertEqual(row.bestSetReps, 5)
        XCTAssertEqual(row.setsPerformed, 2, "Both the top set and the drop count as sets performed")
        XCTAssertEqual(row.totalVolume, 100 * 5 + 80 * 8, "Volume includes the drop's work")
        let e1RM = try XCTUnwrap(row.estimated1RM)
        XCTAssertEqual(e1RM, 100 * (1 + 5.0 / 30.0), accuracy: 0.001, "e1RM comes from the top set only")
        _ = slot // silence unused-var warning if slot goes unread on some paths
    }

    // MARK: - Review fixes

    func testNextWorkingSetPrefillsTopSetWeightNotTheDrop() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, slot) = seedSingleExercise(working: 2, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        vm.addDropSet(modelContext: context) // set 0 → drop at index 1, next working at 2
        let sets = slot.orderedSets
        sets[0].actualWeight = 100
        sets[0].completed = true
        sets[1].actualWeight = 80
        sets[1].completed = true

        enterSetActive(vm, set: 2)

        XCTAssertEqual(vm.stickyWeight, 100, "Pre-fill carries the top set, not the 80kg drop")
    }
}
