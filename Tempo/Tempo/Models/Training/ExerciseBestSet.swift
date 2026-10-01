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

    /// True when (weight, reps) `a` ranks below `b`.
    static func ranksBelow(_ a: (weight: Double, reps: Int), _ b: (weight: Double, reps: Int)) -> Bool {
        a.weight != b.weight ? a.weight < b.weight : a.reps < b.reps
    }

    /// The best of each session's recorded top set.
    static func pick(from history: [ExerciseHistory]) -> ExerciseBestSet? {
        let pairs = history.compactMap { row -> (weight: Double, reps: Int)? in
            guard let reps = row.bestSetReps, reps > 0 else {
                return nil
            }
            return (row.bestSetWeight ?? 0, reps)
        }
        return pairs.max(by: ranksBelow).map { ExerciseBestSet(weightKg: $0.weight, reps: $0.reps) }
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
