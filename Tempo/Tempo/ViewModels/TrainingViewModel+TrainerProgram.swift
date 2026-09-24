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
                case .football, .mobility, .rest:
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
            slot.programNote = [item.perSide == true ? "\(item.targetReps) per side" : nil, item.notes]
                .compactMap(\.self).joined(separator: " · ").nilIfEmpty
            slot.sets = prescribedSets(
                for: exercise,
                workingSets: max(1, item.sets),
                plan: plan,
                plannedExercise: slot,
                modelContext: modelContext,
                targetReps: item.targetReps,
                fixedWeightKg: Self.programWeightKg(item, exercise: exercise),
                targetRIR: item.rpe.map { max(0, Int((10 - $0).rounded())) },
                applyDeload: false
            )
        }
        return true
    }

    /// The trainer's load in kg: explicit weight, else % of the lifter's
    /// estimated 1RM, else nil (Tempo prescribes from history at the
    /// trainer's reps).
    nonisolated static func programWeightKg(_ item: ProgramExercise, exercise: Exercise) -> Double? {
        if let weight = item.weightKg, weight > 0 {
            return weight
        }
        if let pct = item.percentOf1RM, pct > 0, let e1RM = exercise.currentEstimated1RM, e1RM > 0 {
            return e1RM * min(pct, 1.1)
        }
        return nil
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
