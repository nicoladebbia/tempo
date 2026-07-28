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

    /// Ascending series with running-max e1RM sessions flagged as PRs — the
    /// star markers on the chart. A session with no e1RM can't be a PR.
    static func series(from raw: [SessionPoint]) -> [SessionPoint] {
        var best = 0.0
        return raw.sorted { $0.date < $1.date }.map { point in
            var out = point
            if let e1RM = point.e1RM, e1RM > best {
                best = e1RM
                out.isPR = true
            }
            return out
        }
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
