//
// ArenaChallengeInfo.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation

// MARK: - ArenaChallengeMetric

/// What a challenge counts. Only what the app really measures and pushes
/// (ArenaStatsDayDTO): XP, finished workouts and focus minutes.
enum ArenaChallengeMetric: String, CaseIterable, Identifiable {
    case xpTotal = "xp_total"
    case workoutCount = "workout_count"
    case studyMinutes = "study_minutes"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .xpTotal: String(localized: "Most XP")
        case .workoutCount: String(localized: "Most workouts")
        case .studyMinutes: String(localized: "Most focus time")
        }
    }

    /// For a segmented control, where three full names do not fit.
    var shortTitle: String {
        switch self {
        case .xpTotal: "XP"
        case .workoutCount: String(localized: "Workouts")
        case .studyMinutes: String(localized: "Focus")
        }
    }

    var symbol: String {
        switch self {
        case .xpTotal: "bolt.fill"
        case .workoutCount: "dumbbell.fill"
        case .studyMinutes: "book.fill"
        }
    }

    /// "1,240 XP", "3 workouts", "1h 30m".
    func format(_ score: Int) -> String {
        switch self {
        case .xpTotal:
            "\(score.formatted()) XP"
        case .workoutCount:
            ArenaText.workouts(score)
        case .studyMinutes:
            score >= 60 ? String(localized: "\(score / 60)h \(score % 60)m") : String(localized: "\(score) min")
        }
    }

    /// The number alone, and what it counts, for a big figure with a small unit.
    func parts(_ score: Int) -> (value: String, unit: String) {
        switch self {
        case .xpTotal: (score.formatted(), "XP")
        case .workoutCount: (score.formatted(), score == 1 ? String(localized: "workout") : String(localized: "workouts"))
        case .studyMinutes: (score.formatted(), String(localized: "min"))
        }
    }
}

// MARK: - ArenaChallengeDTO + display

extension ArenaChallengeDTO {
    var metricKind: ArenaChallengeMetric? {
        ArenaChallengeMetric(rawValue: metric)
    }

    var isJoined: Bool {
        myStatus == "joined"
    }

    var isInvitation: Bool {
        myStatus == "invited"
    }

    var isFinished: Bool {
        status == "completed"
    }

    /// Whole days from today to the last day: 0 on the last day.
    func daysLeft(now: Date = Date(), calendar: Calendar = ArenaCalendar.calendar()) -> Int {
        Self.days(from: ArenaCalendar.dayKey(now, calendar: calendar), to: endDay, calendar: calendar)
    }

    /// Whole days from today to the first day: 0 or less once it has started.
    func daysUntilStart(now: Date = Date(), calendar: Calendar = ArenaCalendar.calendar()) -> Int {
        Self.days(from: ArenaCalendar.dayKey(now, calendar: calendar), to: startDay, calendar: calendar)
    }

    /// How far through its dates the challenge is, 0 to 1.
    func timelineProgress(now: Date = Date(), calendar: Calendar = ArenaCalendar.calendar()) -> Double {
        let total = Self.days(from: startDay, to: endDay, calendar: calendar) + 1
        guard total > 0 else {
            return 0
        }
        let elapsed = Self.days(from: startDay, to: ArenaCalendar.dayKey(now, calendar: calendar), calendar: calendar) + 1
        return min(max(Double(elapsed) / Double(total), 0), 1)
    }

    /// The line under the title: when it starts, how long is left, or that it ended.
    func timeLine(now: Date = Date(), calendar: Calendar = ArenaCalendar.calendar()) -> String {
        if isFinished {
            return String(localized: "Finished")
        }
        let untilStart = daysUntilStart(now: now, calendar: calendar)
        if untilStart > 0 {
            return ArenaText.startsIn(untilStart)
        }
        return ArenaText.daysLeft(daysLeft(now: now, calendar: calendar))
    }

    private static func days(from first: String, to second: String, calendar: Calendar) -> Int {
        guard let start = ArenaCalendar.date(forKey: first, calendar: calendar),
              let end = ArenaCalendar.date(forKey: second, calendar: calendar)
        else {
            return 0
        }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
