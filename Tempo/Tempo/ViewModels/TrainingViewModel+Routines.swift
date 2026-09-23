//
// TrainingViewModel+Routines.swift
// Tempo
//
// "My routines" — save today's workout as a routine, and run a routine today.
// A routine fixes WHICH lifts, how many working sets and the groups; loads are
// always re-prescribed on apply (history + recovery + deload), the same
// builder swap/add use, so a routine never replays stale weights.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// Why a routine can't be applied today, or nil when it can.
    func routineBlocker(for plan: WorkoutPlan?) -> String? {
        guard let plan else {
            return "No workout planned today."
        }
        guard plan.type.isGymWorkout else {
            return "Today is a \(plan.type.displayName.lowercased()) day — routines run on gym days."
        }
        guard plan.status == .planned else {
            return "Today's workout already started."
        }
        return nil
    }

    /// Snapshot of today's plan as routine items (working sets only — ramps
    /// and drop steps are re-derived when the routine runs).
    static func routineItems(from plan: WorkoutPlan) -> [RoutineItem] {
        plan.orderedExercises.compactMap { slot in
            guard let exercise = slot.exercise else {
                return nil
            }
            let working = slot.orderedSets.filter { !$0.isWarmup && !$0.isDropStep }.count
            return RoutineItem(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                workingSets: max(1, working),
                group: slot.supersetGroup
            )
        }
    }

    @discardableResult
    func saveTodayAsRoutine(named name: String, modelContext: ModelContext) -> WorkoutRoutine? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let plan = todayPlan else {
            return nil
        }
        let items = Self.routineItems(from: plan)
        guard !items.isEmpty else {
            return nil
        }
        let routine = WorkoutRoutine(name: trimmed, items: items)
        modelContext.insert(routine)
        guard saveGuarded(modelContext, operation: "save routine") else {
            return nil
        }
        HapticManager.success()
        return routine
    }

    /// Replace today's (untouched) gym plan with the routine's lifts, each
    /// freshly prescribed. Returns false when blocked or nothing resolvable.
    @discardableResult
    func applyRoutine(_ routine: WorkoutRoutine, modelContext: ModelContext) -> Bool {
        guard routineBlocker(for: todayPlan) == nil, let plan = todayPlan else {
            return false
        }
        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let byID = Dictionary(library.map { ($0.id, $0) }) { first, _ in first }
        let resolved = routine.items.compactMap { item in byID[item.exerciseID].map { (item, $0) } }
        guard !resolved.isEmpty else {
            return false
        }

        for slot in plan.orderedExercises {
            if let id = slot.exercise?.id {
                deleteUnresolvedPrediction(planID: plan.id, exerciseID: id, modelContext: modelContext)
            }
            for set in slot.orderedSets {
                modelContext.delete(set)
            }
            modelContext.delete(slot)
        }
        plan.exercises = []

        for (order, pair) in resolved.enumerated() {
            let (item, exercise) = pair
            let slot = PlannedExercise(order: order, workoutPlan: plan, exercise: exercise)
            slot.supersetGroup = item.group
            slot.sets = prescribedSets(
                for: exercise,
                workingSets: max(1, item.workingSets),
                plan: plan,
                plannedExercise: slot,
                modelContext: modelContext
            )
        }
        routine.lastUsedAt = Date()
        guard saveGuarded(modelContext, operation: "apply routine") else {
            return false
        }
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        HapticManager.success()
        return true
    }
}
