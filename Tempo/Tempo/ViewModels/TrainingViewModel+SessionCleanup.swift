//
// TrainingViewModel+SessionCleanup.swift
// Tempo
//
// Session teardown / side-effect helpers split out of TrainingViewModel.swift
// (file-length guard): rolling back a discarded session's logged work, the
// "everything was skipped" exit, and the best-effort Apple Health write.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// Every set was skipped or removed and none logged: same rollback as
    /// `finishWorkout`'s zero-set guard. Skipping DELETES sets, so if the plan
    /// has no working sets left there is nothing to redo either — resolve the day as a
    /// user skip rather than leaving a hollow, restartable plan.
    func endSessionWithNothingLogged(plan: WorkoutPlan, modelContext: ModelContext) {
        discardActiveWorkout(modelContext: modelContext)
        if plan.orderedExercises.allSatisfy({ $0.orderedSets.allSatisfy(\.isWarmup) }) {
            if plan.isCompositeDay {
                // Football already happened: drop only the gym part.
                dropGymPart(of: plan, modelContext: modelContext)
                saveGuarded(modelContext, operation: "dropped gym part")
                NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
                return
            }
            plan.status = .skipped
            plan.skipReason = .userSkipped
            saveGuarded(modelContext, operation: "skipped workout")
            NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        }
    }

    /// Undo everything a session logged on `plan` so a redo starts clean: set
    /// actuals (incl. added load and the L/R split), their SetFeedback rows and
    /// any PersonalRecord stamped with this plan (a discarded session must not
    /// leave a PR for a lift that "never happened").
    func rollBackLoggedWork(of plan: WorkoutPlan, modelContext: ModelContext) {
        var rolledBackSetIDs: Set<UUID> = []
        for ex in plan.orderedExercises {
            for set in ex.orderedSets where set.completed {
                rolledBackSetIDs.insert(set.id)
                set.completed = false
                set.actualWeight = nil
                set.actualReps = nil
                set.actualRepsLeft = nil
                set.actualRepsRight = nil
                set.addedLoadKg = nil
                set.completedAt = nil
                set.rpe = nil
            }
        }
        // A rolled-back set's SetFeedback row would otherwise linger and
        // shadow the redo (the inline panel would show stale RPE/notes
        // from the discarded attempt on the very first re-log).
        if !rolledBackSetIDs.isEmpty {
            let allFeedback = (try? modelContext.fetch(FetchDescriptor<SetFeedback>())) ?? []
            for feedback in allFeedback where rolledBackSetIDs.contains(feedback.setID) {
                modelContext.delete(feedback)
            }
        }
        let planID = plan.id
        let prDescriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { $0.workoutPlanID == planID }
        )
        for pr in (try? modelContext.fetch(prDescriptor)) ?? [] {
            modelContext.delete(pr)
        }
    }

    /// Fire-and-forget Apple Health write for a finished gym session
    /// (traditional strength training). Authorization is enforced inside
    /// `HealthKitService.writeWorkout` (no-op when sharing isn't granted) and
    /// it de-dupes on start time; any error is swallowed — a Health hiccup
    /// must never affect the saved workout. Active energy isn't known for a
    /// gym session, so it is left 0 (HealthKit then estimates none).
    func writeStrengthWorkoutToHealthKit(plan: WorkoutPlan, totalVolumeKg: Double) {
        let end = plan.finishedAt ?? Date()
        // The live session clock; if it never ran in this VM (0), fall back
        // to wall-clock minus recorded pauses.
        let wallClock = plan.startedAt.map { end.timeIntervalSince($0) - plan.pausedSeconds } ?? 0
        let durationSeconds = max(60, elapsedSeconds > 0 ? elapsedSeconds : wallClock)
        let start = plan.startedAt ?? end.addingTimeInterval(-durationSeconds)
        let sample = WorkoutSample(
            startDate: start,
            endDate: max(end, start),
            workoutType: "strength",
            durationMinutes: durationSeconds / 60,
            activeCalories: 0,
            averageHeartRate: nil,
            maxHeartRate: nil,
            distanceMeters: nil,
            totalVolumeKg: totalVolumeKg > 0 ? totalVolumeKg : nil
        )
        let healthKit = healthKit
        healthKitWriteTask = Task {
            try? await healthKit.writeWorkout(sample)
        }
    }

    /// After a structural change (a set removed), never leave the cursor on a
    /// missing or shifted set. A surviving cursor set keeps its identity
    /// (index re-derived); a deleted one routes like a skip. While RESTING
    /// nothing else is needed — `advanceAfterRest` re-resolves the target.
    func reanchorCursor(
        keeping setID: UUID?,
        in slot: PlannedExercise,
        plan: WorkoutPlan,
        modelContext: ModelContext
    ) {
        let sets = slot.orderedSets
        if let setID, let newIndex = sets.firstIndex(where: { $0.id == setID }) {
            currentSetIndex = newIndex
            if case .exercise(.setActive) = sessionState {
                sessionState = .exercise(.setActive(exerciseIndex: currentExerciseIndex, setIndex: newIndex))
            }
            return
        }
        if case .exercise(.setActive) = sessionState {
            advanceAfterSkip(in: slot, plan: plan, modelContext: modelContext)
        }
    }
}
