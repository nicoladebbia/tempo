//
// ArenaCalendar.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation

// MARK: - ArenaCalendar

// One way to cut time for everything in the Arena: days are "YYYY-MM-DD" in the
// user's own time zone, weeks run Monday to Sunday (ISO 8601), the same cut the
// server uses for the friends leaderboard. A week cut that starts on Sunday
// (the device locale in the US) would rank a different week than the server.

enum ArenaCalendar {
    /// ISO 8601 weeks (Monday first) in the user's current time zone.
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// "2026-11-24".
    static func dayKey(_ date: Date, calendar: Calendar = calendar()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// The start of the day a "YYYY-MM-DD" key names, or nil when it is not one.
    static func date(forKey key: String, calendar: Calendar = calendar()) -> Date? {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else {
            return nil
        }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }

    /// Midnight at the start of the Monday of the week holding `date`.
    static func weekStart(containing date: Date, calendar: Calendar = calendar()) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The Monday of the week before the one holding `date`.
    static func previousWeekStart(before date: Date, calendar: Calendar = calendar()) -> Date {
        let thisWeek = weekStart(containing: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
    }

    /// `days` days after (or before, when negative) a day.
    static func addingDays(_ days: Int, to date: Date, calendar: Calendar = calendar()) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}
