//
// TodayClock.swift
// Tempo
//
// The time Today's evening and week-in-review rules read.
//

import Foundation

enum TodayClock {
    static var now: Date {
        #if DEBUG
            // Screenshots only: -todayNowOverride 2026-11-22T20:30:00+01:00
            if let raw = UserDefaults.standard.string(forKey: "todayNowOverride"),
               let date = ISO8601DateFormatter().date(from: raw)
            {
                return date
            }
        #endif
        return Date()
    }
}
