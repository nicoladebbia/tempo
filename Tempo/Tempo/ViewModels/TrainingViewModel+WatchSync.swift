//
// TrainingViewModel+WatchSync.swift
// Tempo
//
// §21 — the phone half of real watch sync. Builds the lightweight payload
// the watch runs on (replacing its hardcoded stubs) and applies set logs
// arriving from the wrist onto today's real plan. Split out of
// TrainingViewModel.swift to keep that file under the SwiftLint length caps.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Phone → Watch

    /// Today's plan condensed to what the wrist needs: working sets only
    /// (the watch never runs the warm-up ramp), targets taken from the next
    /// uncompleted set. nil when today isn't a loggable gym day — the watch
    /// shows its "open Tempo" empty state instead of stale data.
    func watchWorkoutPayload() -> WatchWorkoutPayload? {
        guard let plan = todayPlan,
              plan.type.isGymWorkout,
              plan.status == .planned || plan.status == .inProgress
        else {
            return nil
        }
        let exercises = plan.orderedExercises.compactMap { slot -> WatchWorkoutPayload.Exercise? in
            guard let exercise = slot.exercise else {
                return nil
            }
            let working = slot.orderedSets.filter { !$0.isWarmup }
            guard let reference = working.first(where: { !$0.completed }) ?? working.last else {
                return nil
            }
            return WatchWorkoutPayload.Exercise(
                name: exercise.name,
                totalSets: working.count,
                completedSets: working.filter(\.completed).count,
                targetReps: reference.targetReps,
                targetWeightKg: reference.targetWeight ?? 0
            )
        }
        guard !exercises.isEmpty else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return WatchWorkoutPayload(
            workoutType: plan.type.displayName.uppercased(),
            dayKey: formatter.string(from: plan.date),
            unit: weightUnit.rawValue,
            exercises: exercises,
            updatedAt: Date()
        )
    }

    /// Push the current queue to the watch. No-op on non-gym days.
    func pushWorkoutToWatch() {
        guard let payload = watchWorkoutPayload() else {
            return
        }
        PhoneWatchConnectivityService.shared.pushWorkout(payload)
    }

    // MARK: - Watch → Phone

    /// A set logged from the wrist: complete the named exercise's next
    /// uncompleted working set with the watch's actuals, persist through the
    /// guarded save, refresh cross-surfaces, and push the updated queue back
    /// (the bidirectional half). Unknown exercise or no open plan → no-op;
    /// the watch's local advance is cosmetic and re-syncs on next push.
    @discardableResult
    func applyWatchSetLog(
        exerciseName: String,
        reps: Int?,
        weightKg: Double?,
        modelContext: ModelContext
    ) -> Bool {
        guard let plan = todayPlan,
              plan.status == .planned || plan.status == .inProgress,
              let slot = plan.orderedExercises.first(where: { $0.exercise?.name == exerciseName }),
              let set = slot.orderedSets.first(where: { !$0.isWarmup && !$0.completed })
        else {
            return false
        }
        if plan.status == .planned {
            plan.status = .inProgress
            plan.startedAt = plan.startedAt ?? Date()
        }
        set.actualReps = reps ?? set.targetReps
        set.actualWeight = weightKg ?? set.targetWeight
        set.completed = true
        set.completedAt = Date()
        guard saveGuarded(modelContext, operation: "watch set") else {
            set.completed = false
            set.completedAt = nil
            set.actualReps = nil
            set.actualWeight = nil
            return false
        }
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        pushWorkoutToWatch()
        return true
    }
}
