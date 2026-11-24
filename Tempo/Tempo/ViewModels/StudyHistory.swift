//
// StudyHistory.swift
// Tempo
//
// What the Study page works out from the focus sessions: minutes per day,
// the best day, minutes per subject, the time-of-day grid, and what to say
// when today has no sessions. On plain values, so each rule has a test.
//

import Foundation

// MARK: - StudyEntry

/// One finished focus session, as plain values.
struct StudyEntry: Equatable {
    var startTime: Date
    var durationMinutes: Int
    var subject: String?
}

// MARK: - StudyHistory

enum StudyHistory {
    struct Day: Equatable {
        let date: Date
        let minutes: Int
    }

    struct SubjectTotal: Equatable {
        let subject: String
        let minutes: Int
    }

    /// Hours shown on the time-of-day grid: 06:00 to 21:59.
    static let heatmapHours = 6 ... 21

    /// Minutes per calendar day for the `days` days ending on `today`, oldest
    /// first. A day without sessions is a 0, so a chart always has `days` bars.
    static func lastDays(
        _ entries: [StudyEntry], days: Int = 7, endingOn today: Date, calendar: Calendar = .current
    ) -> [Day] {
        let end = calendar.startOfDay(for: today)
        return (0 ..< days).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -back, to: end),
                  let next = calendar.date(byAdding: .day, value: 1, to: start)
            else {
                return nil
            }
            let minutes = entries
                .filter { $0.startTime >= start && $0.startTime < next }
                .reduce(0) { $0 + $1.durationMinutes }
            return Day(date: start, minutes: minutes)
        }
    }

    /// The day with the most minutes. Nil when nothing was studied.
    static func bestDay(_ entries: [StudyEntry], calendar: Calendar = .current) -> Day? {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startTime) }
        return byDay
            .map { Day(date: $0.key, minutes: $0.value.reduce(0) { $0 + $1.durationMinutes }) }
            .filter { $0.minutes > 0 }
            // Earlier day wins a tie, so the answer does not change between launches.
            .max { ($0.minutes, $1.date) < ($1.minutes, $0.date) }
    }

    /// Minutes per subject from `since` on, biggest first. A session with no
    /// subject counts as "Untagged".
    static func subjectTotals(_ entries: [StudyEntry], since: Date) -> [SubjectTotal] {
        var totals = [String: Int]()
        for entry in entries where entry.startTime >= since {
            let name = entry.subject.flatMap { $0.isEmpty ? nil : $0 } ?? "Untagged"
            totals[name, default: 0] += entry.durationMinutes
        }
        return totals
            .map { SubjectTotal(subject: $0.key, minutes: $0.value) }
            .sorted { ($0.minutes, $1.subject) > ($1.minutes, $0.subject) }
    }

    /// Minutes by weekday (columns, Monday first) and hour (rows, 06:00 to
    /// 21:00) over the 30 days before `now`.
    static func heatmap(
        _ entries: [StudyEntry], now: Date, calendar: Calendar = .current
    ) -> [[Int]] {
        let since = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        var grid = Array(repeating: Array(repeating: 0, count: heatmapHours.count), count: 7)
        for entry in entries where entry.startTime >= since {
            let hour = calendar.component(.hour, from: entry.startTime)
            guard heatmapHours.contains(hour) else {
                continue
            }
            // Weekday runs 1 (Sunday) to 7 (Saturday); the grid starts on Monday.
            let column = (calendar.component(.weekday, from: entry.startTime) + 5) % 7
            grid[column][hour - heatmapHours.lowerBound] += entry.durationMinutes
        }
        return grid
    }

    /// "2h 5m", "2h", "45m".
    static func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0, rest > 0 {
            return "\(hours)h \(rest)m"
        }
        return hours > 0 ? "\(hours)h" : "\(rest)m"
    }
}

// MARK: - StudyTodayList

/// What the list of today's sessions says when it has no rows. The page used to
/// say "No study sessions yet" under two hours of study that had been counted
/// without the timer: the empty state has to agree with the number above it.
enum StudyTodayList {
    enum Empty: Equatable {
        /// Nothing studied, nothing listed.
        case nothingYet
        /// Minutes are counted today but no session backs them.
        case minutesWithoutSessions
    }

    /// Nil when there are sessions to list.
    static func empty(minutesToday: Int, sessionCount: Int) -> Empty? {
        guard sessionCount == 0 else {
            return nil
        }
        return minutesToday > 0 ? .minutesWithoutSessions : .nothingYet
    }

    /// The study minutes to show while a delete can still be undone: the hidden
    /// session's minutes are already off the total.
    static func shownMinutes(counted: Int, removed: Int) -> Int {
        max(0, counted - max(0, removed))
    }
}
