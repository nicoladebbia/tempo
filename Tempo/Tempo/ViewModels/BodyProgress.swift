//
// BodyProgress.swift
// Tempo
//
// The maths behind the Body progress page: which daily snapshots are real
// measurements, the series for weight, body fat and lean mass, and the trend of
// a series. On plain values, so each rule has a test. No SwiftData, no Health.
//

import Foundation

// MARK: - BodyMetric

enum BodyMetric: String, CaseIterable {
    case weight = "Weight"
    case bodyFat = "Body fat"
    case leanMass = "Lean mass"
}

// MARK: - BodySnapshot

/// One daily row of body composition, as plain values. Health's newest reading
/// is copied into a row every day, so a row says when it was *measured* too.
struct BodySnapshot: Equatable {
    var date: Date
    var measurementDate: Date?
    var weightKg: Double?
    var bodyFatPercent: Double?
    var leanMassKg: Double?
}

// MARK: - BodyMeasurement

/// A real measurement: one per day it was taken.
struct BodyMeasurement: Equatable {
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var leanMassKg: Double?

    func value(for metric: BodyMetric) -> Double? {
        switch metric {
        case .weight: weightKg
        case .bodyFat: bodyFatPercent
        case .leanMass: leanMassKg
        }
    }
}

// MARK: - BodyProgress

enum BodyProgress {
    struct Point: Equatable {
        let date: Date
        let value: Double
    }

    struct Trend: Equatable {
        let latest: Point
        let first: Point
        let pointCount: Int
        /// The change along the fitted line, first to last day. Single readings
        /// swing with hydration, so this is not "last minus first". Nil with
        /// fewer than three readings or less than a week between them.
        let fittedChange: Double?
        /// The slope of that line, per week.
        let weeklyRate: Double?
    }

    /// Values outside these ranges are a scale or sync glitch, not a body.
    static func plausible(_ value: Double, for metric: BodyMetric) -> Bool {
        switch metric {
        case .weight: (20.0 ... 400.0).contains(value)
        case .bodyFat: (2.0 ... 70.0).contains(value)
        case .leanMass: (10.0 ... 300.0).contains(value)
        }
    }

    /// Fewer readings than this is not a trend.
    static let minimumPoints = 3
    /// Nor is a span shorter than this many days.
    static let minimumSpanDays = 7.0

    /// The real measurements behind the daily snapshots. A day that only copied
    /// an old reading forward is not a new measurement, so snapshots group by the
    /// day they were measured and the newest copy of each wins. Readings that are
    /// not plausible are dropped, and a day left with nothing is dropped.
    static func measurements(from snapshots: [BodySnapshot], calendar: Calendar = .current) -> [BodyMeasurement] {
        var byDay = [Date: BodySnapshot]()
        for snapshot in snapshots {
            let day = calendar.startOfDay(for: snapshot.measurementDate ?? snapshot.date)
            if let existing = byDay[day], existing.date >= snapshot.date {
                continue
            }
            byDay[day] = snapshot
        }
        return byDay
            .map { day, snapshot in
                BodyMeasurement(
                    date: day,
                    weightKg: snapshot.weightKg.flatMap { plausible($0, for: .weight) ? $0 : nil },
                    bodyFatPercent: snapshot.bodyFatPercent.flatMap { plausible($0, for: .bodyFat) ? $0 : nil },
                    leanMassKg: snapshot.leanMassKg.flatMap { plausible($0, for: .leanMass) ? $0 : nil }
                )
            }
            .filter { $0.weightKg != nil || $0.bodyFatPercent != nil || $0.leanMassKg != nil }
            .sorted { $0.date < $1.date }
    }

    /// One metric over the last `days` days (all of it for nil), oldest first.
    static func series(
        _ metric: BodyMetric, from measurements: [BodyMeasurement], days: Int?, now: Date,
        calendar: Calendar = .current
    ) -> [Point] {
        var start = Date.distantPast
        if let days, let from = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) {
            start = from
        }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return measurements
            .filter { $0.date >= start && $0.date < end }
            .compactMap { measurement in
                measurement.value(for: metric).map { Point(date: measurement.date, value: $0) }
            }
    }

    /// The latest reading, and where the series has been going. Nil with no points.
    static func trend(of points: [Point]) -> Trend? {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first, let latest = sorted.last else {
            return nil
        }
        let spanDays = latest.date.timeIntervalSince(first.date) / 86400
        guard sorted.count >= minimumPoints, spanDays >= minimumSpanDays,
              let slopePerDay = leastSquaresSlope(sorted)
        else {
            return Trend(latest: latest, first: first, pointCount: sorted.count, fittedChange: nil, weeklyRate: nil)
        }
        return Trend(
            latest: latest, first: first, pointCount: sorted.count,
            fittedChange: slopePerDay * spanDays, weeklyRate: slopePerDay * 7
        )
    }

    enum Direction: Equatable {
        case up
        case down
        case steady
    }

    /// Where a trend is heading. A weekly rate that would show as 0.0 is steady.
    /// Nil when the trend has no rate yet.
    static func direction(of trend: Trend) -> Direction? {
        guard let rate = trend.weeklyRate else {
            return nil
        }
        if abs(rate) < steadyBelowPerWeek {
            return .steady
        }
        return rate > 0 ? .up : .down
    }

    /// A change smaller than this per week (kg, or points of body fat) reads as 0.0.
    static let steadyBelowPerWeek = 0.05

    /// The number for a stored value in the display unit: kg or lbs for weight and
    /// lean mass, percent for body fat. "80", "80.2", "18.1".
    static func displayNumber(_ storedValue: Double, metric: BodyMetric, unit: WeightUnit) -> String {
        WeightFormat.number(displayValue(storedValue, metric: metric, unit: unit))
    }

    /// A stored value in the display unit.
    static func displayValue(_ storedValue: Double, metric: BodyMetric, unit: WeightUnit) -> Double {
        metric == .bodyFat ? storedValue : WeightUnit.kg.convert(storedValue, to: unit)
    }

    /// "kg", "lbs" or "%".
    static func unitLabel(metric: BodyMetric, unit: WeightUnit) -> String {
        metric == .bodyFat ? "%" : unit.abbreviation
    }

    /// Value per day of the straight line that best fits the points.
    static func leastSquaresSlope(_ points: [Point]) -> Double? {
        guard let origin = points.first?.date, points.count >= 2 else {
            return nil
        }
        let xs = points.map { $0.date.timeIntervalSince(origin) / 86400 }
        let ys = points.map(\.value)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var covariance = 0.0
        var variance = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            variance += (x - meanX) * (x - meanX)
        }
        return variance > 0 ? covariance / variance : nil
    }
}
