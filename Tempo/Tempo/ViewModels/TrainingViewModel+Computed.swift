//
// TrainingViewModel+Computed.swift
// Tempo
//
// Display-value computed properties (current exercise/set, volume,
// elapsed/rest formatting, rest context, day-state flags), split out of
// TrainingViewModel.swift to keep that file under the SwiftLint length
// caps. Pure VM behavior — same instance members, hosted in an extension.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Computed Properties

    // Per MODULE_TRAINING.md Section 2 — Display values

    var currentExercise: PlannedExercise? {
        guard let plan = todayPlan else {
            return nil
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return nil
        }
        return exercises[currentExerciseIndex]
    }

    var currentSet: PlannedSet? {
        guard let exercise = currentExercise else {
            return nil
        }
        let sets = exercise.orderedSets
        guard currentSetIndex < sets.count else {
            return nil
        }
        return sets[currentSetIndex]
    }

    var totalExercises: Int {
        todayPlan?.orderedExercises.count ?? 0
    }

    var totalSets: Int {
        todayPlan?.totalSets ?? 0
    }

    var completedSets: Int {
        todayPlan?.completedSets ?? 0
    }

    var totalVolume: Double {
        todayPlan?.totalVolume ?? 0
    }

    var formattedVolume: String {
        // totalVolume is kg-stored; show in the user's unit.
        let vol = WeightUnit.kg.convert(totalVolume, to: weightUnit)
        let unit = weightUnit.abbreviation
        if vol >= 1000 {
            return String(format: "%.1fk %@", vol / 1000, unit)
        }
        return "\(Int(vol)) \(unit)"
    }

    /// Working-set count for the current exercise (excludes warmup) so the
    /// +/- stepper matches the "Set X of N" header.
    var workingSetCount: Int {
        (currentExercise?.orderedSets ?? []).filter { !$0.isWarmup }.count
    }

    var formattedElapsedTime: String {
        let total = Int(elapsedSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedRestTimer: String {
        let remaining = Int(restTimerRemaining)
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var restTimerProgress: Double {
        guard restTimerTotal > 0 else {
            return 0
        }
        return 1.0 - (restTimerRemaining / restTimerTotal)
    }

    var setCountText: String {
        guard let exercise = currentExercise else {
            return ""
        }
        let sets = exercise.orderedSets
        let total = sets.count

        // Indicate if current set is a warmup
        if currentSetIndex < sets.count, sets[currentSetIndex].isWarmup {
            let warmupCount = sets.filter(\.isWarmup).count
            let warmupIndex = sets.prefix(currentSetIndex + 1).filter(\.isWarmup).count
            return "Warmup \(warmupIndex) of \(warmupCount)"
        }

        let workingSets = sets.filter { !$0.isWarmup }
        let workingIndex = currentSetIndex - sets.filter(\.isWarmup).count + 1
        if workingSets.count < total {
            return "Set \(workingIndex) of \(workingSets.count)"
        }
        return "Set \(currentSetIndex + 1) of \(total)"
    }

    /// Context for the rest screen: what the user is resting *toward*.
    /// During between-sets rest this is the current exercise; during the rest
    /// before the next exercise it is the upcoming exercise (so the screen can
    /// preview its name + how-to instead of mislabelling it "Current:").
    struct RestContext {
        let exercise: Exercise?
        /// True when rest leads into a different exercise (show full how-to).
        let isExerciseTransition: Bool
        /// Short label, e.g. "Next: Set 2 of 4" or "Up next".
        let label: String
        let instructions: String?
        let cues: [String]
    }

    var restContext: RestContext {
        let exercises = todayPlan?.orderedExercises ?? []
        // §6 superset rest — the pair's one rest leads to an explicit target
        // (back to the first lift, or the exercise after a finished pair).
        if case let .supersetJump(exIdx, setIdx) = pendingRestAction {
            let target = exIdx < exercises.count ? exercises[exIdx] : nil
            let ex = target?.exercise
            let total = target?.orderedSets.count ?? 0
            let isTransition = exIdx != currentExerciseIndex
            return RestContext(
                exercise: ex,
                isExerciseTransition: isTransition,
                label: ex.map { "Next: \($0.name) · set \(min(setIdx + 1, max(total, 1))) of \(total)" }
                    ?? "Up next",
                instructions: isTransition ? ex?.instructions : nil,
                cues: isTransition ? (ex?.cues ?? []) : []
            )
        }
        if pendingRestAction == .nextExercise {
            let nextIndex = currentExerciseIndex + 1
            let next = nextIndex < exercises.count ? exercises[nextIndex] : nil
            let ex = next?.exercise
            return RestContext(
                exercise: ex,
                isExerciseTransition: true,
                label: ex.map { "Up next: \($0.name)" } ?? "Up next",
                instructions: ex?.instructions,
                cues: ex?.cues ?? []
            )
        } else {
            let ex = currentExercise?.exercise
            // Resting between sets — the next set is currentSetIndex + 1.
            let total = currentExercise?.orderedSets.count ?? 0
            let nextSetNumber = min(currentSetIndex + 2, total)
            return RestContext(
                exercise: ex,
                isExerciseTransition: false,
                label: ex.map { "\($0.name) · next: set \(nextSetNumber) of \(total)" } ?? "",
                instructions: nil,
                cues: []
            )
        }
    }

    var workoutTypeDisplayName: String {
        todayPlan?.type.displayName ?? "Rest"
    }

    var isRestDay: Bool {
        guard let plan = todayPlan else {
            return true
        }
        return plan.type == .rest || plan.type == .mobility
    }

    /// Whether today's plan is a loggable gym session — the ONLY case where a
    /// "Start Workout" button makes sense. Non-gym days (football, run, sprint,
    /// conditioning, mobility, rest) have no exercises to log, so the button is
    /// hidden for them. This is stricter than `!isRestDay`, which only excludes
    /// rest/mobility and wrongly left the button visible on football/run days.
    var canStartWorkout: Bool {
        guard let plan = todayPlan else {
            return false
        }
        return plan.type.isGymWorkout
    }

    var recoveryAdjustmentText: String? {
        guard let plan = todayPlan else {
            return nil
        }
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return nil
        }
        if adj >= 0.8 {
            return "Volume reduced 20% — Yellow recovery"
        }
        if adj >= 0.75 {
            return "Volume reduced 25%, lighter load — Yellow recovery"
        }
        return "Mobility session — Red recovery"
    }

    var stickyWeight: Double? {
        guard let exercise = currentExercise else {
            return nil
        }
        let sets = exercise.orderedSets
        guard currentSetIndex < sets.count else {
            return sets.last?.targetWeight
        }
        // Carry from the most recent WORKING set (skip ramps) so the first
        // working set pre-fills the working weight, not the 75% ramp. Fall back
        // to the current set's own target if no prior working set exists.
        for i in stride(from: currentSetIndex - 1, through: 0, by: -1) {
            let prev = sets[i]
            if !prev.isWarmup {
                return prev.actualWeight ?? prev.targetWeight
            }
        }
        return sets[currentSetIndex].targetWeight
    }
}
