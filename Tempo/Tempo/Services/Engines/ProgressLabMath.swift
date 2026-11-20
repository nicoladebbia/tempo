//
// ProgressLabMath.swift
// Tempo
//
// §11.2 — the math behind the interactive Strength Lab chart. Pure value
// types (no SwiftData) so PR detection and range filtering unit-test
// without a container; the view flattens ExerciseHistory into SessionPoint.
//

import Foundation

enum ProgressLabMath {
    /// One training day of one lift, chart-ready.
    struct SessionPoint: Equatable, Identifiable {
        var id: Date { date }
        let date: Date
        let e1RM: Double?
        let volume: Double
        let bestWeight: Double?
        let bestReps: Int?
        var isPR = false
    }

    enum Span: String, CaseIterable {
        case month = "1M"
        case quarter = "3M"
        case half = "6M"
        case all = "All"

        var days: Int? {
            switch self {
            case .month: 30
            case .quarter: 90
            case .half: 180
            case .all: nil
            }
        }
    }

    /// Ascending series, one point per calendar day (two sessions of the
    /// same lift on one day merge: best e1RM, summed volume, heavier best
    /// set), with running-max e1RM days flagged as PRs — the star markers on
    /// the chart. The first e1RM is the baseline, not a PR, and a day with no
    /// e1RM can't be one.
    static func series(from raw: [SessionPoint], calendar: Calendar = .current) -> [SessionPoint] {
        var best: Double?
        return mergedByDay(raw, calendar: calendar).map { point in
            var out = point
            if let e1RM = point.e1RM, e1RM > 0 {
                if let prior = best, e1RM > prior {
                    out.isPR = true
                }
                best = max(best ?? 0, e1RM)
            }
            return out
        }
    }

    private static func mergedByDay(_ raw: [SessionPoint], calendar: Calendar) -> [SessionPoint] {
        var merged: [SessionPoint] = []
        for point in raw.sorted(by: { $0.date < $1.date }) {
            guard let last = merged.last, calendar.isDate(last.date, inSameDayAs: point.date) else {
                merged.append(point)
                continue
            }
            let e1RMs = [last.e1RM, point.e1RM].compactMap(\.self)
            let keepLastSet = ExerciseBestSet.ranksBelow(
                (point.bestWeight ?? 0, point.bestReps ?? 0),
                (last.bestWeight ?? 0, last.bestReps ?? 0)
            )
            merged[merged.count - 1] = SessionPoint(
                date: last.date,
                e1RM: e1RMs.max(),
                volume: last.volume + point.volume,
                bestWeight: keepLastSet ? last.bestWeight : point.bestWeight,
                bestReps: keepLastSet ? last.bestReps : point.bestReps
            )
        }
        return merged
    }

    /// One (day, best e1RM) per calendar day, ascending, positive e1RMs only —
    /// a chart keyed by date must never see two points for one day.
    static func dailyBestE1RM(
        _ rows: [(date: Date, e1RM: Double?)], calendar: Calendar = .current
    ) -> [(date: Date, e1RM: Double)] {
        var out: [(date: Date, e1RM: Double)] = []
        for row in rows.sorted(by: { $0.date < $1.date }) {
            guard let e1RM = row.e1RM, e1RM > 0 else {
                continue
            }
            if let last = out.last, calendar.isDate(last.date, inSameDayAs: row.date) {
                out[out.count - 1].e1RM = max(last.e1RM, e1RM)
            } else {
                out.append((row.date, e1RM))
            }
        }
        return out
    }

    /// Points inside the span, measured back from `now`.
    static func filter(_ points: [SessionPoint], span: Span, now: Date) -> [SessionPoint] {
        guard let days = span.days else {
            return points
        }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return points.filter { $0.date >= cutoff }
    }

    /// The point nearest to a scrubbed date — the callout's data source.
    static func nearest(to date: Date, in points: [SessionPoint]) -> SessionPoint? {
        points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}
