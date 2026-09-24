//
// ExerciseDeletionTests.swift
// Tempo
//
// §1 — deleting a custom Exercise must NOT erase the training record it
// produced. `Exercise.plannedExercises` / `.history` / `.personalRecords` were
// `.cascade`, so deleting the exercise silently deleted every past
// PlannedExercise/PlannedSet, ExerciseHistory and PersonalRecord that ever
// referenced it — directly contradicting ExerciseDetailView's own delete
// confirmation ("Past sessions that used it keep their logged sets, but lose
// the exercise name"). Now `.nullify`; readers fall back to a name snapshot.
//
// Also confirms the schema change is migration-safe: `TempoModelContainer`
// (the app's real, full schema) opens an in-memory store with the new
// `.nullify` rules with no error.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ExerciseDeletionTests: XCTestCase {
    func testDeletingCustomExercisePreservesHistorySetsAndPRs() throws {
        // Uses the app's REAL schema (TempoModelContainer), not a narrow test
        // schema — this is what proves the `.cascade` → `.nullify` change
        // opens cleanly (no migration needed for a delete-rule-only change).
        let container = try TempoModelContainer.create(inMemory: true)
        let context = ModelContext(container)

        let exercise = Exercise(
            name: "Landmine Press", muscleGroup: .chest,
            equipment: .barbell, movementPattern: .horizontalPush,
            isCompound: true, isCustom: true
        )
        context.insert(exercise)

        let sessionDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        let plan = WorkoutPlan(date: sessionDate, type: .push, status: .completed)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        context.insert(slot)
        let set = PlannedSet(
            setNumber: 1, targetReps: 8, targetWeight: 60,
            actualReps: 8, actualWeight: 60, completed: true, plannedExercise: slot
        )
        context.insert(set)
        let history = ExerciseHistory(
            date: sessionDate, estimated1RM: 75, totalVolume: 480,
            bestSetWeight: 60, bestSetReps: 8, workoutPlanID: plan.id, exercise: exercise
        )
        context.insert(history)
        let pr = PersonalRecord(
            type: .oneRepMax, value: 75, date: sessionDate, workoutPlanID: plan.id, exercise: exercise
        )
        context.insert(pr)
        try context.save()

        let historyID = history.id
        let prID = pr.id
        let setID = set.id
        let slotID = slot.id

        // The delete under test.
        context.delete(exercise)
        try context.save()

        let survivingHistory = try context.fetch(
            FetchDescriptor<ExerciseHistory>(predicate: #Predicate<ExerciseHistory> { $0.id == historyID })
        )
        XCTAssertEqual(survivingHistory.count, 1, "ExerciseHistory must survive deleting its exercise")
        XCTAssertNil(survivingHistory.first?.exercise, "the pointer is nullified, not the row")
        XCTAssertEqual(survivingHistory.first?.displayName, "Landmine Press", "falls back to the name snapshot")

        let survivingPR = try context.fetch(
            FetchDescriptor<PersonalRecord>(predicate: #Predicate<PersonalRecord> { $0.id == prID })
        )
        XCTAssertEqual(survivingPR.count, 1, "PersonalRecord must survive deleting its exercise")
        XCTAssertNil(survivingPR.first?.exercise)
        XCTAssertEqual(survivingPR.first?.displayName, "Landmine Press")

        let survivingSlot = try context.fetch(
            FetchDescriptor<PlannedExercise>(predicate: #Predicate<PlannedExercise> { $0.id == slotID })
        )
        XCTAssertEqual(survivingSlot.count, 1, "the past session's exercise slot must survive")
        XCTAssertEqual(survivingSlot.first?.displayName, "Landmine Press")

        let survivingSet = try context.fetch(
            FetchDescriptor<PlannedSet>(predicate: #Predicate<PlannedSet> { $0.id == setID })
        )
        XCTAssertEqual(survivingSet.count, 1, "the logged set itself must survive")
        XCTAssertEqual(survivingSet.first?.actualWeight, 60)
        XCTAssertEqual(survivingSet.first?.actualReps, 8)
    }

    func testDisplayNamePrefersLiveExerciseThenSnapshotThenRemovedLabel() {
        let exercise = Exercise(
            name: "Cable Fly", muscleGroup: .chest,
            equipment: .cable, movementPattern: .horizontalPush,
            isCompound: false, isCustom: true
        )
        let plan = WorkoutPlan(date: .now, type: .push)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)

        XCTAssertEqual(slot.displayName, "Cable Fly", "live exercise wins")

        slot.exercise = nil // simulates the exercise having been deleted (nullify)
        XCTAssertEqual(slot.displayName, "Cable Fly", "falls back to the snapshot captured at creation")

        let legacySlot = PlannedExercise(order: 1, workoutPlan: plan)
        XCTAssertEqual(legacySlot.displayName, "Removed exercise", "no exercise and no snapshot")
    }

    /// A slot's `exercise` can be repointed after creation (an exercise SWAP,
    /// in TrainingViewModel+ExercisePopulation.swift), which the init-time
    /// snapshot capture alone never sees. `displayName` must self-heal the
    /// stale snapshot the moment it's read with the new exercise still live —
    /// otherwise deleting the SWAPPED-TO exercise later would fall back to the
    /// ORIGINAL (wrong) exercise's name instead of the new one.
    func testDisplayNameSelfHealsTheSnapshotAfterAnExerciseSwap() {
        let original = Exercise(
            name: "Barbell Row", muscleGroup: .back,
            equipment: .barbell, movementPattern: .horizontalPull, isCompound: true
        )
        let swappedTo = Exercise(
            name: "Cable Row", muscleGroup: .back,
            equipment: .cable, movementPattern: .horizontalPull, isCompound: true, isCustom: true
        )
        let plan = WorkoutPlan(date: .now, type: .pull)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: original)
        XCTAssertEqual(slot.displayName, "Barbell Row")

        // Simulates swapExercise repointing `.exercise` directly.
        slot.exercise = swappedTo
        XCTAssertEqual(slot.displayName, "Cable Row", "the swap must win immediately")

        // The swapped-to exercise is later deleted (nullify fires).
        slot.exercise = nil
        XCTAssertEqual(
            slot.displayName, "Cable Row",
            "must fall back to the SWAPPED-TO name, not the original one, because displayName re-synced the snapshot while it was still live"
        )
    }
}
