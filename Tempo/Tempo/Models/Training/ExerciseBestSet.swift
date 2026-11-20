//
// ExerciseBestSet.swift
// Tempo
//
// One rule for "best set": the heaviest set, ties broken by more reps — and
// always ONE set that actually happened. Exercise detail used to glue the
// heaviest weight from one session to the most reps from another ("100 kg ×
// 12" that was never lifted), and per-session bests ignored reps on a tie.
//

import Foundation

struct ExerciseBestSet: Equatable {
    let weightKg: Double
    let reps: Int
    /// Bodyweight-style lifts only: the best set's added load (nil = plain BW).
    var addedLoadKg: Double?
    var isBodyweight = false

    /// True when (weight, reps) `a` ranks below `b`.
    static func ranksBelow(_ a: (weight: Double, reps: Int), _ b: (weight: Double, reps: Int)) -> Bool {
        a.weight != b.weight ? a.weight < b.weight : a.reps < b.reps
    }

    /// The best of each session's recorded top set.
    /// `bodyweight`: rank by ADDED load then reps (the stored effective load
    /// drifts with the lifter's bodyweight) and carry the added load for display.
    static func pick(from history: [ExerciseHistory], bodyweight: Bool = false) -> ExerciseBestSet? {
        let pairs = history.compactMap { row -> (weight: Double, reps: Int)? in
            guard let reps = row.bestSetReps, reps > 0 else {
                return nil
            }
            let weight = bodyweight ? max(0, row.bestSetAddedLoadKg ?? 0) : (row.bestSetWeight ?? 0)
            return (weight, reps)
        }
        return pairs.max(by: ranksBelow).map {
            ExerciseBestSet(
                weightKg: $0.weight,
                reps: $0.reps,
                addedLoadKg: bodyweight && $0.weight > 0 ? $0.weight : nil,
                isBodyweight: bodyweight
            )
        }
    }
}

extension Exercise {
    /// "Current" 1RM: the strongest estimate from the last 6 weeks, so one
    /// light or deload day doesn't read as "you got weaker" and a session
    /// without an estimate (bodyweight) doesn't blank or zero it. With nothing
    /// that recent, the latest estimate on record.
    static func currentEstimated1RM(from rows: [ExerciseHistory], asOf date: Date = Date()) -> Double? {
        let positive = rows.filter { ($0.estimated1RM ?? 0) > 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -42, to: date) ?? .distantPast
        if let recent = positive.filter({ $0.date >= cutoff }).compactMap(\.estimated1RM).max() {
            return recent
        }
        return positive.max { $0.date < $1.date }?.estimated1RM
    }
}
