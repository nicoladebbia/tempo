//
// PlannedSetPerSideVolumeTests.swift
// Tempo
//
// Fix #9 — a unilateral (per-side) set's TRUE tonnage covers both sides
// (load × reps × 2), but its e1RM/PR must read the single-side reps as-is,
// never doubled. `PlannedExercise.totalVolume` and `WorkoutPlan.totalVolume`
// both delegate to `PlannedSet.volume`, so covering that one property here
// covers every volume reader (Dashboard Move quadrant, Arena/history charts,
// MonthlyReview tonnage) at the source.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PlannedSetPerSideVolumeTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([WorkoutPlan.self, Exercise.self, PlannedExercise.self, PlannedSet.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func loggedSet(
        weight: Double, reps: Int, isWarmup: Bool = false, plannedExercise: PlannedExercise
    ) -> PlannedSet {
        PlannedSet(
            setNumber: 1, targetReps: reps, actualReps: reps, actualWeight: weight,
            completed: true, isWarmup: isWarmup, plannedExercise: plannedExercise
        )
    }

    // MARK: - Volume

    func testBilateralSetVolumeIsUnchanged() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .push)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        context.insert(slot)
        let set = loggedSet(weight: 100, reps: 5, plannedExercise: slot)
        slot.sets = [set]
        plan.exercises = [slot]
        try context.save()

        XCTAssertFalse(slot.perSide)
        XCTAssertEqual(set.volume, 500, "bilateral: unaffected by Fix #9")
    }

    func testPerSideSetVolumeDoublesWithoutASplit() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .pull)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        slot.perSide = true
        context.insert(slot)
        // Trainer wrote "SA DB Row 3x8 each" — the athlete logs ONE entry of
        // 20kg x 8, meaning 8 reps EACH side.
        let set = loggedSet(weight: 20, reps: 8, plannedExercise: slot)
        slot.sets = [set]
        plan.exercises = [slot]
        try context.save()

        XCTAssertEqual(set.volume, 320, "20kg x 8 reps x BOTH sides = 320, not 160")
    }

    func testPerSideSetVolumeSumsLoggedLRSplit() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .pull)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        slot.perSide = true
        context.insert(slot)
        let set = loggedSet(weight: 20, reps: 8, plannedExercise: slot)
        // The athlete logged an uneven set: left hit 8, right only managed 7.
        set.actualRepsLeft = 8
        set.actualRepsRight = 7
        slot.sets = [set]
        plan.exercises = [slot]
        try context.save()

        XCTAssertEqual(set.volume, 300, "20kg x (8+7) = 300 — the REAL split, not 20 x 8 x 2 = 320")
    }

    func testPlannedExerciseTotalVolumeAppliesPerSideAndExcludesWarmup() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .pull)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        slot.perSide = true
        context.insert(slot)
        let warmup = loggedSet(weight: 10, reps: 8, isWarmup: true, plannedExercise: slot)
        let working1 = loggedSet(weight: 20, reps: 8, plannedExercise: slot)
        let working2 = loggedSet(weight: 20, reps: 8, plannedExercise: slot)
        slot.sets = [warmup, working1, working2]
        plan.exercises = [slot]
        try context.save()

        XCTAssertEqual(slot.totalVolume, 640, "two per-side working sets: (20x8x2) x 2 = 640; warmup excluded")
    }

    func testWorkoutPlanTotalVolumeDelegatesAndCoversPerSide() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .pull)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        slot.perSide = true
        context.insert(slot)
        let set = loggedSet(weight: 20, reps: 8, plannedExercise: slot)
        slot.sets = [set]
        plan.exercises = [slot]
        try context.save()

        XCTAssertEqual(plan.totalVolume, slot.totalVolume, "must stay in lockstep — now literally the same code")
        XCTAssertEqual(plan.totalVolume, 320)
    }

    // MARK: - e1RM / PR — never doubled

    func testPerSideSetEstimated1RMUsesSingleSideRepsNotDoubled() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: .now, type: .pull)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan)
        slot.perSide = true
        context.insert(slot)
        let set = loggedSet(weight: 20, reps: 8, plannedExercise: slot)
        slot.sets = [set]
        plan.exercises = [slot]
        try context.save()

        let expectedE1RM = 20 * (1 + 8.0 / 30.0)
        XCTAssertEqual(set.estimated1RM ?? 0, expectedE1RM, accuracy: 0.001, "single-side Epley e1RM — no ×2")
        // Sanity: the SAME formula bilateral would use, off the SAME reps —
        // proves the per-side flag never touches this computation.
        let bilateralSlot = PlannedExercise(order: 1, workoutPlan: plan)
        context.insert(bilateralSlot)
        let bilateralSet = loggedSet(weight: 20, reps: 8, plannedExercise: bilateralSlot)
        bilateralSlot.sets = [bilateralSet]
        XCTAssertEqual(set.estimated1RM, bilateralSet.estimated1RM)
    }
}
