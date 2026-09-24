//
// TrainingViewModel+TrainerProgram.swift
// Tempo
//
// Following the athlete's own trainer. While a TrainerProgram is active:
// - its sessions replace the generated gym days (type + exercises from the
//   trainer), other gym/conditioning days become rest — "your trainer's plan
//   plus your football";
// - Tempo still adjusts automatically: a red-recovery day stays mobility, a
//   match day stays football, the recovery multiplier and pain notes scale
//   the loads, and the daily coach/safety floor run as on any day.
// Tempo's scheduled deload is skipped on trainer days — the trainer owns the
// periodization.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// The one active trainer program, if any.
    func activeTrainerProgram(modelContext: ModelContext) -> TrainerProgram? {
        let descriptor = FetchDescriptor<TrainerProgram>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Overlay the active program on generated plans (mutates them in place).
    /// Pure apart from the plans themselves — unit-tested.
    nonisolated static func applyTrainerProgram(
        _ program: TrainerProgram,
        to plans: [WorkoutPlan],
        matchDayKeys: Set<Date>
    ) {
        let cal = Calendar.current
        for plan in plans {
            let day = cal.startOfDay(for: plan.date)
            // A dated match is a fixed commitment — the match day stays.
            if matchDayKeys.contains(day) {
                continue
            }
            // Red recovery: the engine already moved the day to mobility with
            // a zero multiplier — Tempo adjusts automatically, so keep it.
            let isRedRecoveryDay = plan.type == .mobility && plan.recoveryAdjustment == 0
            let sessions = program.sessions(on: plan.date)
            plan.programSecondaryKey = nil
            if let main = program.session(on: plan.date) {
                if isRedRecoveryDay {
                    plan.notes = "Recovery is low — your trainer's \(main.day.title ?? "session") is paused today."
                    plan.programSessionKey = nil
                    continue
                }
                plan.type = main.day.workoutType
                plan.programSessionKey = program.sessionKey(weekIndex: main.weekIndex, dayIndex: main.dayIndex)
                plan.notes = main.day.title ?? "Trainer session"
                // A second session the same day becomes the day's second part
                // (two-a-day): lift then shuttles, or two conditioning blocks.
                // Prefer a conditioning session after a lift.
                let others = sessions.filter { $0.dayIndex != main.dayIndex }
                if let second = others.first(where: { !$0.day.isStrength }) ?? others.first {
                    plan.secondarySessionType = second.day.workoutType
                    plan.programSecondaryKey = program.sessionKey(weekIndex: second.weekIndex, dayIndex: second.dayIndex)
                } else {
                    plan.secondarySessionType = nil
                }
            } else if !isRedRecoveryDay {
                plan.programSessionKey = nil
                switch plan.type {
                case .football,
                     .mobility,
                     .rest:
                    break // your sport / recovery stay as planned
                default:
                    plan.type = .rest
                    plan.notes = "Rest — not on your trainer's program."
                }
                plan.secondarySessionType = nil
            }
        }
    }

    /// The trainer's session behind a plan's key (main or second part), for
    /// display — e.g. a conditioning session's blocks on Today.
    func trainerDay(forKey key: String?, modelContext: ModelContext) -> ProgramDay? {
        guard let key,
              let programID = key.split(separator: "#").first.flatMap({ UUID(uuidString: String($0)) })
        else {
            return nil
        }
        let descriptor = FetchDescriptor<TrainerProgram>(predicate: #Predicate { $0.id == programID })
        return (try? modelContext.fetch(descriptor).first)?.day(forSessionKey: key)
    }

    /// Build a trainer-program day's exercises. Returns false when the session
    /// can't be resolved (program deleted/edited) so the caller falls back to
    /// the generated workout.
    func populateFromTrainerProgram(_ plan: WorkoutPlan, modelContext: ModelContext) -> Bool {
        guard let key = plan.programSessionKey,
              let programID = key.split(separator: "#").first.flatMap({ UUID(uuidString: String($0)) })
        else {
            return false
        }
        let descriptor = FetchDescriptor<TrainerProgram>(predicate: #Predicate { $0.id == programID })
        guard let program = try? modelContext.fetch(descriptor).first,
              let day = program.day(forSessionKey: key),
              !day.exercises.isEmpty
        else {
            return false
        }

        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        var byID = Dictionary(library.map { ($0.id, $0) }) { first, _ in first }
        var byName = Dictionary(library.map { (Self.normalizedName($0.name), $0) }) { first, _ in first }
        // §13 — the trainer never writes explicit warm-up sets; every isWarmup
        // set on a trainer day is one Tempo added. Off = build none of them.
        let includeWarmups = program.warmupsEnabled
        // §4 — needed to tell whether today's number differs from the
        // trainer's because of a pain-flagged note (vs. recovery alone).
        let signals = noteSignals(modelContext: modelContext)

        for (order, item) in day.exercises.enumerated() {
            let exercise: Exercise
            if let id = item.exerciseID, let known = byID[id] {
                exercise = known
            } else if let known = byName[Self.normalizedName(item.name)] {
                exercise = known
            } else {
                // Unmatched on import (or library changed since) — keep the
                // trainer's name as a custom exercise, editable in the library.
                exercise = Exercise(
                    name: item.name,
                    muscleGroup: .fullBody,
                    equipment: .none,
                    movementPattern: .isolation,
                    isCompound: false,
                    isCustom: true
                )
                modelContext.insert(exercise)
                byID[exercise.id] = exercise
                byName[Self.normalizedName(item.name)] = exercise
            }

            let slot = PlannedExercise(order: order, workoutPlan: plan, exercise: exercise)
            slot.supersetGroup = item.group
            slot.restSecondsOverride = item.restSeconds
            // Fix #9 — a real flag, not just baked-in note text: drives the
            // "/ side" reps copy and the ×2 volume rule everywhere a set's
            // tonnage is read (see PlannedSet.volume).
            slot.perSide = item.perSide == true
            slot.programNote = item.notes?.nilIfEmpty

            // §5 — a % with no reliable e1RM (or an isolation/machine lift) is
            // read as EFFORT, not a weight guess: no fixed weight, a
            // calibration first set, and an RIR derived from the Epley
            // reps-at-% relationship.
            let isEffort = Self.isEffortPercent(item, exercise: exercise)
            let trainerTargetKg = Self.programWeightKg(item, exercise: exercise)
            let rpeRIR = item.rpe.map { max(0, Int((10 - $0).rounded())) }
            let effortRIR = (isEffort ? item.percentOf1RM : nil)
                .map { Self.effortTargetRIR(percent: $0, targetReps: item.targetReps) }

            slot.sets = prescribedSets(
                for: exercise,
                workingSets: max(1, item.sets),
                plan: plan,
                plannedExercise: slot,
                modelContext: modelContext,
                targetReps: item.targetReps,
                fixedWeightKg: trainerTargetKg,
                targetRIR: rpeRIR ?? effortRIR,
                applyDeload: false,
                isEffortOnly: isEffort,
                includeWarmups: includeWarmups
            )

            // §4 — record the trainer's own number and why Tempo changed it
            // (if it did), so the adjustment is never a silent substitution.
            if let trainerTargetKg {
                slot.trainerTargetKg = trainerTargetKg
                slot.loadAdjustmentNote = Self.loadAdjustmentNote(
                    trainerTargetKg: trainerTargetKg,
                    appliedWorkingWeightKg: slot.sets?.first(where: { !$0.isWarmup })?.targetWeight,
                    recoveryAdjustment: plan.recoveryAdjustment,
                    isConservativeNote: signals[exercise.id]?.isConservative == true
                )
            }
        }
        return true
    }

    /// §5 post-calibration propagation — a calibration set (`PlannedSet.
    /// isCalibration`) just told us the athlete's real number. Derive an
    /// e1RM (Epley) from what was actually logged and set every remaining,
    /// not-yet-completed set on the SAME exercise to a target weight for ITS
    /// OWN reps, snapped to a loadable weight in the user's unit/equipment.
    func propagateCalibration(
        from set: PlannedSet,
        weight: Double,
        reps: Int,
        modelContext: ModelContext
    ) {
        guard let plannedExercise = set.plannedExercise, let exercise = plannedExercise.exercise else {
            return
        }
        let e1RM = StrengthStandards.epleyE1RM(weight: weight, reps: reps)
        guard e1RM > 0 else {
            return
        }
        let unit = currentWeightUnit(modelContext: modelContext)
        for remaining in plannedExercise.orderedSets where !remaining.completed && remaining.id != set.id {
            let target = StrengthStandards.inverseEpleyWeight(e1RM: e1RM, reps: remaining.targetReps)
            remaining.targetWeight = WeightConverter.loadableKg(target, equipment: exercise.equipment, unit: unit)
        }
    }

    /// §4 — restores the trainer's own number (`trainerTargetKg`) for this
    /// exercise's remaining, not-yet-completed sets today — warm-ups re-ramp
    /// off it (same 50%/75% split as generation), working sets take it
    /// directly, both snapped to a loadable weight. Records the override so
    /// Today/the summary can show it was used instead of Tempo's adjustment.
    func useTrainerWeight(for plannedExercise: PlannedExercise, modelContext: ModelContext) {
        guard let target = plannedExercise.trainerTargetKg, target > 0,
              let exercise = plannedExercise.exercise,
              let plan = plannedExercise.workoutPlan,
              plan.status == .planned || plan.status == .inProgress
        else {
            return
        }
        let unit = currentWeightUnit(modelContext: modelContext)
        let pendingWarmups = plannedExercise.orderedSets.filter { $0.isWarmup && !$0.completed }
        for (index, warmup) in pendingWarmups.enumerated() {
            let fraction = pendingWarmups.count == 2 ? (index == 0 ? 0.5 : 0.75) : 0.75
            warmup.targetWeight = WeightConverter.loadableKg(
                target * fraction, equipment: exercise.equipment, unit: unit
            )
        }
        for workingSet in plannedExercise.orderedSets where !workingSet.isWarmup && !workingSet.completed {
            workingSet.targetWeight = WeightConverter.loadableKg(target, equipment: exercise.equipment, unit: unit)
        }
        plannedExercise.trainerOverrideApplied = true
        saveGuarded(modelContext, operation: "trainer weight override")
        HapticManager.selection()
        // Today + the active workout read the plan's exercises directly.
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    /// The trainer's load in kg: explicit weight, else % of the lifter's
    /// RELIABLE estimated 1RM (§5 — ≥1 logged working set in the last ~90
    /// days), else nil. nil covers both "no % written" (Tempo prescribes from
    /// history) and "% written but unreadable as a weight" (§5 effort path —
    /// see `isEffortPercent`); an isolation/machine lift's % is NEVER read as
    /// e1RM × %, even with a reliable max on file.
    nonisolated static func programWeightKg(_ item: ProgramExercise, exercise: Exercise) -> Double? {
        if let weight = item.weightKg, weight > 0 {
            return weight
        }
        guard let pct = item.percentOf1RM, pct > 0, !isIsolationOrMachine(exercise) else {
            return nil
        }
        guard let e1RM = reliableEstimated1RM(for: exercise), e1RM > 0 else {
            return nil
        }
        return e1RM * min(pct, 1.1)
    }

    /// §5 — true when the trainer wrote a %1RM that must be read as an
    /// EFFORT target (RIR + calibration) rather than a weight: no explicit
    /// weight, and `programWeightKg` couldn't resolve a number for it (no
    /// reliable e1RM, or an isolation/machine lift).
    nonisolated static func isEffortPercent(_ item: ProgramExercise, exercise: Exercise) -> Bool {
        guard let pct = item.percentOf1RM, pct > 0, (item.weightKg ?? 0) <= 0 else {
            return false
        }
        return programWeightKg(item, exercise: exercise) == nil
    }

    /// Machine/cable equipment, or any non-compound (isolation) lift — §5:
    /// a "1RM" on a stack or an isolation movement isn't a real one-rep max,
    /// so a trainer's % on one is ALWAYS effort, never e1RM × %.
    nonisolated static func isIsolationOrMachine(_ exercise: Exercise) -> Bool {
        !exercise.isCompound || exercise.equipment == .machine || exercise.equipment == .cable
    }

    /// §5 reliability gate — the most recent logged e1RM for `exercise`, but
    /// ONLY if it came from a working set logged within the last ~90 days.
    /// A stale e1RM (last trained months ago) isn't trustworthy enough to
    /// read a trainer's % against.
    nonisolated static func reliableEstimated1RM(for exercise: Exercise, asOf date: Date = Date()) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: date) ?? .distantPast
        return exercise.history?
            .filter { $0.date >= cutoff && ($0.estimated1RM ?? 0) > 0 }
            .max { $0.date < $1.date }?
            .estimated1RM
    }

    /// §5 — reps "possible" at `percent` of a true 1RM, via the same Epley
    /// relationship the rest of the app already uses, inverted: the rep
    /// count whose Epley e1RM equals `percent` of the max.
    nonisolated static func repsPossible(atPercent percent: Double) -> Int {
        guard percent > 0, percent < 1 else {
            return 1
        }
        return max(1, Int((30 * (1 - percent) / percent).rounded()))
    }

    /// §5 — effort target (reps in reserve) for a trainer % with no reliable
    /// e1RM: reps possible at that % (Epley) minus the prescribed reps.
    nonisolated static func effortTargetRIR(percent: Double, targetReps: Int) -> Int {
        max(0, repsPossible(atPercent: percent) - targetReps)
    }

    /// §4 — human reason today's trainer-day weight differs from the
    /// trainer's own number. nil when Tempo didn't change it (nothing to
    /// explain, nothing to show/override on Today).
    nonisolated static func loadAdjustmentNote(
        trainerTargetKg: Double,
        appliedWorkingWeightKg: Double?,
        recoveryAdjustment: Double,
        isConservativeNote: Bool
    ) -> String? {
        guard let applied = appliedWorkingWeightKg, applied < trainerTargetKg - 0.05 else {
            return nil
        }
        var reasons: [String] = []
        if recoveryAdjustment < 1.0 {
            let cutPercent = Int(((1 - recoveryAdjustment) * 100).rounded())
            reasons.append("Recovery yellow −\(cutPercent)%")
        }
        if isConservativeNote {
            reasons.append("Pain note — capped at last session")
        }
        guard !reasons.isEmpty else {
            return "Adjusted from your trainer's target"
        }
        return reasons.joined(separator: " · ")
    }

    nonisolated static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
