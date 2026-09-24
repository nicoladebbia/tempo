//
// ConditioningTargetEvaluator.swift
// Tempo
//
// Given a parsed `ConditioningTarget` (ConditioningTargetParser) and what the
// athlete actually logged, decide whether the trainer's target was hit. Pure
// and unit-tested (ConditioningTargetEvaluatorTests) — the log sheet and the
// history view both call this instead of duplicating the rule.
//

import Foundation

enum ConditioningTargetEvaluator {
    /// nil when there isn't enough information to judge (no cap on a
    /// repsDistance target, no logged data at all, or a freeform target).
    static func targetMet(
        target: ConditioningTarget,
        repTimesSeconds: [Double]?,
        durationSeconds: Double?,
        distanceMeters: Double?,
        roundsCompleted: Int?
    ) -> Bool? {
        switch target.kind {
        case let .repsDistance(_, _, _, capSeconds):
            guard let capSeconds, let times = repTimesSeconds, !times.isEmpty else {
                return nil
            }
            return times.allSatisfy { $0 <= capSeconds }

        case let .duration(minutes):
            guard let durationSeconds else {
                return nil
            }
            // Tolerant lower bound only — going long is never a miss, cutting
            // it short by more than 10% is. Matches the drill-sergeant rule:
            // did you put in at least what was asked.
            let targetSeconds = minutes * 60
            return durationSeconds >= targetSeconds * 0.9

        case let .intervalSets(sets, reps):
            guard let roundsCompleted else {
                return nil
            }
            return roundsCompleted >= sets * reps

        case let .distance(value, unit):
            guard let distanceMeters else {
                return nil
            }
            // 3% tolerance for GPS/track-measurement noise.
            return distanceMeters >= unit.meters(value) * 0.97

        case .freeform:
            return nil
        }
    }

    /// Best time in a set of logged rep times, for the compact card summary.
    static func bestTime(_ times: [Double]?) -> Double? {
        times?.min()
    }
}
