//
// RecoveryPeriod.swift
// Tempo
//
// The maths behind the Recovery page's Week and Month views, on plain values:
// which days belong to a period, what a period averages, and what the load
// state is after a refresh. No SwiftData and no Whoop, so each rule is tested
// on its own.
//

import Foundation

// MARK: - RecoveryRange

/// The one switch at the top of the Recovery page.
enum RecoveryRange: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
}

// MARK: - RecoveryDayReading

/// One day of readings, as plain values.
struct RecoveryDayReading: Equatable {
    var date: Date
    var recovery: Double
    var hrv: Double?
    var rhr: Double?
    var sleepHours: Double?
    var strain: Double?

    /// True once a night of readings is in. A day that holds a score of 0 and
    /// nothing else is a day without data, not a red day, and must not pull an
    /// average down or draw a dip to zero on a chart.
    var hasReadings: Bool {
        hrv != nil || rhr != nil || sleepHours != nil || strain != nil || recovery > 0
    }
}

// MARK: - RecoveryWindow

enum RecoveryWindow {
    /// The readings that fall in the `days` calendar days ending on `today`,
    /// oldest first. The count is days on the calendar, never rows: a week with
    /// three recorded days holds three readings, not the last seven rows.
    static func select(
        _ readings: [RecoveryDayReading],
        days: Int,
        endingOn today: Date,
        calendar: Calendar = .current
    ) -> [RecoveryDayReading] {
        guard let range = bounds(days: days, endingOn: today, calendar: calendar) else {
            return []
        }
        return readings
            .filter { $0.hasReadings && $0.date >= range.start && $0.date < range.end }
            .sorted { $0.date < $1.date }
    }

    /// The `days` calendar days just before the window `select` returns.
    static func previous(
        _ readings: [RecoveryDayReading],
        days: Int,
        endingOn today: Date,
        calendar: Calendar = .current
    ) -> [RecoveryDayReading] {
        guard let range = bounds(days: days, endingOn: today, calendar: calendar),
              let earlierEnd = calendar.date(byAdding: .day, value: -1, to: range.start)
        else {
            return []
        }
        return select(readings, days: days, endingOn: earlierEnd, calendar: calendar)
    }

    private static func bounds(
        days: Int, endingOn today: Date, calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let dayStart = calendar.startOfDay(for: today)
        guard days > 0,
              let start = calendar.date(byAdding: .day, value: -(days - 1), to: dayStart),
              let end = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else {
            return nil
        }
        return (start, end)
    }
}

// MARK: - RecoveryPeriodStats

/// What a week or a month of recovery adds up to.
struct RecoveryPeriodStats: Equatable {
    struct DayScore: Equatable {
        let date: Date
        let score: Double
    }

    /// The averages of the period before, for "vs last week".
    struct Averages: Equatable {
        let recovery: Double
        let hrv: Double?
        let rhr: Double?
        let sleep: Double?
    }

    /// Fewer days than this say nothing about a pattern.
    static let minimumDays = 3

    let dayCount: Int
    let avgRecovery: Double
    let avgHRV: Double?
    let avgRHR: Double?
    let avgSleep: Double?
    let totalStrain: Double
    let avgStrain: Double?
    let best: DayScore?
    let worst: DayScore?
    let greenDays: Int
    let yellowDays: Int
    let redDays: Int
    let previous: Averages?

    /// Nil until the period holds `minimumDays` days with readings.
    static func make(
        window: [RecoveryDayReading],
        previous: [RecoveryDayReading] = []
    ) -> RecoveryPeriodStats? {
        guard window.count >= minimumDays else {
            return nil
        }
        let scores = window.map(\.recovery)
        let strains = window.compactMap(\.strain)
        let zones = window.map { RecoveryZone(score: $0.recovery) }

        return RecoveryPeriodStats(
            dayCount: window.count,
            avgRecovery: average(scores) ?? 0,
            avgHRV: average(window.compactMap(\.hrv)),
            avgRHR: average(window.compactMap(\.rhr)),
            avgSleep: average(window.compactMap(\.sleepHours)),
            totalStrain: strains.reduce(0, +),
            avgStrain: average(strains),
            best: window.max { $0.recovery < $1.recovery }.map { DayScore(date: $0.date, score: $0.recovery) },
            worst: window.min { $0.recovery < $1.recovery }.map { DayScore(date: $0.date, score: $0.recovery) },
            greenDays: zones.count(where: { $0 == .green }),
            yellowDays: zones.count(where: { $0 == .yellow }),
            redDays: zones.count(where: { $0 == .red }),
            previous: previousAverages(previous)
        )
    }

    private static func previousAverages(_ readings: [RecoveryDayReading]) -> Averages? {
        guard readings.count >= minimumDays else {
            return nil
        }
        let hrv = readings.compactMap(\.hrv)
        let rhr = readings.compactMap(\.rhr)
        let sleep = readings.compactMap(\.sleepHours)
        return Averages(
            recovery: average(readings.map(\.recovery)) ?? 0,
            hrv: hrv.count >= minimumDays ? average(hrv) : nil,
            rhr: rhr.count >= minimumDays ? average(rhr) : nil,
            sleep: sleep.count >= minimumDays ? average(sleep) : nil
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - RecoveryLoadResolver

/// What the page shows after a refresh. A failure is only an error when it
/// leaves the page with nothing to show: stale numbers beat a blank screen.
enum RecoveryLoadResolver {
    static func resolve(
        isConnectedToRealData: Bool,
        fetchedAnything: Bool,
        todayHasReadings: Bool,
        saveFailed: Bool
    ) -> RecoveryLoadState {
        if saveFailed {
            return .error("Couldn't save today's recovery. Pull down to try again.")
        }
        if isConnectedToRealData, !fetchedAnything, !todayHasReadings {
            return .error("Couldn't reach WHOOP. Check your connection and try again.")
        }
        return .loaded
    }
}

// MARK: - RecoveryBalance

/// The one-line read on strain against recovery.
enum RecoveryBalance {
    static func assessment(avgRecovery: Double, avgStrain: Double) -> String {
        if avgRecovery >= 67, avgStrain >= 12 {
            return "Great balance. You're training hard and recovering well. Keep this rhythm."
        } else if avgRecovery < 50, avgStrain >= 14 {
            return "Your strain is outpacing your recovery. Consider reducing training volume or adding an extra rest day."
        } else if avgRecovery >= 67, avgStrain < 10 {
            return "You have room to push harder. Your recovery supports more training stimulus."
        } else if avgRecovery < 50, avgStrain < 10 {
            return "Both strain and recovery are low. Focus on sleep quality and nutrition to build your recovery back up."
        }
        return "Moderate balance. Monitor how you feel and adjust training intensity day-by-day."
    }
}
