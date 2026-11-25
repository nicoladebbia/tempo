//
// ArenaViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - ArenaLoadState

enum ArenaLoadState {
    case loading
    case loaded
}

// MARK: - ArenaViewModel

// The numbers on the Arena home, all read from the one place each lives:
//   - XP and level: the XPEvent rows the ArenaXPLedger keeps in line with the
//     user's own records (also mirrored onto UserProfile for Settings)
//   - streak: the overall Streak row (ArenaXPLedger.streakDays)
//   - weeks: ISO weeks, Monday to Sunday (ArenaCalendar), the same cut as the
//     friends leaderboard
// Nothing here is invented: a number nothing produces is not on the page.

@Observable
@MainActor
final class ArenaViewModel {
    // MARK: - State

    var loadState: ArenaLoadState = .loading

    // XP / Level
    var todayXP = 0
    var totalXP = 0
    var level = 1
    var levelTitle = "Recruit"
    var nextLevelTitle = "Recruit II"
    var xpProgress = 0.0
    var xpForNextLevel = 100
    var streakDays = 0

    // XP gain animation
    var showXPGain = false
    var lastXPGainAmount = 0

    // Daily XP goal
    var dailyXPGoal = 100
    var dailyXPProgress = 0.0

    /// Streak freeze
    var freezesAvailable = 0

    /// XP by source, today.
    var xpBreakdown: [XPBreakdownRow] = []

    // Achievements and activity (the one "earned" story)
    var recentAchievements: [Achievement] = []
    var totalEarned = 0
    var totalTracked = 0
    var recentDays: [ArenaXPDay] = []

    // This week and last week
    var weekXP = 0
    var weekWorkouts = 0
    var weekStudyMinutes = 0
    var lastWeekXP = 0
    var lastWeekWorkouts = 0
    var lastWeekStudyMinutes = 0
    var lastWeekAchievements = 0

    // MARK: - Dependencies

    private let xpEngine: any XPEngineProtocol

    init(xpEngine: any XPEngineProtocol) {
        self.xpEngine = xpEngine
    }

    // MARK: - Load

    /// Reads fresh from the store, so it always sees what the ledger just wrote.
    func load(
        in context: ModelContext,
        summary: ArenaXPLedger.Summary,
        now: Date = Date(),
        calendar: Calendar = ArenaCalendar.calendar()
    ) {
        let events = (try? context.fetch(FetchDescriptor<XPEvent>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let achievements = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
        let streak = ArenaXPLedger.overallStreak(in: context)
        apply(
            events: events, achievements: achievements, settings: settings, streak: streak,
            summary: summary, now: now, calendar: calendar
        )
    }

    func apply(
        events: [XPEvent],
        achievements: [Achievement],
        settings: UserSettings?,
        streak: Streak?,
        summary: ArenaXPLedger.Summary,
        now: Date,
        calendar: Calendar = ArenaCalendar.calendar()
    ) {
        let todayKey = ArenaCalendar.dayKey(now, calendar: calendar)
        let todayEvents = events.filter { ArenaCalendar.dayKey($0.date, calendar: calendar) == todayKey }

        let previousTodayXP = todayXP
        let newTodayXP = todayEvents.reduce(0) { $0 + $1.amount }
        todayXP = newTodayXP

        // One total, one level: the rows the ledger keeps.
        let total = events.reduce(0) { $0 + $1.amount }
        totalXP = total
        let current = xpEngine.currentLevel(totalXP: total)
        level = current
        levelTitle = LevelSystem.displayTitle(for: current)
        nextLevelTitle = LevelSystem.displayTitle(for: min(current + 1, LevelSystem.definitions.count))
        xpForNextLevel = xpEngine.xpToNextLevel(totalXP: total)
        streakDays = streak?.currentCount ?? 0

        let currentLevelXP = xpEngine.xpForLevel(current)
        let nextLevelXP = current < LevelSystem.definitions.count
            ? xpEngine.xpForLevel(current + 1)
            : currentLevelXP + 10000
        xpProgress = min(max(Double(total - currentLevelXP) / Double(max(1, nextLevelXP - currentLevelXP)), 0), 1)

        // Today, by source.
        let grouped = Dictionary(grouping: todayEvents, by: \.sourceRaw)
        xpBreakdown = XPSource.allCases.compactMap { source in
            guard let rows = grouped[source.rawValue], !rows.isEmpty else {
                return nil
            }
            let amount = rows.reduce(0) { $0 + $1.amount }
            return amount == 0 ? nil : XPBreakdownRow(source: source, xp: amount, count: rows.count)
        }

        // Achievements the app can really measure.
        let tracked = achievements.filter { ArenaAchievementTracker.isTracked($0.badgeID) }
        totalTracked = tracked.count
        totalEarned = tracked.count(where: \.isEarned)
        recentAchievements = tracked
            .filter(\.isEarned)
            .sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
            .prefix(3)
            .map(\.self)

        // Daily goal.
        if let settings {
            dailyXPGoal = settings.dailyXPGoal.rawValue
        }
        dailyXPProgress = dailyXPGoal > 0 ? min(Double(todayXP) / Double(dailyXPGoal), 1.0) : 0

        if let streak {
            freezesAvailable = max(0, streak.freezesAvailable - streak.freezesUsed)
        }

        // Weeks, Monday to Sunday.
        let thisWeek = ArenaCalendar.weekStart(containing: now, calendar: calendar)
        let lastWeek = ArenaCalendar.previousWeekStart(before: now, calendar: calendar)
        let thisStats = ArenaWeekStats(summary: summary, weekStart: thisWeek, calendar: calendar)
        let lastStats = ArenaWeekStats(summary: summary, weekStart: lastWeek, calendar: calendar)
        weekXP = thisStats.xp
        weekWorkouts = thisStats.workouts
        weekStudyMinutes = thisStats.studyMinutes
        lastWeekXP = lastStats.xp
        lastWeekWorkouts = lastStats.workouts
        lastWeekStudyMinutes = lastStats.studyMinutes
        lastWeekAchievements = tracked.count {
            guard let earned = $0.earnedAt else {
                return false
            }
            return earned >= lastWeek && earned < thisWeek
        }

        // What earned XP lately, a day at a time.
        recentDays = Self.days(from: events, calendar: calendar)

        // The "+N XP" overlay only for XP earned while looking, never for a first load.
        let isInitialLoad = if case .loading = loadState {
            true
        } else {
            false
        }
        if newTodayXP > previousTodayXP, !isInitialLoad {
            lastXPGainAmount = newTodayXP - previousTodayXP
            showXPGain = true
        }
        loadState = .loaded
    }

    /// The latest days with XP in them, newest first, each with its rows.
    static func days(from events: [XPEvent], limit: Int = 14, calendar: Calendar) -> [ArenaXPDay] {
        let byDay = Dictionary(grouping: events.filter { $0.amount != 0 }) { ArenaCalendar.dayKey($0.date, calendar: calendar) }
        return byDay.keys.sorted(by: >).prefix(limit).compactMap { key in
            guard let date = ArenaCalendar.date(forKey: key, calendar: calendar), let rows = byDay[key] else {
                return nil
            }
            let items = rows
                .sorted { $0.amount > $1.amount }
                .map { ArenaXPDay.Item(id: $0.id, source: $0.source, text: $0.eventDescription, xp: $0.amount) }
            return ArenaXPDay(id: key, date: date, items: items)
        }
    }
}

// MARK: - ArenaWeekStats

/// One ISO week (Monday to Sunday) of what the user did, from the same
/// per-day totals that are pushed to friends.
struct ArenaWeekStats: Equatable {
    var xp = 0
    var workouts = 0
    var studyMinutes = 0

    init() {}

    init(summary: ArenaXPLedger.Summary, weekStart: Date, calendar: Calendar = ArenaCalendar.calendar()) {
        let keys = Set((0 ..< 7).map {
            ArenaCalendar.dayKey(ArenaCalendar.addingDays($0, to: weekStart, calendar: calendar), calendar: calendar)
        })
        xp = summary.xp(in: weekStart, calendar: calendar)
        for day in summary.days where keys.contains(day.day) {
            workouts += day.workouts
            studyMinutes += day.studyMinutes
        }
    }
}

// MARK: - ArenaXPDay

/// One day of XP: what earned it.
struct ArenaXPDay: Identifiable, Equatable {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let source: XPSource
        let text: String
        let xp: Int
    }

    let id: String
    let date: Date
    let items: [Item]

    var total: Int {
        items.reduce(0) { $0 + $1.xp }
    }
}

// MARK: - XPBreakdownRow

struct XPBreakdownRow: Identifiable {
    let source: XPSource
    let xp: Int
    let count: Int

    var id: String {
        source.rawValue
    }

    var label: String {
        switch source {
        case .workout: String(localized: "Workout")
        case .study: String(localized: "Study")
        case .meal: String(localized: "Meals")
        case .sleep: String(localized: "Sleep")
        case .steps: String(localized: "Steps")
        case .nonNegotiable: String(localized: "Tasks")
        case .streak: String(localized: "Streak")
        case .challenge: String(localized: "Challenge")
        case .achievement: String(localized: "Achievements")
        case .perfectDay: String(localized: "Perfect day")
        case .penalty: String(localized: "Penalty")
        case .earlyBird: String(localized: "Early bird")
        }
    }
}
