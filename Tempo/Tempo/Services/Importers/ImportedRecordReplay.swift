//
// ImportedRecordReplay.swift
// Tempo
//
// Imported workout history should leave the app in the state it would be in
// had the athlete logged those sessions live: real records on the dates they
// were set, the first time a lift appears counted as its baseline (never a
// "PR"), and nothing celebrated twice. So CSV import replays each session in
// date order through the SAME rule live logging uses
// (`TrainingEngine.personalRecordKind`), against everything the athlete had
// BEFORE that date, then folds the session into the bar for the next one.
//
// One record per lift per session: the best e1RM PR, else the heaviest-weight
// PR (only when no e1RM PR), else — for pure bodyweight lifts — most reps.
// Bodyweight-loaded lifts (pull-ups, dips) never get an e1RM PR: heaviest
// ADDED load or most reps only, exactly as live logging.
//

import Foundation

struct ImportedRecordReplay {
    private struct Event {
        let date: Date
        let weightKg: Double
        let reps: Int
        let e1RM: Double?
    }

    /// What the athlete had on each lift before the import (by date).
    private var existing: [UUID: [Event]] = [:]
    /// What earlier imported sessions of that lift have already established.
    private var imported: [UUID: TrainingEngine.PersonalRecordBaseline] = [:]

    /// Snapshots the lift's existing history. Call before the import attaches
    /// any of its own sets to `exercise`; a second call is a no-op.
    mutating func prepare(_ exercise: Exercise) {
        guard existing[exercise.id] == nil else {
            return
        }
        let bodyweight = TrainingEngine.usesBodyweightPRRule(exercise.equipment)
        var events: [Event] = []
        for row in exercise.history ?? [] {
            events.append(Event(
                date: row.date,
                weightKg: max(0, (bodyweight ? row.bestSetAddedLoadKg : row.bestSetWeight) ?? 0),
                reps: row.bestSetReps ?? 0,
                e1RM: row.estimated1RM
            ))
        }
        for slot in exercise.plannedExercises ?? [] {
            guard let plan = slot.workoutPlan else {
                continue
            }
            let date = plan.startedAt ?? plan.date
            for set in slot.sets ?? [] where set.completed && !set.isWarmup {
                events.append(Event(
                    date: date,
                    weightKg: max(0, (bodyweight ? set.addedLoadKg : set.actualWeight) ?? 0),
                    reps: set.actualReps ?? 0,
                    e1RM: set.estimated1RM
                ))
            }
        }
        existing[exercise.id] = events
        imported[exercise.id] = TrainingEngine.PersonalRecordBaseline()
    }

    /// The record (if any) this imported session sets on `exercise`, then
    /// folds the session's sets into the lift's running bar. The returned row
    /// is NOT inserted — the caller does that.
    mutating func record(
        for exercise: Exercise,
        sets: [PlannedSet],
        on date: Date,
        planID: UUID
    ) -> PersonalRecord? {
        prepare(exercise)
        var bar = TrainingEngine.PersonalRecordBaseline()
        for event in existing[exercise.id] ?? [] where event.date < date {
            bar.absorb(weightKg: event.weightKg, reps: event.reps, e1RM: event.e1RM)
        }
        bar = bar.merged(with: imported[exercise.id] ?? TrainingEngine.PersonalRecordBaseline())

        // Same keying as live logging: bodyweight-loaded lifts by the added
        // load (no e1RM record), loaded lifts with a real weight; only
        // bodyweight-loaded and unclassified lifts may set "Most reps".
        let bodyweight = TrainingEngine.usesBodyweightPRRule(exercise.equipment)
        let zeroWeightAllowed = TrainingEngine.allowsZeroWeightRecord(exercise.equipment)
        let load: (PlannedSet) -> Double = { set in
            max(0, (bodyweight ? set.addedLoadKg : set.actualWeight) ?? 0)
        }
        let working = sets.filter { $0.completed && !$0.isWarmup && ($0.actualReps ?? 0) > 0 }
        var best: [PRType: (value: Double, set: PlannedSet)] = [:]
        for set in working {
            let reps = set.actualReps ?? 0
            let weight = load(set)
            guard weight > 0 || zeroWeightAllowed, let hit = TrainingEngine.personalRecordKind(
                baseline: bar, weight: weight, reps: reps, rir: set.effectiveRIR(reps: reps), allowsE1RM: !bodyweight
            ) else {
                continue
            }
            if hit.value > (best[hit.type]?.value ?? -1) {
                best[hit.type] = (hit.value, set)
            }
        }

        // The session raises the bar only after it has been judged — sets in
        // the same session never beat each other.
        var next = imported[exercise.id] ?? TrainingEngine.PersonalRecordBaseline()
        for set in working {
            let reps = set.actualReps ?? 0
            next.absorb(
                weightKg: load(set),
                reps: reps,
                e1RM: reps <= TrainingEngine.e1RMPersonalRecordRepCap ? set.estimated1RM : nil
            )
        }
        imported[exercise.id] = next

        guard let type = [PRType.oneRepMax, .repMax, .mostReps].first(where: { best[$0] != nil }),
              let hit = best[type]
        else {
            return nil
        }
        let weight = load(hit.set)
        let reps = hit.set.actualReps ?? 0
        return PersonalRecord(
            type: type,
            value: hit.value,
            date: date,
            workoutPlanID: planID,
            context: weight > 0 ? "\(Int(weight)) x \(reps) reps" : "BW x \(reps) reps",
            contextWeightKg: weight,
            contextReps: reps,
            exercise: exercise
        )
    }
}
