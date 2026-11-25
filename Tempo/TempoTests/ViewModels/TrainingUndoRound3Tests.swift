//
// TrainingUndoRound3Tests.swift
// Tempo
//
// Undo for the rest of Train's logs and deletes: a discarded workout, the "−"
// button, the session rating, a deleted match, a deleted trainer program and a
// deleted custom exercise. Each test checks that what Undo brings back is what
// was there before, and that Undo is refused or does nothing twice where it
// could not be exact.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainingUndoRound3Tests: XCTestCase {
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

    private func makeVM() -> TrainingViewModel {
        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        vm.autoStartRest = false
        return vm
    }

    /// One bench exercise with `sets` working sets.
    private func seed(sets: Int, context: ModelContext) -> (plan: WorkoutPlan, bench: Exercise) {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest,
            equipment: .barbell, movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.sets = (1 ... sets).map {
            PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 80, plannedExercise: slot)
        }
        try? context.save()
        return (plan, bench)
    }

    private func enterSetActive(_ vm: TrainingViewModel, set: Int = 0) {
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = set
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: set))
    }

    private func sets(_ plan: WorkoutPlan) -> [PlannedSet] {
        plan.orderedExercises[0].orderedSets
    }

    // MARK: - Discarded workout

    func testUndoingADiscardBringsBackSetsFeedbackRecordsAndTheSession() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, bench) = seed(sets: 3, context: context)
        vm.todayPlan = plan
        plan.status = .inProgress
        plan.startedAt = Date().addingTimeInterval(-600)
        enterSetActive(vm)

        vm.logSet(weight: 80, reps: 8, modelContext: context)
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 1))
        vm.currentSetIndex = 1
        vm.logSet(weight: 82.5, reps: 7, modelContext: context)
        let record = PersonalRecord(
            type: .oneRepMax, value: 100, date: Date(), workoutPlanID: plan.id,
            context: "82.5 x 7", contextWeightKg: 82.5, contextReps: 7, exercise: bench
        )
        context.insert(record)
        try context.save()
        let recordID = record.id
        let feedbackIDs = try Set(context.fetch(FetchDescriptor<SetFeedback>()).map(\.id))
        XCTAssertEqual(feedbackIDs.count, 2)
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 2))
        vm.currentSetIndex = 2

        let undo = try XCTUnwrap(vm.discardActiveWorkoutCapturingUndo(modelContext: context))
        XCTAssertEqual(undo.loggedSets, 2)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertNil(plan.startedAt)
        XCTAssertTrue(sets(plan).allSatisfy { !$0.completed })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetFeedback>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
        XCTAssertEqual(vm.discardUndo?.id, undo.id)

        // The day reloads and settles on idle before Undo is tapped.
        vm.sessionState = .idle
        XCTAssertTrue(vm.undoDiscardedWorkout(undo, modelContext: context))

        let restored = sets(plan)
        XCTAssertEqual(restored.map(\.completed), [true, true, false])
        XCTAssertEqual(restored[0].actualWeight, 80)
        XCTAssertEqual(restored[0].actualReps, 8)
        XCTAssertEqual(restored[1].actualWeight, 82.5)
        XCTAssertEqual(restored[1].actualReps, 7)
        XCTAssertEqual(plan.status, .inProgress)
        XCTAssertNotNil(plan.startedAt)
        XCTAssertEqual(try Set(context.fetch(FetchDescriptor<SetFeedback>()).map(\.id)), feedbackIDs)
        let records = try context.fetch(FetchDescriptor<PersonalRecord>())
        XCTAssertEqual(records.map(\.id), [recordID])
        XCTAssertEqual(records.first?.exercise?.id, bench.id)
        XCTAssertEqual(records.first?.value, 100)
        XCTAssertEqual(records.first?.contextReps, 7)
        // Back in the logger on the first set still open.
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 2)))
        XCTAssertNil(vm.discardUndo)
        vm.resetState()
    }

    func testNoUndoIsOfferedForADiscardThatLostNothing() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 2, context: context)
        vm.todayPlan = plan
        plan.status = .inProgress
        enterSetActive(vm)

        XCTAssertNil(vm.discardActiveWorkoutCapturingUndo(modelContext: context))
        XCTAssertNil(vm.discardUndo)
        XCTAssertEqual(plan.status, .planned)
    }

    func testAnUndoIsRefusedWhileTheDayIsStillReloadingOrAnotherSessionRuns() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 2, context: context)
        vm.todayPlan = plan
        plan.status = .inProgress
        plan.startedAt = Date().addingTimeInterval(-60)
        enterSetActive(vm)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        let undo = try XCTUnwrap(vm.discardActiveWorkoutCapturingUndo(modelContext: context))

        // Mid-reload (.discarded): the settle to .idle would overwrite the restore.
        XCTAssertEqual(vm.sessionState, .discarded)
        XCTAssertFalse(vm.undoDiscardedWorkout(undo, modelContext: context))
        XCTAssertTrue(sets(plan).allSatisfy { !$0.completed })

        // A different plan is today's now.
        vm.sessionState = .idle
        let other = WorkoutPlan(date: Date(), type: .pull)
        context.insert(other)
        vm.todayPlan = other
        XCTAssertFalse(vm.undoDiscardedWorkout(undo, modelContext: context))
    }

    func testUndoingADiscardTwiceDoesNotDuplicateFeedback() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 2, context: context)
        vm.todayPlan = plan
        plan.status = .inProgress
        plan.startedAt = Date().addingTimeInterval(-60)
        enterSetActive(vm)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        let undo = try XCTUnwrap(vm.discardActiveWorkoutCapturingUndo(modelContext: context))
        vm.sessionState = .idle
        XCTAssertTrue(vm.undoDiscardedWorkout(undo, modelContext: context))
        // The second tap finds a live session and does nothing.
        XCTAssertFalse(vm.undoDiscardedWorkout(undo, modelContext: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetFeedback>()), 1)
        vm.resetState()
    }

    // MARK: - Remove a set with "−"

    func testUndoPutsTheRemovedSetBackInPlace() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)
        let lastID = sets(plan)[2].id

        let undo = try XCTUnwrap(vm.removeLastUncompletedSetCapturingUndo(from: 0, modelContext: context))
        XCTAssertEqual(sets(plan).count, 2)
        XCTAssertEqual(undo.message, "Removed a set")

        XCTAssertTrue(vm.undoRemovedSet(undo, modelContext: context))
        let back = sets(plan)
        XCTAssertEqual(back.map(\.setNumber), [1, 2, 3])
        XCTAssertEqual(back[2].id, lastID)
        XCTAssertEqual(back[2].targetReps, 8)
        XCTAssertEqual(back[2].targetWeight, 80)
        XCTAssertEqual(vm.currentSetIndex, 0)
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))
    }

    func testUndoingTheRemovalOfTheSetOnScreenReturnsToIt() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 3, context: context)
        vm.todayPlan = plan
        plan.status = .inProgress
        // The last set is the one on screen when "-" takes it out.
        enterSetActive(vm, set: 2)
        let doomedID = sets(plan)[2].id

        let undo = try XCTUnwrap(vm.removeLastUncompletedSetCapturingUndo(from: 0, modelContext: context))
        XCTAssertTrue(undo.cursorWasRemoved)
        XCTAssertEqual(sets(plan).count, 2)
        XCTAssertEqual(vm.currentSetIndex, 0, "the session moved to the first open set")

        XCTAssertTrue(vm.undoRemovedSet(undo, modelContext: context))
        XCTAssertEqual(sets(plan).map(\.id).last, doomedID)
        XCTAssertEqual(vm.currentSetIndex, 2)
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 2)))
        vm.resetState()
    }

    func testNoUndoWhenTheLastSetCannotBeRemoved() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        XCTAssertNil(vm.removeLastUncompletedSetCapturingUndo(from: 0, modelContext: context))
        XCTAssertEqual(sets(plan).count, 1)
    }

    func testRemovedSetUndoIsRefusedOnceSomethingIsLogged() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 4, context: context)
        vm.todayPlan = plan
        plan.status = .inProgress
        enterSetActive(vm)
        let undo = try XCTUnwrap(vm.removeLastUncompletedSetCapturingUndo(from: 0, modelContext: context))
        vm.logSet(weight: 80, reps: 8, modelContext: context)

        XCTAssertFalse(vm.undoRemovedSet(undo, modelContext: context))
        XCTAssertEqual(sets(plan).count, 3)
        vm.resetState()
    }

    // MARK: - Session rating

    func testUndoTakesTheSessionRatingBack() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 1, context: context)
        plan.status = .completed
        vm.todayPlan = plan

        let undo = try XCTUnwrap(vm.recordSessionRPECapturingUndo(8, modelContext: context))
        XCTAssertEqual(plan.sessionRPE, 8)
        XCTAssertEqual(undo.rating, 8)

        XCTAssertTrue(vm.undoSessionRPE(undo, modelContext: context))
        XCTAssertNil(plan.sessionRPE)
        // The card asks again, and a second tap on Undo changes nothing.
        XCTAssertFalse(vm.undoSessionRPE(undo, modelContext: context))
    }

    func testNoRatingUndoForARatingThatWasNotRecorded() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seed(sets: 1, context: context)
        plan.status = .inProgress
        vm.todayPlan = plan

        XCTAssertNil(vm.recordSessionRPECapturingUndo(8, modelContext: context))
        XCTAssertNil(plan.sessionRPE)
        XCTAssertNil(vm.recordSessionRPECapturingUndo(11, modelContext: context))
    }

    // MARK: - Match, trainer program, custom exercise

    func testAMatchComesBackWithItsOldIdAndDetails() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let kickoff = Date().addingTimeInterval(3 * 86400)
        let match = Match(kickoff: kickoff, opponent: "Inter", isCompetitive: false)
        context.insert(match)
        try context.save()
        let snapshot = MatchSnapshot(match)

        context.delete(match)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Match>()), 0)

        let back = snapshot.restore(in: context)
        try context.save()
        XCTAssertEqual(back.id, snapshot.id)
        XCTAssertEqual(back.opponent, "Inter")
        XCTAssertFalse(back.isCompetitive)
        XCTAssertEqual(back.kickoff, kickoff)
        XCTAssertEqual(snapshot.message, "Deleted the match vs Inter")
        // A second Undo changes nothing.
        snapshot.restore(in: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Match>()), 1)
    }

    func testATrainerProgramComesBackExactlyAsItWas() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let day = ProgramDay(weekday: 1, title: "Push", exercises: [])
        let program = TrainerProgram(
            name: "Block A", startDate: Date(), weeks: [ProgramWeek(days: [day])],
            repeats: false, isActive: true, sourceKind: "text", sourceText: "Mon: push",
            autoWarmups: false, scheduleMode: .fixed, cadence: .weekly
        )
        program.endedAt = Date().addingTimeInterval(-86400)
        program.skippedSessions = [TrainerProgramSkip(date: Date(), sessionKey: "k", summary: "Skipped Mon")]
        context.insert(program)
        try context.save()
        let snapshot = TrainerProgramSnapshot(program)

        context.delete(program)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainerProgram>()), 0)

        let back = snapshot.restore(in: context)
        try context.save()
        XCTAssertEqual(back.id, program.id)
        XCTAssertEqual(back.name, "Block A")
        XCTAssertEqual(back.weeks, [ProgramWeek(id: snapshot.weeks[0].id, days: [day])])
        XCTAssertFalse(back.repeats)
        XCTAssertTrue(back.isActive)
        XCTAssertEqual(back.sourceText, "Mon: push")
        XCTAssertEqual(back.autoWarmups, false)
        XCTAssertEqual(back.scheduleMode, .fixed)
        XCTAssertEqual(back.cadence, .weekly)
        XCTAssertEqual(back.endedAt, snapshot.endedAt)
        XCTAssertEqual(back.skippedSessions.map(\.summary), ["Skipped Mon"])
        XCTAssertEqual(back.startDate, snapshot.startDate)
        XCTAssertEqual(back.createdAt, snapshot.createdAt)
        // A double tap does not make a second copy.
        snapshot.restore(in: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainerProgram>()), 1)
    }

    func testARestoredProgramDoesNotFightAnotherActiveOne() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = TrainerProgram(
            name: "Old", startDate: Date(), weeks: [ProgramWeek(days: [])],
            isActive: true, sourceKind: "text"
        )
        context.insert(program)
        try context.save()
        let snapshot = TrainerProgramSnapshot(program)
        context.delete(program)
        let newer = TrainerProgram(
            name: "New", startDate: Date(), weeks: [ProgramWeek(days: [])],
            isActive: true, sourceKind: "text"
        )
        context.insert(newer)
        try context.save()

        let back = snapshot.restore(in: context)
        try context.save()
        XCTAssertFalse(back.isActive, "only one program is active at a time")
        XCTAssertTrue(newer.isActive)
    }

    func testACustomExerciseComesBackWithItsHistoryRecordsAndSessions() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let custom = Exercise(
            name: "Zercher Squat", muscleGroup: .quads, secondaryMuscles: [.glutes],
            equipment: .barbell, movementPattern: .squat, isCompound: true, isCustom: true,
            instructions: "Bar in the elbows", cues: ["Chest up"]
        )
        custom.preferredRestSeconds = 150
        context.insert(custom)
        let plan = WorkoutPlan(date: Date().addingTimeInterval(-86400), type: .legs)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: custom)
        slot.sets = [PlannedSet(setNumber: 1, targetReps: 5, targetWeight: 100, plannedExercise: slot)]
        let history = ExerciseHistory(date: Date(), estimated1RM: 130, exercise: custom)
        context.insert(history)
        let record = PersonalRecord(type: .oneRepMax, value: 130, date: Date(), exercise: custom)
        context.insert(record)
        try context.save()
        let snapshot = ExerciseSnapshot(custom)

        context.delete(custom)
        try context.save()
        XCTAssertNil(slot.exercise)
        XCTAssertNil(history.exercise)
        XCTAssertNil(record.exercise)

        let back = snapshot.restore(in: context)
        try context.save()
        XCTAssertEqual(back.id, snapshot.id)
        XCTAssertEqual(back.name, "Zercher Squat")
        XCTAssertEqual(back.muscleGroup, .quads)
        XCTAssertEqual(back.secondaryMuscles, [.glutes])
        XCTAssertEqual(back.equipment, .barbell)
        XCTAssertEqual(back.movementPattern, .squat)
        XCTAssertTrue(back.isCustom)
        XCTAssertEqual(back.preferredRestSeconds, 150)
        XCTAssertEqual(back.instructions, "Bar in the elbows")
        XCTAssertEqual(back.cues, ["Chest up"])
        XCTAssertEqual(slot.exercise?.id, back.id)
        XCTAssertEqual(history.exercise?.id, back.id)
        XCTAssertEqual(record.exercise?.id, back.id)
        XCTAssertEqual(back.plannedExercises?.count, 1)
        // A double tap does not make a second exercise.
        snapshot.restore(in: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }
}
