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
    ///
    /// §11 fix — when the PHONE's own session is live and sitting on exactly
    /// this (exercise, set), route through `logSet` (the same function the
    /// phone's Finish Set button calls) instead of a thinner parallel path.
    /// That's what keeps PR detection, the eager SetFeedback row, the rest
    /// timer, and the exercise/set cursor all in sync — the old direct-mutate
    /// path never advanced the phone's cursor, so a phone tap right after a
    /// watch log re-completed (and overwrote) the SAME set with stale phone
    /// input values. Off the phone's exact cursor (no live session, or it has
    /// moved elsewhere), fall back to the simple direct completion.
    @discardableResult
    func applyWatchSetLog(
        exerciseName: String,
        reps: Int?,
        weightKg: Double?,
        modelContext: ModelContext
    ) -> Bool {
        guard let plan = todayPlan,
              plan.status == .planned || plan.status == .inProgress,
              let exerciseIndex = plan.orderedExercises.firstIndex(where: { $0.exercise?.name == exerciseName })
        else {
            return false
        }
        let slot = plan.orderedExercises[exerciseIndex]
        guard let setIndex = slot.orderedSets.firstIndex(where: { !$0.isWarmup && !$0.completed }) else {
            return false
        }
        let set = slot.orderedSets[setIndex]
        let resolvedWeight = weightKg ?? set.targetWeight ?? 0
        let resolvedReps = reps ?? set.targetReps

        if sessionState.isActive, currentExerciseIndex == exerciseIndex, currentSetIndex == setIndex {
            logSet(weight: resolvedWeight, reps: resolvedReps, modelContext: modelContext)
            NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
            pushWorkoutToWatch()
            return true
        }

        if plan.status == .planned {
            plan.status = .inProgress
            plan.startedAt = plan.startedAt ?? Date()
        }
        set.actualReps = resolvedReps
        set.actualWeight = resolvedWeight
        set.completed = true
        set.completedAt = Date()

        // Mirror logSet's PR detection + eager feedback row so a watch-only
        // log (phone not looking at this session) carries the same signal a
        // phone-logged one does.
        if !set.isWarmup, !set.isDropStep, let exercise = slot.exercise,
           let pr = trainingEngine.detectPersonalRecord(
               exercise: exercise, weight: resolvedWeight, reps: resolvedReps,
               workoutPlanID: plan.id
           )
        {
            modelContext.insert(pr)
            detectedPRs.append(pr)
            HapticManager.notification(.success)
        }
        if !set.isWarmup {
            let feedback = SetFeedback(plannedSet: set, rpe: 7)
            modelContext.insert(feedback)
            set.rpe = feedback.rpe
        }

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
