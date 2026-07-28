//
// MuscleHeatEngine.swift
// Tempo
//
// §11.5 — the math behind the interactive muscle heatmap. Pure value-level
// aggregation (no SwiftData types) so it unit-tests without a container:
// the view flattens ExerciseHistory rows into ContributionRow values and
// everything after that is deterministic.
//

import Foundation

enum MuscleHeatEngine {
    /// One history row flattened to what the heat math needs.
    struct ContributionRow: Equatable {
        let primary: MuscleGroup
        let secondaries: [MuscleGroup]
        let volume: Double
        let sets: Int
        let date: Date
    }

    /// Secondary movers earn half credit — a row's full volume heats its
    /// primary muscle; each listed secondary gets 0.5×.
    static let secondaryFactor = 0.5

    /// Muscles that render on the body figure. fullBody/cardio rows carry no
    /// location — they're excluded rather than smeared across everything.
    static let mappableMuscles: Set<MuscleGroup> = [
        .chest, .back, .shoulders, .biceps, .triceps, .forearms,
        .quads, .hamstrings, .glutes, .calves, .core,
    ]

    /// Weighted volume per muscle for rows inside [from, to).
    static func volumes(
        rows: [ContributionRow],
        from: Date,
        to: Date
    ) -> [MuscleGroup: Double] {
        var out: [MuscleGroup: Double] = [:]
        for row in rows where row.date >= from && row.date < to {
            if mappableMuscles.contains(row.primary) {
                out[row.primary, default: 0] += row.volume
            }
            for secondary in row.secondaries where mappableMuscles.contains(secondary) {
                out[secondary, default: 0] += row.volume * secondaryFactor
            }
        }
        return out
    }

    /// Set counts per muscle (primary only — a set "belongs" to one muscle)
    /// for the drill-down card.
    static func setCounts(
        rows: [ContributionRow],
        from: Date,
        to: Date
    ) -> [MuscleGroup: Int] {
        var out: [MuscleGroup: Int] = [:]
        for row in rows where row.date >= from && row.date < to {
            guard mappableMuscles.contains(row.primary) else {
                continue
            }
            out[row.primary, default: 0] += row.sets
        }
        return out
    }

    /// Normalize volumes to 0…1 heat by the hottest muscle. Empty → empty.
    static func heat(_ volumes: [MuscleGroup: Double]) -> [MuscleGroup: Double] {
        guard let peak = volumes.values.max(), peak > 0 else {
            return [:]
        }
        return volumes.mapValues { $0 / peak }
    }

    /// Signed fractional change current-vs-previous per muscle (0.25 = +25%).
    /// nil where the previous window had nothing to compare against.
    static func delta(
        current: [MuscleGroup: Double],
        previous: [MuscleGroup: Double]
    ) -> [MuscleGroup: Double?] {
        var out: [MuscleGroup: Double?] = [:]
        for (muscle, volume) in current {
            if let prior = previous[muscle], prior > 0 {
                out[muscle] = (volume - prior) / prior
            } else {
                // Subscript-assigning nil would REMOVE the key — updateValue
                // stores an explicit "no comparison available".
                out.updateValue(nil, forKey: muscle)
            }
        }
        return out
    }
}
