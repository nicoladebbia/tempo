//
// SetCursorTests.swift
// Tempo
//
// QA bugs E + F — after the guided warm-up the cursor jumped past exercise 1's
// ramp sets, leaving them uncompleted behind it, so a crash-resume landed on a
// warm-up instead of the next working set; and the rest screen counted
// warm-ups as sets ("next: set 4 of 6") while the set screen said "Set 1 of 4".
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SetCursorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    /// Row: 2 ramp sets + 4 working sets.
    private func seedRampedPlan(context: ModelContext) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .pull)
        plan.status = .inProgress
        context.insert(plan)
        let row = Exercise(name: "Barbell Row", muscleGroup: .back, equipment: .barbell,
                           movementPattern: .horizontalPull, isCompound: true)
        context.insert(row)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: row)
        var sets = [
            PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 30, isWarmup: true, plannedExercise: slot),
            PlannedSet(setNumber: 2, targetReps: 8, targetWeight: 45, isWarmup: true, plannedExercise: slot),
        ]
        sets += (3 ... 6).map { PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 60, plannedExercise: slot) }
        slot.sets = sets
        try? context.save()
        return plan
    }

    func testGuidedWarmupLandsOnFirstRampSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedRampedPlan(context: context)
        vm.sessionState = .warmup(exerciseIndex: 0, warmupSetIndex: 0)

        vm.advancePastWarmup()

        XCTAssertEqual(vm.currentSetIndex, 0, "Ramp sets are done (or explicitly skipped), never silently jumped")
        XCTAssertEqual(vm.setCountText, "Warmup 1 of 2")
        vm.resetState()
    }

    func testResumeLandsOnFirstUncompletedSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedRampedPlan(context: context)
        let sets = plan.orderedExercises[0].orderedSets
        // Ramps never done; first working set logged.
        sets[2].completed = true
        sets[2].actualWeight = 60
        sets[2].actualReps = 8
        plan.startedAt = Date().addingTimeInterval(-300)
        try context.save()
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.resumeFromCrash()

        XCTAssertEqual(vm.currentSetIndex, 0, "Cursor = first set not done, not 'completed count'")
        vm.resetState()
    }

    func testStartWithLoggedSetsResumesInsteadOfResetting() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedRampedPlan(context: context)
        for set in plan.orderedExercises[0].orderedSets.prefix(3) {
            set.completed = true
        }
        plan.startedAt = Date().addingTimeInterval(-300)
        try context.save()
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        XCTAssertTrue(vm.startWorkout())

        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 3)),
                       "Start after a crash must continue at the first open set, not re-run the warm-up onto a done set")
        vm.resetState()
    }

    func testCountersAgreeOnWorkingSetNumbering() throws {
        let context = try makeContext()
        let sets = seedRampedPlan(context: context).orderedExercises[0].orderedSets

        XCTAssertEqual(TrainingViewModel.setPositionText(in: sets, at: 0), "Warmup 1 of 2")
        XCTAssertEqual(TrainingViewModel.setPositionText(in: sets, at: 2), "Set 1 of 4")
        XCTAssertEqual(TrainingViewModel.setPositionText(in: sets, at: 3, capitalized: false), "set 2 of 4")
        XCTAssertEqual(TrainingViewModel.setPositionText(in: sets, at: 5), "Set 4 of 4")
    }

    func testRestLabelPointsAtNextWorkingSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedRampedPlan(context: context)
        vm.todayPlan = plan
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 2
        plan.orderedExercises[0].orderedSets[2].completed = true

        XCTAssertEqual(vm.restContext.label, "Barbell Row · next: set 2 of 4")
    }
}
