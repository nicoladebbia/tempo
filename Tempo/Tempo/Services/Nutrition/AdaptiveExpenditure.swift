//
// AdaptiveExpenditure.swift
// Tempo
//
// Energy balance from the user's own data: what they logged eating versus
// how their weight actually moved. Formulas (Mifflin/Katch × activity) can
// be 10–20% off for a given person; four weeks of intake + weigh-ins say
// what THIS body burns. TDEECalculator blends it in by `confidence`, so a
// thin log barely moves the formula and a solid month mostly replaces it.
//

import Foundation
import SwiftData

enum AdaptiveExpenditure {
    /// Observed maintenance calories and how far to trust them.
    struct Observation: Equatable {
        /// Mean logged intake minus the energy in the weight change, kcal/day.
        let kcal: Double
        /// 0 … `maxConfidence`. Grows with logged days and weigh-in span.
        let confidence: Double
        let loggedDays: Int
        let trendKgPerWeek: Double
    }

    struct WeighIn: Equatable {
        let date: Date
        let kg: Double
    }

    static let windowDays = 28
    static let minLoggedDays = 10
    static let minWeighIns = 4
    static let minSpanDays = 10
    /// A logged day below this is treated as a partial log, not a real day.
    static let minDayKcal = 1000
    static let maxConfidence = 0.8
    static let kcalPerKg = 7700.0

    /// Pure estimate. `intake` is per-day eaten totals (today excluded — it's
    /// still in progress); `weighIns` any order. nil when the data is too thin.
    static func observe(intake: [DailyEatenTotals], weighIns: [WeighIn]) -> Observation? {
        let logged = intake.filter { $0.hasData && $0.calories >= minDayKcal }
        guard logged.count >= minLoggedDays else {
            return nil
        }
        guard let trend = weightTrend(weighIns) else {
            return nil
        }
        let meanIntake = Double(logged.map(\.calories).reduce(0, +)) / Double(logged.count)
        let kcal = meanIntake - trend.kgPerDay * kcalPerKg
        guard kcal > 0 else {
            return nil
        }
        let logShare = min(1, Double(logged.count) / 21)
        let spanShare = min(1, trend.spanDays / 21)
        return Observation(
            kcal: kcal,
            confidence: maxConfidence * logShare * spanShare,
            loggedDays: logged.count,
            trendKgPerWeek: trend.kgPerDay * 7
        )
    }

    /// Least-squares slope through the weigh-ins (kg/day), ignoring readings
    /// more than 2.5 kg from the median (a mis-tap or someone else on the scale).
    static func weightTrend(_ weighIns: [WeighIn]) -> (kgPerDay: Double, spanDays: Double)? {
        let sorted = weighIns.map(\.kg).sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        let median = sorted[sorted.count / 2]
        let points = weighIns.filter { abs($0.kg - median) <= 2.5 }
        guard points.count >= minWeighIns,
              let first = points.map(\.date).min(),
              let last = points.map(\.date).max()
        else {
            return nil
        }
        let span = last.timeIntervalSince(first) / 86400
        guard span >= Double(minSpanDays) else {
            return nil
        }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86400 }
        let ys = points.map(\.kg)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var sxy = 0.0
        var sxx = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - meanX) * (y - meanY)
            sxx += (x - meanX) * (x - meanX)
        }
        guard sxx > 0 else {
            return nil
        }
        return (sxy / sxx, span)
    }

    /// The last `windowDays` full days of eaten meals and BodyComposition weigh-ins.
    @MainActor
    static func observe(in context: ModelContext, now: Date = Date()) -> Observation? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
              let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: yesterday)
        else {
            return nil
        }
        let intake = EatenNutritionHistory.dailyTotals(in: context, days: windowDays, endingOn: yesterday)
        let descriptor = FetchDescriptor<BodyComposition>(
            predicate: #Predicate<BodyComposition> { $0.date >= windowStart }
        )
        let weighIns = ((try? context.fetch(descriptor)) ?? []).compactMap { snapshot -> WeighIn? in
            guard let kg = snapshot.weightKg, kg > 0 else {
                return nil
            }
            // A day re-snapshotting an old reading isn't a new weigh-in.
            let measured = snapshot.measurementDate ?? snapshot.date
            guard measured >= windowStart else {
                return nil
            }
            return WeighIn(date: measured, kg: kg)
        }
        return observe(intake: intake, weighIns: dedupedByDay(weighIns, calendar: calendar))
    }

    /// One weigh-in per measurement day (BodyComposition snapshots the latest
    /// reading daily, so a skipped weigh-in repeats yesterday's value).
    static func dedupedByDay(_ weighIns: [WeighIn], calendar: Calendar = .current) -> [WeighIn] {
        var byDay: [Date: WeighIn] = [:]
        for weighIn in weighIns {
            byDay[calendar.startOfDay(for: weighIn.date)] = weighIn
        }
        return byDay.values.sorted { $0.date < $1.date }
    }
}
