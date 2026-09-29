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
            // An exercise deleted from the library mid-plan can't be logged
            // from the wrist (logs match by library exercise) — leave it off.
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
                targetWeightKg: reference.targetWeight ?? 0,
                perSide: slot.perSide
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
        // A payload without a weight must not log 0 kg (that would also
        // poison PRs/e1RM): fall back to the prescription, then to the load
        // the athlete last used on this lift. Only a true bodyweight move may
        // resolve to 0; anything else with no usable number is refused.
        let lastLoggedKg = slot.orderedSets.last { $0.completed && ($0.actualWeight ?? 0) > 0 }?.actualWeight
        let fallbackKg = [set.targetWeight, lastLoggedKg].compactMap { $0 }.first { $0 > 0 }
        let isBodyweightMove = slot.exercise?.equipment == .bodyweight || slot.exercise?.equipment == .none
        guard let resolvedWeight = weightKg ?? fallbackKg ?? (isBodyweightMove ? 0 : nil) else {
            return false
        }
        let resolvedReps = reps ?? set.targetReps

        if sessionState.isActive, currentExerciseIndex == exerciseIndex, currentSetIndex == setIndex {
            logSet(weight: resolvedWeight, reps: resolvedReps, modelContext: modelContext)
            NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
            pushWorkoutToWatch()
            return true
        }

        let priorStatus = plan.status
        let priorStartedAt = plan.startedAt
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
        var insertedPR: PersonalRecord?
        var insertedFeedback: SetFeedback?
        if !set.isWarmup, !set.isDropStep, let exercise = slot.exercise,
           let pr = trainingEngine.detectPersonalRecord(
               exercise: exercise, weight: resolvedWeight, reps: resolvedReps,
               workoutPlanID: plan.id
           )
        {
            modelContext.insert(pr)
            insertedPR = pr
        }
        if !set.isWarmup {
            let feedback = SetFeedback(plannedSet: set, rpe: 7)
            modelContext.insert(feedback)
            set.rpe = feedback.rpe
            insertedFeedback = feedback
        }

        guard saveGuarded(modelContext, operation: "watch set") else {
            // Undo EVERYTHING the attempt touched — a PR/feedback row for a
            // set that isn't logged would otherwise stay in the context (and
            // get saved by the next unrelated save).
            set.completed = false
            set.completedAt = nil
            set.actualReps = nil
            set.actualWeight = nil
            set.rpe = nil
            if let insertedPR {
                modelContext.delete(insertedPR)
            }
            if let insertedFeedback {
                modelContext.delete(insertedFeedback)
            }
            plan.status = priorStatus
            plan.startedAt = priorStartedAt
            return false
        }
        if let insertedPR {
            detectedPRs.append(insertedPR)
            HapticManager.notification(.success)
        }
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        pushWorkoutToWatch()
        return true
    }
}
