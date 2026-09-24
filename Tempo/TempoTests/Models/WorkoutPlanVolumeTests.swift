//
// WorkoutPlanVolumeTests.swift
// Tempo
//
// §14 — `WorkoutPlan.totalVolume` was missing the `!isWarmup` rule that
// `PlannedExercise.totalVolume` already has, so a warmup ramp set inflated
// every workout's tonnage (the session stat, MonthlyReviewAggregator's
// tonnage, the Dashboard Move quadrant and WorkoutHistoryView all read this
// SAME computed property, so fixing it here fixes all of them at once).
// Drop steps must still count — they're reduced-weight work, not "not work",
// per the §6.4 drop-set design — so `WorkoutPlan.totalVolume` must match
// `PlannedExercise.totalVolume` EXACTLY: exclude only warmups.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WorkoutPlanVolumeTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([WorkoutPlan.self, Exercise.self, PlannedExercise.self, PlannedSet.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func completedSet(
        weight: Double, reps: Int, isWarmup: Bool = false, isDropStep: Bool = false, plannedExercise: PlannedExercise
    ) -> PlannedSet {
        PlannedSet(
            setNumber: 1, targetReps: reps, actualReps: reps, actualWeight: weight,
            completed: true, isWarmup: isWarmup,
            dropStepIndex: isDropStep ? 1 : nil, plannedExercise: plannedExercise
        )
    }

    func testWarmupSetsAreExcludedFromWorkoutPlanTotalVolume() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .push)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        context.insert(slot)
        let warmup = completedSet(weight: 40, reps: 10, isWarmup: true, plannedExercise: slot)
        let working = completedSet(weight: 100, reps: 5, plannedExercise: slot)
        slot.sets = [warmup, working]
        plan.exercises = [slot]
        try context.save()

        XCTAssertEqual(plan.totalVolume, 500, "only the working set's 100x5 counts — the warmup's 40x10 must not")
    }

    func testDropStepsStillCountTowardWorkoutPlanTotalVolume() throws {
        // §6.4 — a drop step is a reduced-weight backoff, excluded from
        // PR/e1RM, but it's still real work performed and DOES count toward
        // volume — same rule PlannedExercise.totalVolume already applies.
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .push)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        context.insert(slot)
        let topSet = completedSet(weight: 100, reps: 5, plannedExercise: slot)
        let dropStep = completedSet(weight: 80, reps: 5, isDropStep: true, plannedExercise: slot)
        slot.sets = [topSet, dropStep]
        plan.exercises = [slot]
        try context.save()

        XCTAssertEqual(plan.totalVolume, 900, "100x5 (500) + drop step 80x5 (400) = 900")
    }

    func testMatchesPlannedExerciseTotalVolumeExactly() throws {
        // The two computed properties must apply the SAME filter — this is
        // the exact bug: WorkoutPlan.totalVolume didn't re-derive each
        // exercise's volume via PlannedExercise.totalVolume, so it drifted
        // from it. Assert they agree on a mixed warmup+drop+working set.
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .push)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        context.insert(slot)
        slot.sets = [
            completedSet(weight: 40, reps: 10, isWarmup: true, plannedExercise: slot),
            completedSet(weight: 100, reps: 5, plannedExercise: slot),
            completedSet(weight: 80, reps: 5, isDropStep: true, plannedExercise: slot),
        ]
        plan.exercises = [slot]
        try context.save()

        XCTAssertEqual(plan.totalVolume, slot.totalVolume)
    }
}
