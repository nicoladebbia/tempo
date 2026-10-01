//
// UseItUpNotificationPlanner.swift
// Tempo
//
// Pure decision logic for the daily "Use it up" pantry notification: fires
// AT MOST once a day, ONLY when something expires within 2 days, as ONE
// summary notification (never one per item — that would blow the daily
// notification budget on a big pantry). Kept separate from
// `NotificationService` (which owns `UNUserNotificationCenter` I/O) so the
// decision is unit-testable without touching the notification center.
//

import Foundation

enum UseItUpNotificationPlanner {
    struct Decision: Equatable {
        let shouldFire: Bool
        let body: String
        let urgentCount: Int
    }

    /// `now` is injectable for deterministic tests.
    static func decide(items: [PantryItem], now: Date = Date()) -> Decision {
        let urgent = items
            .filter { !$0.isArchived && $0.isInStock }
            .compactMap { item -> (PantryItem, Int)? in
                guard let days = item.daysUntilUseBy, (0 ... 2).contains(days) else {
                    return nil
                }
                return (item, days)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        guard !urgent.isEmpty else {
            return Decision(shouldFire: false, body: "", urgentCount: 0)
        }

        let names = urgent.prefix(3).map(\.displayName)
        let namesJoined = names.joined(separator: ", ")
        let body = if urgent.count <= 3 {
            "\(namesJoined) — use it up or lose it. Check the pantry."
        } else {
            "\(namesJoined) and \(urgent.count - 3) more expire soon. Check the pantry before it's trash."
        }
        return Decision(shouldFire: true, body: body, urgentCount: urgent.count)
    }

    /// Next 8:00 AM strictly after `now` — the fire time for the morning
    /// summary. Today's 8am if it hasn't passed yet, otherwise tomorrow's.
    static func nextMorningFireDate(after now: Date = Date(), hour: Int = 8) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        components.second = 0
        let todayAtHour = calendar.date(from: components) ?? now
        if todayAtHour > now {
            return todayAtHour
        }
        return calendar.date(byAdding: .day, value: 1, to: todayAtHour) ?? todayAtHour
    }
}
