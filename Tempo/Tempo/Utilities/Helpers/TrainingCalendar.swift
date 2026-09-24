//
// TrainingCalendar.swift
// Tempo
//
// Locale-independent Monday-first week math for Training. `Calendar.current`
// ties "first weekday" to the device's region (en_US = Sunday), which made
// every `dateComponents([.yearForWeekOfYear, .weekOfYear], from:)` +
// `weekday = 2` computation across Training compute TOMORROW as "this
// Monday" on an en_US Sunday: the region's calendar identifies that Sunday as
// the FIRST day of its own week, so weekday=2 (Monday) resolves to the day
// AFTER it. ISO 8601 defines Monday as day 1 of the week by definition, so
// anchoring on the ISO 8601 calendar identifier keeps this correct on every
// device locale and on every day of the week, Sunday included.
//

import Foundation

enum TrainingCalendar {
    /// Monday-first, locale-independent. Deliberately has no `.locale` set —
    /// `.iso8601`'s firstWeekday/minimumDaysInFirstWeek are part of the
    /// calendar identifier itself and must not be overridden by a region.
    static let iso8601: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal
    }()

    /// Monday 00:00 of the week containing `date` — correct regardless of the
    /// device's region settings and regardless of `date`'s own weekday.
    static func mondayOfWeek(containing date: Date) -> Date {
        var comps = iso8601.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday, per ISO 8601
        return iso8601.date(from: comps) ?? iso8601.startOfDay(for: date)
    }
}
