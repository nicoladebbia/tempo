//
// WorkoutHistoryDeletionTests.swift
// Tempo
//
// §13 — deleting a workout used to leave `PersonalRecord` rows orphaned
// (`workoutPlanID` was never stamped at PR-creation time, so
// `WorkoutHistoryView`'s exact-match cleanup never fired), could delete the
// WRONG same-day workout's `ExerciseHistory` row (a day+exercise heuristic
// with no ID tiebreak), and never cleaned `PredictionLog` rows at all. Covers
// the extracted `WorkoutHistoryView.historyRowsToDelete` matching logic (the
// part that actually decides WHICH rows die) plus the "previous PR becomes
// current" behavior a deletion relies on.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WorkoutHistoryDeletionTests: XCTestCase {
    func testHistoryRowsToDeleteDoesNotCrossDeleteTheOtherSameDayWorkout() {
        let exercise = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        let day = Calendar.current.startOfDay(for: .now)

        let morningPush = WorkoutPlan(date: day, type: .push, status: .completed)
        let eveningPush = WorkoutPlan(date: day, type: .push, status: .completed)

        // Both workouts trained the SAME exercise the SAME day — the classic
        // trap for a day+exercise-only heuristic.
        let morningHistory = ExerciseHistory(
            date: day, bestSetWeight: 80, bestSetReps: 5, workoutPlanID: morningPush.id, exercise: exercise
        )
        let eveningHistory = ExerciseHistory(
            date: day, bestSetWeight: 85, bestSetReps: 5, workoutPlanID: eveningPush.id, exercise: exercise
        )
        let allHistory = [morningHistory, eveningHistory]

        let toDelete = WorkoutHistoryView.historyRowsToDelete(for: morningPush, allHistory: allHistory)

        XCTAssertEqual(
            toDelete.map(\.id), [morningHistory.id],
            "must delete ONLY the row stamped with the deleted plan's own ID"
        )
        XCTAssertFalse(
            toDelete.contains { $0.id == eveningHistory.id },
            "the OTHER same-day workout's row must survive"
        )
    }

    func testHistoryRowsToDeleteFallsBackToHeuristicForLegacyRowsWithNoWorkoutPlanID() throws {
        let schema = Schema([WorkoutPlan.self, Exercise.self, PlannedExercise.self, PlannedSet.self, ExerciseHistory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let exercise = Exercise(
            name: "Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        context.insert(exercise)
        let day = Calendar.current.startOfDay(for: .now)
        let plan = WorkoutPlan(date: day, type: .legs, status: .completed)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        context.insert(slot)

        // Legacy row: same day + same exercise, but no workoutPlanID (written
        // before that field existed).
        let legacyHistory = ExerciseHistory(date: day, bestSetWeight: 100, bestSetReps: 5, exercise: exercise)
        context.insert(legacyHistory)
        try context.save()

        let toDelete = WorkoutHistoryView.historyRowsToDelete(for: plan, allHistory: [legacyHistory])

        XCTAssertEqual(
            toDelete.map(\.id), [legacyHistory.id],
            "a legacy row with no workoutPlanID still falls back to the day+exercise heuristic"
        )
    }

    func testDeletedPRIsSupersededByThePreviousBestAutomatically() throws {
        let schema = Schema([Exercise.self, PersonalRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // "Current PR" is derived live (`Exercise.allTimePR` = max of
        // surviving rows) — there is no `isCurrent` flag to update, so
        // deleting the top PR must let the next-highest become current with
        // no extra bookkeeping.
        let exercise = Exercise(
            name: "Deadlift", muscleGroup: .back, equipment: .barbell,
            movementPattern: .hinge, isCompound: true
        )
        context.insert(exercise)
        let olderPR = PersonalRecord(type: .oneRepMax, value: 140, date: .now, exercise: exercise)
        let newerPR = PersonalRecord(type: .oneRepMax, value: 150, date: .now, exercise: exercise)
        context.insert(olderPR)
        context.insert(newerPR)
        try context.save()

        XCTAssertEqual(exercise.allTimePR, 150)

        context.delete(newerPR)
        try context.save()

        XCTAssertEqual(exercise.allTimePR, 140, "the previous best becomes current with no separate bookkeeping")
    }
}
