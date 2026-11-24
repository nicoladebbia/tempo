//
// BodyHistory.swift
// Tempo
//
// What the Body page compares today against: the average of the days before it,
// yesterday and the same day last week. Every number comes from a stored day of
// readings (Whoop or Health); a comparison without two real days behind it is
// not shown. Plain values only, so each rule has a test.
//

import Foundation

// MARK: - BodyHistory

enum BodyHistory {
    /// The days before today that make the baseline.
    static let baselineDays = 7
    /// A baseline built from fewer days than this is a guess, so there is none.
    static let minimumBaselineDays = 3

    // MARK: Baseline

    /// The average of each reading over the `baselineDays` days before today.
    struct Baseline: Equatable {
        let dayCount: Int
        let recovery: Double?
        let hrv: Double?
        let rhr: Double?
        let sleepHours: Double?
    }

    /// Days with readings in the `baselineDays` calendar days ending yesterday.
    /// Each reading is averaged over the days that have it, and only when at
    /// least `minimumBaselineDays` days do.
    static func baseline(
        _ readings: [RecoveryDayReading], today: Date, calendar: Calendar = .current
    ) -> Baseline {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)) else {
            return Baseline(dayCount: 0, recovery: nil, hrv: nil, rhr: nil, sleepHours: nil)
        }
        let window = RecoveryWindow.select(readings, days: baselineDays, endingOn: yesterday, calendar: calendar)
        return Baseline(
            dayCount: window.count,
            recovery: average(window.map(\.recovery)),
            hrv: average(window.compactMap(\.hrv)),
            rhr: average(window.compactMap(\.rhr)),
            sleepHours: average(window.compactMap(\.sleepHours))
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        values.count >= minimumBaselineDays ? values.reduce(0, +) / Double(values.count) : nil
    }

    // MARK: Against the baseline

    enum Verdict: Equatable {
        case better
        case worse
        case same
    }

    /// How a reading sits against its average. Within 5% either way is "same".
    static func verdict(current: Double, baseline: Double, higherIsBetter: Bool) -> Verdict {
        guard baseline > 0 else {
            return .same
        }
        let ratio = current / baseline
        if ratio > 1.05 {
            return higherIsBetter ? .better : .worse
        }
        if ratio < 0.95 {
            return higherIsBetter ? .worse : .better
        }
        return .same
    }

    // MARK: Against another day

    struct Change: Equatable {
        enum Kind: Equatable {
            case recovery
            case hrv
            case sleep
        }

        let kind: Kind
        /// Today minus the other day, rounded the way it is shown.
        let delta: Double
        let verdict: Verdict

        /// "+5%", "-2 ms", "+0.5 h", "0%". A zero change has no sign.
        var text: String {
            switch kind {
            case .recovery: BodyHistory.signed(delta, decimals: 0, unit: "%")
            case .hrv: BodyHistory.signed(delta, decimals: 0, unit: " ms")
            case .sleep: BodyHistory.signed(delta, decimals: 1, unit: " h")
            }
        }
    }

    /// Today against one other day, for the readings both days have. Recovery
    /// is always there; HRV and sleep only when both days measured them.
    /// Nil when either day has no readings at all.
    static func changes(
        today: RecoveryDayReading?, other: RecoveryDayReading?, kinds: [Change.Kind]
    ) -> [Change] {
        guard let today, let other, today.hasReadings, other.hasReadings else {
            return []
        }
        return kinds.compactMap { kind in
            switch kind {
            case .recovery:
                return change(kind, today.recovery, other.recovery, decimals: 0)
            case .hrv:
                guard let now = today.hrv, let then = other.hrv else {
                    return nil
                }
                return change(kind, now, then, decimals: 0)
            case .sleep:
                guard let now = today.sleepHours, let then = other.sleepHours else {
                    return nil
                }
                return change(kind, now, then, decimals: 1)
            }
        }
    }

    private static func change(_ kind: Change.Kind, _ now: Double, _ then: Double, decimals: Int) -> Change {
        let scale = pow(10, Double(decimals))
        let delta = ((now - then) * scale).rounded() / scale
        let verdict: Verdict = delta > 0 ? .better : delta < 0 ? .worse : .same
        return Change(kind: kind, delta: delta, verdict: verdict)
    }

    /// The reading for one calendar day, if that day has readings.
    static func reading(
        on day: Date, in readings: [RecoveryDayReading], calendar: Calendar = .current
    ) -> RecoveryDayReading? {
        readings.first { $0.hasReadings && calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The day `days` calendar days before `day`.
    static func day(_ days: Int, before day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: day))
    }

    // MARK: Text

    /// "+5%", "-2 ms", "0%". A change that rounds to zero carries no sign.
    static func signed(_ value: Double, decimals: Int, unit: String) -> String {
        let scale = pow(10, Double(decimals))
        let rounded = (value * scale).rounded() / scale
        if rounded == 0 {
            return "0\(unit)"
        }
        return String(format: "%+.\(decimals)f", rounded) + unit
    }
}

// MARK: - SleepStageMinutes

/// Last night's minutes in each stage, from the stored day.
struct SleepStageMinutes: Equatable {
    let deep: Int
    let rem: Int
    let light: Int
    let awake: Int

    var total: Int {
        deep + rem + light + awake
    }

    /// Nil unless at least one stage has minutes: a night with no stage data
    /// is "no data", never four zero-width bars.
    init?(deep: Int?, rem: Int?, light: Int?, awake: Int?) {
        let minutes = (deep ?? 0, rem ?? 0, light ?? 0, awake ?? 0)
        guard minutes.0 + minutes.1 + minutes.2 + minutes.3 > 0 else {
            return nil
        }
        self.deep = max(minutes.0, 0)
        self.rem = max(minutes.1, 0)
        self.light = max(minutes.2, 0)
        self.awake = max(minutes.3, 0)
    }

    /// "7h 5m", "45m", "2h".
    static func formatted(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0, rest > 0 {
            return "\(hours)h \(rest)m"
        }
        return hours > 0 ? "\(hours)h" : "\(rest)m"
    }
}
