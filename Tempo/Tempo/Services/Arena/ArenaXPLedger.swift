//
// ArenaXPLedger.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation
import SwiftData

// MARK: - ArenaXPLedger

// The one place XP is written. Nothing in the app used to create XP rows, so
// the Arena showed zero for everyone. The ledger reads what the user actually
// did (finished workouts, logged meals, study sessions, daily tasks), asks
// `XPEngine.dayAwards(for:)` what each day is worth, and brings the stored
// `XPEvent` rows in line with that: one row per day per source.
//
// It is safe to run as often as you like. Run it twice and nothing changes;
// undo a workout and that day's XP shrinks with it. Every screen that shows XP
// then reads the same rows (the Arena, the Watch, the progress report), and the
// ledger also mirrors the total and level onto `UserProfile`, which Settings
// and the data export read. Rows from sources the ledger does not own are left
// alone but still counted.

enum ArenaXPLedger {
    // MARK: - Records (the user's own data, as plain values)

    struct Records: Equatable {
        struct Workout: Equatable {
            /// Start of the day the workout belongs to.
            var day: Date
            /// When it began, for ordering; the day itself when unknown.
            var start: Date
            var startHour: Int?
            var exercises: Int
            var volumeKg: Double
        }

        struct Meal: Equatable {
            var day: Date
            /// "breakfast", "lunch", "dinner" or "snack".
            var slot: String
        }

        struct Study: Equatable {
            var day: Date
            var start: Date
            var minutes: Int
            var pomodoros: Int
        }

        struct TaskDay: Equatable {
            var day: Date
            var allDone: Bool
        }

        var workouts: [Workout] = []
        var meals: [Meal] = []
        var studySessions: [Study] = []
        var taskDays: [TaskDay] = []

        /// Days with breakfast, lunch and dinner all logged.
        func mainMealDayKeys(calendar: Calendar) -> [String] {
            var slotsByDay: [String: Set<String>] = [:]
            for meal in meals {
                slotsByDay[ArenaCalendar.dayKey(meal.day, calendar: calendar), default: []].insert(meal.slot)
            }
            return slotsByDay.filter { $0.value.isSuperset(of: ["breakfast", "lunch", "dinner"]) }.map(\.key)
        }

        /// Every day that has anything in it.
        func activityDays(calendar: Calendar) -> Set<String> {
            var days = Set<String>()
            for workout in workouts {
                days.insert(ArenaCalendar.dayKey(workout.day, calendar: calendar))
            }
            for meal in meals {
                days.insert(ArenaCalendar.dayKey(meal.day, calendar: calendar))
            }
            for session in studySessions {
                days.insert(ArenaCalendar.dayKey(session.day, calendar: calendar))
            }
            for day in taskDays where day.allDone {
                days.insert(ArenaCalendar.dayKey(day.day, calendar: calendar))
            }
            return days
        }
    }

    // MARK: - Summary

    struct Summary: Equatable {
        var totalXP: Int
        var level: Int
        /// Today's key, "YYYY-MM-DD".
        var today: String
        /// Per-day totals the friends board and challenges rank on.
        var days: [ArenaStatsDayDTO]
        /// Names of achievements unlocked in the last two days, new in this run.
        var newlyEarned: [String]
        /// XP by day key, every day with any.
        var xpByDay: [String: Int]
        /// True when the user's records could not be read this time. Nothing was
        /// changed and nothing should be sent to friends: the numbers are not real.
        var isPartial = false

        func xp(in weekStart: Date, calendar: Calendar = ArenaCalendar.calendar()) -> Int {
            (0 ..< 7).reduce(0) { total, offset in
                let key = ArenaCalendar.dayKey(ArenaCalendar.addingDays(offset, to: weekStart, calendar: calendar), calendar: calendar)
                return total + (xpByDay[key] ?? 0)
            }
        }
    }

    /// The server only keeps this many days back. All of them are sent every time,
    /// even at zero, so a day that lost its XP (an undone workout) is corrected on
    /// the server too; the server makes no row for an empty day.
    static let maxDaysBack = 62
    /// The server's own per-day caps; sending more would be refused.
    static let maxXPPerDay = 5000
    static let maxWorkoutsPerDay = 20
    static let maxStudyMinutesPerDay = 1440

    // MARK: - Pure rules

    /// What each day held, counted from the records.
    static func activity(from records: Records, calendar: Calendar = ArenaCalendar.calendar()) -> [String: XPDayActivity] {
        var days: [String: XPDayActivity] = [:]

        for workout in records.workouts {
            let key = ArenaCalendar.dayKey(workout.day, calendar: calendar)
            var day = days[key] ?? XPDayActivity()
            day.workouts += 1
            day.exercisesPerformed += workout.exercises
            if let hour = workout.startHour {
                day.earliestWorkoutHour = min(day.earliestWorkoutHour ?? hour, hour)
            }
            days[key] = day
        }

        var slotsByDay: [String: Set<String>] = [:]
        for meal in records.meals {
            slotsByDay[ArenaCalendar.dayKey(meal.day, calendar: calendar), default: []].insert(meal.slot)
        }
        for (key, slots) in slotsByDay {
            var day = days[key] ?? XPDayActivity()
            day.mealSlotsLogged = slots.count
            day.mainMealsAllLogged = slots.isSuperset(of: ["breakfast", "lunch", "dinner"])
            days[key] = day
        }

        for session in records.studySessions {
            let key = ArenaCalendar.dayKey(session.day, calendar: calendar)
            var day = days[key] ?? XPDayActivity()
            day.studyMinutes += session.minutes
            let hour = calendar.component(.hour, from: session.start)
            day.earliestStudyHour = min(day.earliestStudyHour ?? hour, hour)
            days[key] = day
        }

        for taskDay in records.taskDays where taskDay.allDone {
            let key = ArenaCalendar.dayKey(taskDay.day, calendar: calendar)
            var day = days[key] ?? XPDayActivity()
            day.allNonNegotiablesDone = true
            days[key] = day
        }
        return days
    }

    // MARK: - Reading the user's records

    @MainActor
    static func records(in context: ModelContext, calendar: Calendar = ArenaCalendar.calendar()) throws -> Records {
        var records = Records()

        let workouts = try context.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.statusRaw == "completed" }
        ))
        records.workouts = workouts.map { plan in
            let day = calendar.startOfDay(for: plan.date)
            return Records.Workout(
                day: day,
                start: plan.startedAt ?? day,
                startHour: plan.startedAt.map { calendar.component(.hour, from: $0) },
                exercises: plan.performedExerciseCount,
                volumeKg: plan.totalVolume
            )
        }

        let meals = try context.fetch(FetchDescriptor<MealLog>())
        records.meals = meals.map { Records.Meal(day: calendar.startOfDay(for: $0.dayDate), slot: $0.mealTypeRaw) }

        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        records.studySessions = sessions.filter { $0.durationMinutes > 0 }.map {
            Records.Study(
                day: calendar.startOfDay(for: $0.startTime), start: $0.startTime,
                minutes: $0.durationMinutes, pomodoros: $0.completedPomodoros
            )
        }

        let days = try context.fetch(FetchDescriptor<DailyAccountability>())
        records.taskDays = days.map { Records.TaskDay(day: calendar.startOfDay(for: $0.date), allDone: $0.allComplete) }
        return records
    }

    // MARK: - Sync

    /// Brings the stored XP, the achievements and the profile in line with the
    /// user's records. Idempotent.
    @MainActor
    @discardableResult
    static func sync(
        in context: ModelContext,
        engine: any XPEngineProtocol,
        now: Date = Date(),
        calendar: Calendar = ArenaCalendar.calendar()
    ) -> Summary {
        // A read that fails must not look like an empty history: that would wipe every
        // XP row, zero the profile and tell friends. Leave everything as it is instead.
        let records: Records
        let existing: [XPEvent]
        let achievements: [Achievement]
        do {
            records = try Self.records(in: context, calendar: calendar)
            existing = try context.fetch(FetchDescriptor<XPEvent>())
            achievements = try context.fetch(FetchDescriptor<Achievement>())
        } catch {
            let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
            return Summary(
                totalXP: profile?.totalXP ?? 0, level: profile?.currentLevel ?? 1,
                today: ArenaCalendar.dayKey(now, calendar: calendar), days: [], newlyEarned: [],
                xpByDay: [:], isPartial: true
            )
        }
        let activity = activity(from: records, calendar: calendar)

        // XP the days are worth, by day and source.
        struct Entry {
            var day: Date
            var source: XPSource
            var amount: Int
            var text: String
        }
        var desired: [String: Entry] = [:]
        func add(_ day: Date, _ source: XPSource, _ amount: Int, _ text: String) {
            let key = "\(ArenaCalendar.dayKey(day, calendar: calendar))|\(source.rawValue)"
            if var entry = desired[key] {
                entry.amount += amount
                entry.text = text
                desired[key] = entry
            } else {
                desired[key] = Entry(day: calendar.startOfDay(for: day), source: source, amount: amount, text: text)
            }
        }
        for (key, day) in activity {
            guard let date = ArenaCalendar.date(forKey: key, calendar: calendar) else {
                continue
            }
            for award in engine.dayAwards(for: day) {
                add(date, award.source, award.amount, award.reason)
            }
        }

        // Rows the ledger does not own (none are written today) still count.
        let owned = Set([XPSource.workout, .meal, .study, .nonNegotiable, .achievement].map(\.rawValue))
        let foreignXP = existing.filter { !owned.contains($0.sourceRaw) }.reduce(0) { $0 + $1.amount }
        let activityXP = desired.values.reduce(0) { $0 + $1.amount }

        // Achievements: earned ones stay earned; new ones come from the records.
        let tracked = achievements.filter { ArenaAchievementTracker.isTracked($0.badgeID) }
        let streak = overallStreak(in: context)
        let longestStreak = max(streak?.longestCount ?? 0, streak?.currentCount ?? 0)
        let targets = Dictionary(tracked.map { ($0.badgeID, $0.targetValue) }, uniquingKeysWith: { first, _ in first })

        // What the days were worth: dates the level badges to the day their level was reached.
        var activityByDay: [Date: Int] = [:]
        for entry in desired.values {
            activityByDay[entry.day, default: 0] += entry.amount
        }

        var progress: [String: ArenaAchievementTracker.Progress] = [:]
        var earned = Set(tracked.filter { $0.earnedAt != nil }.map(\.badgeID))
        // Level badges depend on XP, and achievement XP raises the level (and the day it was reached),
        // so run until steady. The first pass settles who is earned, the second their days.
        for pass in 0 ..< 4 {
            let achievementXP = tracked.filter { earned.contains($0.badgeID) }.reduce(0) { $0 + $1.effectiveXPReward }
            var byDay = activityByDay
            for achievement in tracked where !achievement.badgeID.hasPrefix("level_") {
                if let day = achievement.earnedAt ?? progress[achievement.badgeID]?.earnedOn {
                    byDay[calendar.startOfDay(for: day), default: 0] += achievement.effectiveXPReward
                }
            }
            progress = ArenaAchievementTracker.evaluate(
                records: records,
                level: engine.currentLevel(totalXP: activityXP + achievementXP + foreignXP),
                longestStreak: longestStreak, currentStreak: streak?.currentCount ?? 0,
                activityXPByDay: byDay.map { (day: $0.key, xp: $0.value) }, xpForLevel: { engine.xpForLevel($0) },
                now: now, targets: targets, calendar: calendar
            )
            let next = Set(tracked.filter { $0.earnedAt != nil || progress[$0.badgeID]?.earnedOn != nil }.map(\.badgeID))
            if next == earned, pass >= 1 {
                break
            }
            earned = next
        }

        var newlyEarned: [String] = []
        let recent = ArenaCalendar.addingDays(-2, to: calendar.startOfDay(for: now), calendar: calendar)
        for achievement in tracked {
            guard let result = progress[achievement.badgeID] else {
                continue
            }
            if achievement.earnedAt == nil, let day = result.earnedOn {
                achievement.earnedAt = day
                if day >= recent {
                    newlyEarned.append(achievement.name)
                }
            }
            let value = achievement.earnedAt != nil ? max(result.value, achievement.targetValue) : result.value
            if achievement.progressValue != value {
                achievement.progressValue = value
            }
        }
        for achievement in tracked {
            if let day = achievement.earnedAt {
                let count = tracked.filter { $0.earnedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }.count
                add(
                    day,
                    .achievement,
                    achievement.effectiveXPReward,
                    count == 1 ? "Unlocked \(achievement.name)" : "Unlocked \(count) achievements"
                )
            }
        }

        // Bring the stored rows in line: update the match, delete the stale and duplicate, add the missing.
        var matched = Set<String>()
        for event in existing where owned.contains(event.sourceRaw) {
            let key = "\(ArenaCalendar.dayKey(event.date, calendar: calendar))|\(event.sourceRaw)"
            if let want = desired[key], !matched.contains(key) {
                matched.insert(key)
                if event.amount != want.amount {
                    event.amount = want.amount
                }
                if event.eventDescription != want.text {
                    event.eventDescription = want.text
                }
                if event.date != want.day {
                    event.date = want.day
                }
            } else {
                context.delete(event)
            }
        }
        for (key, want) in desired where !matched.contains(key) {
            let event = XPEvent(date: want.day, source: want.source, amount: want.amount, description: want.text)
            // XPEvent cuts its own day with the device calendar; the ledger's day is the one that counts.
            event.date = want.day
            context.insert(event)
        }

        // Totals: what the rows now say.
        let totalXP = max(0, desired.values.reduce(0) { $0 + $1.amount } + foreignXP)
        let level = engine.currentLevel(totalXP: totalXP)
        if let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            if profile.totalXP != totalXP {
                profile.totalXP = totalXP
            }
            if profile.currentLevel != level {
                profile.currentLevel = level
            }
        }
        if context.hasChanges {
            try? context.save()
        }

        // What friends and challenges rank on.
        var xpByDay: [String: Int] = [:]
        for entry in desired.values {
            xpByDay[ArenaCalendar.dayKey(entry.day, calendar: calendar), default: 0] += entry.amount
        }
        let todayStart = calendar.startOfDay(for: now)
        var days: [ArenaStatsDayDTO] = []
        for offset in 0 ..< maxDaysBack {
            let date = ArenaCalendar.addingDays(-offset, to: todayStart, calendar: calendar)
            let key = ArenaCalendar.dayKey(date, calendar: calendar)
            let activityDay = activity[key]
            let xp = xpByDay[key] ?? 0
            let workouts = activityDay?.workouts ?? 0
            let minutes = activityDay?.studyMinutes ?? 0
            days.append(ArenaStatsDayDTO(
                day: key, xp: min(xp, maxXPPerDay), workouts: min(workouts, maxWorkoutsPerDay),
                studyMinutes: min(minutes, maxStudyMinutesPerDay)
            ))
        }
        return Summary(
            totalXP: totalXP, level: level, today: ArenaCalendar.dayKey(now, calendar: calendar),
            days: days, newlyEarned: newlyEarned, xpByDay: xpByDay
        )
    }

    // MARK: - Streak (one place)

    /// The overall streak row every screen reads.
    @MainActor
    static func overallStreak(in context: ModelContext) -> Streak? {
        (try? context.fetch(FetchDescriptor<Streak>(predicate: #Predicate { $0.typeRaw == "overall" })))?.first
    }

    /// Days in a row, as every screen should show them.
    @MainActor
    static func streakDays(in context: ModelContext) -> Int {
        overallStreak(in: context)?.currentCount ?? 0
    }
}
