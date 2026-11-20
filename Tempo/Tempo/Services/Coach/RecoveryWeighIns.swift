//
// RecoveryWeighIns.swift
// Tempo
//
// Recovery Coach: turns Apple Health body-mass readings and manual entries
// into the weigh-ins the server wants for one session. Pure, no HealthKit.
//
// Windows the server uses: pre = 3 h before start to 10 min after;
// post = 10 min before end to 2 h after. The app sends everything in
// [start - 3 h, end + 2.5 h] and lets the server pick.
//

import Foundation

/// One body-mass reading from Apple Health.
struct HealthWeightSample: Equatable, Sendable {
    let time: Date
    let kg: Double
    /// Name of the app/device that wrote it ("Withings", "Health", ...).
    let sourceName: String
}

enum RecoveryWeighIns {
    static let before: TimeInterval = 3 * 3600
    static let after: TimeInterval = 2.5 * 3600
    /// Same range the server accepts.
    static let plausibleKg: ClosedRange<Double> = 20 ... 400
    /// The server rejects very long lists.
    static let maxCount = 12

    /// Range of Health readings worth reading for a session.
    static func window(start: Date, end: Date) -> (from: Date, to: Date) {
        (start.addingTimeInterval(-before), end.addingTimeInterval(after))
    }

    /// Fluids count from the weigh-in the server uses as "before" to the one it uses as "after".
    /// Server rule (SweatBalance.pair): before = LATEST weight in [start - 3 h, start + 10 min],
    /// after = EARLIEST weight in [end - 10 min, end + 2 h]. Without one, fall back to
    /// start - 15 min and `now`. Only copies which weights the server picks; no sweat math.
    static func waterWindow(
        weighIns: [CoachWeighIn], start: Date, end: Date, now: Date
    ) -> (from: Date, to: Date) {
        let before = weighIns
            .filter { $0.time >= start.addingTimeInterval(-3 * 3600) && $0.time <= start.addingTimeInterval(10 * 60) }
            .map(\.time).max()
        let after = weighIns
            .filter { $0.time >= end.addingTimeInterval(-10 * 60) && $0.time <= end.addingTimeInterval(2 * 3600) }
            .map(\.time).min()
        return (before ?? start.addingTimeInterval(-15 * 60), after ?? now)
    }

    /// Any source containing "Withings" is `withings`; everything else is `manual`.
    static func source(forHealthSourceName name: String) -> String {
        name.localizedCaseInsensitiveContains("withings") ? CoachWeighIn.sourceWithings : CoachWeighIn.sourceManual
    }

    /// Health readings and manual entries inside the window, oldest first,
    /// out-of-range weights dropped, same-instant duplicates collapsed
    /// (a manual entry wins over a Health reading at the same second).
    static func select(
        health: [HealthWeightSample], manual: [CoachWeighIn], start: Date, end: Date
    ) -> [CoachWeighIn] {
        let range = window(start: start, end: end)
        let fromHealth = health.map {
            CoachWeighIn(time: $0.time, kg: $0.kg, source: source(forHealthSourceName: $0.sourceName))
        }
        var byInstant: [Int: CoachWeighIn] = [:]
        for entry in fromHealth + manual
            where plausibleKg.contains(entry.kg) && entry.time >= range.from && entry.time <= range.to {
            byInstant[Int(entry.time.timeIntervalSince1970)] = entry
        }
        let sorted = byInstant.values.sorted { $0.time < $1.time }
        return Array(sorted.suffix(maxCount))
    }
}
