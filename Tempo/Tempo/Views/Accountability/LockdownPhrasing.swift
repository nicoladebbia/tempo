//
// LockdownPhrasing.swift
// Tempo
//
// The words and the pace maths of the Lockdown page, as plain functions over
// plain values. Nothing here touches SwiftData or the clock, so each rule can
// be tested on its own and the views only draw the answer.
//

import Foundation

// MARK: - PS5Countdown

/// How the time left until PS5 time is written. The view model clamps the
/// countdown at zero, so "0m" must never be written as if time were left.
enum PS5Countdown {
    /// "12m", "1h 5m", or nil when less than a whole minute is left.
    static func remaining(_ seconds: TimeInterval) -> String? {
        let minutes = Int(seconds / 60)
        guard seconds > 0, minutes > 0 else {
            return nil
        }
        let hours = minutes / 60
        return hours > 0 ? String(localized: "\(hours)h \(minutes % 60)m") : String(localized: "\(minutes)m")
    }

    /// A short "less than" line for the last stretch. Whole minutes round up,
    /// so 11m 30s left reads "Less than 12m", never the untrue "Less than 11m".
    static func lessThan(_ seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return String(localized: "PS5 time has passed.")
        }
        if seconds < 60 {
            return String(localized: "Less than a minute until PS5 time.")
        }
        let minutes = Int((seconds / 60).rounded(.up))
        return String(localized: "Less than \(minutes)m until PS5 time.")
    }

    /// "Only 12m until PS5 time." for the title of a recommendation.
    static func only(_ seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return String(localized: "PS5 time has passed.")
        }
        if seconds < 60 {
            return String(localized: "Under a minute until PS5 time.")
        }
        let minutes = Int((seconds / 60).rounded(.up))
        return String(localized: "Only \(minutes)m until PS5 time.")
    }

    /// The status line under the dial while tasks are still open.
    static func statusLine(seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return String(localized: "PS5 time is here. Handle your business.")
        }
        guard let left = remaining(seconds) else {
            return String(localized: "Under a minute. Move.")
        }
        if seconds < 30 * 60 {
            return String(localized: "\(left). Move.")
        }
        if seconds < 60 * 60 {
            return String(localized: "\(left). Clock's ticking.")
        }
        if seconds < 2 * 3600 {
            return String(localized: "\(left) left. Focus up.")
        }
        return String(localized: "\(left) until your usual PS5 time")
    }
}

// MARK: - LockdownPace

/// Reads how the day is going and what it means for finishing by PS5 time.
enum LockdownPace {
    /// What the pace read-out says. The view turns it into a sentence.
    enum Reading: Equatable {
        /// PS5 time has passed with tasks still open.
        case passed(remaining: Int)
        /// The study target alone cannot fit in the time left.
        case studyBehind(minutes: Int)
        /// At the pace so far the rest does not fit.
        case wontFinish
        /// The rest fits; `finish` is when, `ahead` is true with a lot of room.
        case onPace(finish: Date, ahead: Bool)

        var onTrack: Bool {
            switch self {
            case .passed,
                 .studyBehind,
                 .wontFinish: false
            case .onPace: true
            }
        }
    }

    /// The working day the pace is measured over: 8 AM to 7:30 PM.
    static let activeDay: TimeInterval = 11.5 * 3600
    /// Pace is only a guess once this much of the day has gone by. Earlier, one
    /// task done says nothing about the rest.
    static let minimumElapsed: TimeInterval = 30 * 60

    static func reading(
        done: Int,
        total: Int,
        timeToPS5: TimeInterval,
        studyMinutesRemaining: Double,
        now: Date
    ) -> Reading? {
        let remaining = total - done
        guard total > 0, remaining > 0 else {
            return nil
        }

        if timeToPS5 <= 0 {
            return .passed(remaining: remaining)
        }

        // Study alone can already be too much for the time left. That needs no pace.
        let studySeconds = max(0, studyMinutesRemaining) * 60
        if studySeconds > timeToPS5 {
            return .studyBehind(minutes: Int(((studySeconds - timeToPS5) / 60).rounded(.up)))
        }

        // A pace needs something done and enough of the day behind it. With
        // nothing done there is no pace to read, so no finish time is promised.
        let elapsed = activeDay - timeToPS5
        guard done > 0, elapsed >= minimumElapsed else {
            return nil
        }

        let secondsPerTask = elapsed / Double(done)
        let secondsForRest = secondsPerTask * Double(remaining)

        if secondsForRest > timeToPS5 {
            return .wontFinish
        }
        return .onPace(
            finish: now.addingTimeInterval(secondsForRest),
            ahead: secondsForRest < timeToPS5 * 0.5
        )
    }

    /// The drill-sergeant sentence for a reading.
    static func message(for reading: Reading, finishFormat: (Date) -> String) -> String {
        switch reading {
        case let .passed(remaining):
            remaining == 1
                ? String(localized: "PS5 time has passed. 1 task still incomplete.")
                : String(localized: "PS5 time has passed. \(remaining) tasks still incomplete.")
        case let .studyBehind(minutes):
            String(localized: "You're \(minutes)min short on study before PS5 time. Open the timer.")
        case .wontFinish:
            String(localized: "WARNING: At current pace, you won't finish in time. Accelerate.")
        case let .onPace(finish, ahead):
            ahead
                ? String(localized: "On pace to finish by \(finishFormat(finish)). Ahead of schedule.")
                : String(localized: "At this pace, you'll finish by \(finishFormat(finish)). Stay focused.")
        }
    }
}

// MARK: - Plural

enum Plural {
    /// "1 day", "2 days", "0 days".
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        if plural == nil {
            switch singular {
            case "day": return String(localized: "\(n) days")
            case "session": return String(localized: "\(n) sessions")
            default: break
            }
        }
        return "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Days left until a date, the way an exam countdown is written.
    static func daysLeft(_ days: Int) -> String {
        switch days {
        case ..<0: String(localized: "Passed")
        case 0: String(localized: "Today")
        case 1: String(localized: "Tomorrow")
        default: String(localized: "\(days) days left")
        }
    }
}

// MARK: - Weekly days

/// Counts days for the weekly report card from real per-day numbers. A rate
/// scaled to seven days says "7/7" after two perfect days; counting days
/// against the days that were tracked cannot.
enum WeeklyDays {
    struct Tally: Equatable {
        /// Days on which every task of the category was done.
        let completed: Int
        /// Days on which the category had any task at all.
        let tracked: Int

        var progress: Double {
            tracked > 0 ? Double(completed) / Double(tracked) : 0
        }
    }

    static func tally(_ days: [(completed: Int, total: Int)]) -> Tally {
        let tracked = days.filter { $0.total > 0 }
        return Tally(
            completed: tracked.filter { $0.completed >= $0.total }.count,
            tracked: tracked.count
        )
    }

    static func phrase(_ tally: Tally) -> String {
        guard tally.tracked > 0 else {
            return String(localized: "No days tracked yet")
        }
        return String(localized: "\(tally.completed) of \(Plural.count(tally.tracked, "day")) completed")
    }
}
