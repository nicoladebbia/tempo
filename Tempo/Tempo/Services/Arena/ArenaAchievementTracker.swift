//
// ArenaAchievementTracker.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation

// MARK: - ArenaAchievementTracker

// Works out, from the user's own records, how far along each achievement is and
// the day it was reached. Only badges the app can really measure are tracked:
// a badge that needs data Tempo does not keep (heart-rate strain, personal
// records, recovery colours) is never shown, because a bar that can never fill
// is a made-up number. Pure functions, so the rules are unit tested without a
// database.

enum ArenaAchievementTracker {
    struct Progress: Equatable {
        var value: Int
        /// The day the target was reached, nil while it has not been.
        var earnedOn: Date?
    }

    /// Everything in `AchievementLibrary` that is counted from records Tempo keeps.
    static let trackedBadgeIDs: Set<String> = [
        "iron_novice", "century_club", "iron_warrior", "dawn_warrior", "volume_king", "night_owl",
        "knowledge_seeker", "scholar", "pomodoro_master", "deep_focus",
        "clean_eater", "meal_prep_king",
        "first_steps", "the_grind", "diamond_hands", "no_days_off", "perfect_week", "perfect_month",
        "level_10", "level_25",
    ]

    static func isTracked(_ badgeID: String) -> Bool {
        trackedBadgeIDs.contains(badgeID)
    }

    static func evaluate(
        records: ArenaXPLedger.Records,
        level: Int,
        longestStreak: Int,
        now: Date,
        targets: [String: Int],
        calendar: Calendar = ArenaCalendar.calendar()
    ) -> [String: Progress] {
        var result: [String: Progress] = [:]
        func target(_ id: String) -> Int {
            max(1, targets[id] ?? 1)
        }

        // Workouts.
        let workouts = records.workouts.sorted { $0.start < $1.start }
        for id in ["iron_novice", "century_club", "iron_warrior"] {
            result[id] = cumulative(workouts.map { ($0.day, 1) }, target: target(id))
        }
        result["dawn_warrior"] = cumulative(
            workouts.filter { ($0.startHour ?? 12) < 8 }.map { ($0.day, 1) }, target: target("dawn_warrior")
        )
        result["night_owl"] = cumulative(
            workouts.filter { ($0.startHour ?? 12) < 4 }.map { ($0.day, 1) }, target: target("night_owl")
        )
        result["volume_king"] = cumulative(
            workouts.map { ($0.day, Int($0.volumeKg.rounded())) }, target: target("volume_king")
        )

        // Study.
        let sessions = records.studySessions.sorted { $0.start < $1.start }
        for id in ["knowledge_seeker", "scholar"] {
            result[id] = cumulative(sessions.map { ($0.day, $0.minutes) }, target: target(id))
        }
        result["pomodoro_master"] = cumulative(sessions.map { ($0.day, $0.pomodoros) }, target: target("pomodoro_master"))
        result["deep_focus"] = cumulative(
            sessions.filter { $0.pomodoros >= 4 }.map { ($0.day, 1) }, target: target("deep_focus")
        )

        // Meals and tasks, in a row.
        let mealDays = Set(records.meals.map { ArenaCalendar.dayKey($0.day, calendar: calendar) })
        result["clean_eater"] = longestRun(mealDays, target: target("clean_eater"), calendar: calendar)
        let mainMealDays = Set(records.mainMealDayKeys(calendar: calendar))
        result["meal_prep_king"] = longestRun(mainMealDays, target: target("meal_prep_king"), calendar: calendar)
        let taskDays = Set(records.taskDays.filter(\.allDone).map { ArenaCalendar.dayKey($0.day, calendar: calendar) })
        result["perfect_week"] = longestRun(taskDays, target: target("perfect_week"), calendar: calendar)
        result["perfect_month"] = longestRun(taskDays, target: target("perfect_month"), calendar: calendar)

        // First day with anything in it.
        let firstDay = records.activityDays(calendar: calendar).min()
        result["first_steps"] = Progress(
            value: firstDay == nil ? 0 : 1,
            earnedOn: firstDay.flatMap { ArenaCalendar.date(forKey: $0, calendar: calendar) }
        )

        // Streak and level badges have no history to look back on: reached today.
        for id in ["no_days_off", "the_grind", "diamond_hands"] {
            result[id] = reached(longestStreak, target: target(id), on: now)
        }
        for id in ["level_10", "level_25"] {
            result[id] = reached(level, target: target(id), on: now)
        }
        return result
    }

    // MARK: - Counting

    /// A running total of `(day, amount)` and the day it first reached `target`.
    private static func cumulative(_ items: [(Date, Int)], target: Int) -> Progress {
        var total = 0
        var crossed: Date?
        for (day, amount) in items.sorted(by: { $0.0 < $1.0 }) {
            total += amount
            if crossed == nil, total >= target {
                crossed = day
            }
        }
        return Progress(value: min(total, target), earnedOn: crossed)
    }

    /// The longest run of consecutive days, and the day the run first hit `target`.
    private static func longestRun(_ dayKeys: Set<String>, target: Int, calendar: Calendar) -> Progress {
        let days = dayKeys.compactMap { ArenaCalendar.date(forKey: $0, calendar: calendar) }.sorted()
        var run = 0
        var best = 0
        var previous: Date?
        var crossed: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            if crossed == nil, run >= target {
                crossed = day
            }
            previous = day
        }
        return Progress(value: min(best, target), earnedOn: crossed)
    }

    private static func reached(_ value: Int, target: Int, on day: Date) -> Progress {
        Progress(value: min(value, target), earnedOn: value >= target ? day : nil)
    }
}
