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
    case error(String)
}

// MARK: - ArenaViewModel

// Per MODULE_ARENA.md Sections 5-12 and BUILD_PLAN.md Step 14.3.
// Enhanced with level names, XP earning categories, and weekly recap.

@Observable
@MainActor
final class ArenaViewModel {
    // MARK: - State

    var loadState: ArenaLoadState = .loading

    // XP / Level
    var todayXP: Int = 0
    var totalXP: Int = 0
    var level: Int = 1
    var levelTitle: String = "Recruit"
    var xpProgress: Double = 0
    var xpForNextLevel: Int = 100
    var streakDays: Int = 0
    var streakMultiplier: Double = 1.0

    // XP gain animation
    var showXPGain: Bool = false
    var lastXPGainAmount: Int = 0

    // Daily XP goal
    var dailyXPGoal: Int = 100
    var dailyXPProgress: Double = 0

    /// League
    var currentLeague: League = .bronze

    // Streak freeze
    var freezesAvailable: Int = 0
    var freezesUsed: Int = 0
    var showFreezeSaved: Bool = false

    /// XP Breakdown
    var xpBreakdown: [XPBreakdownRow] = []

    // Leaderboard
    var leaderboardPreview: [LeaderboardEntry] = []
    var myRank: Int = 0
    var gapToFirst: Int = 0

    // Friends
    var friendCount: Int = 0
    var pendingRequestCount: Int = 0

    /// Challenges
    var activeChallenges: [ChallengeLocal] = []

    // Achievements
    var recentAchievements: [Achievement] = []
    var totalEarned: Int = 0

    /// Detail sheet
    var showXPDetail: Bool = false

    // Weekly recap
    var weeklyXPEarned: Int = 0
    var weeklyAchievementsUnlocked: Int = 0
    var weeklyRankChange: Int = 0
    var weeklyPersonalBests: Int = 0

    /// Activity feed
    var recentActivityEvents: [ActivityEvent] = []

    // MARK: - Dependencies

    private let xpEngine: any XPEngineProtocol

    init(xpEngine: any XPEngineProtocol) {
        self.xpEngine = xpEngine
    }

    // MARK: - Load

    func load(
        xpEvents: [XPEvent],
        achievements: [Achievement],
        challenges: [ChallengeLocal],
        userTotalXP: Int,
        userStreakDays: Int,
        settings: UserSettings? = nil,
        streak: Streak? = nil,
        activityEvents: [ActivityEvent] = []
    ) {
        // XP calculations
        let today = Calendar.current.startOfDay(for: Date())
        let todayEvents = xpEvents.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }

        let previousTodayXP = todayXP
        let newTodayXP = todayEvents.reduce(0) { $0 + $1.amount }
        todayXP = newTodayXP
        totalXP = userTotalXP

        // Use new level system
        let currentLevel = xpEngine.currentLevel(totalXP: userTotalXP)
        level = currentLevel
        levelTitle = xpEngine.levelName(for: currentLevel)
        xpForNextLevel = xpEngine.xpToNextLevel(totalXP: userTotalXP)
        streakDays = userStreakDays
        streakMultiplier = 1.0 + min(0.50, Double(userStreakDays) * 0.02)

        // XP progress bar (using LevelSystem thresholds)
        let currentLevelXP = xpEngine.xpForLevel(currentLevel)
        let nextLevel = currentLevel + 1
        let nextLevelXP = nextLevel <= LevelSystem.definitions.count
            ? xpEngine.xpForLevel(nextLevel)
            : currentLevelXP + 10000
        let range = max(1, nextLevelXP - currentLevelXP)
        xpProgress = Double(userTotalXP - currentLevelXP) / Double(range)

        // XP breakdown by source
        let grouped = Dictionary(grouping: todayEvents, by: { $0.source })
        xpBreakdown = XPSource.allCases.map { source in
            let events = grouped[source] ?? []
            let total = events.reduce(0) { $0 + $1.amount }
            return XPBreakdownRow(source: source, xp: total, count: events.count)
        }.filter { $0.xp != 0 }

        // Challenges
        activeChallenges = challenges.filter { $0.isActive && !$0.hasEnded }

        // Achievements
        recentAchievements = achievements
            .filter(\.isEarned)
            .sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
            .prefix(3)
            .map(\.self)
        totalEarned = achievements.count(where: { $0.isEarned })

        // Daily XP goal
        if let settings {
            dailyXPGoal = settings.dailyXPGoal.rawValue
            currentLeague = settings.league
        }
        dailyXPProgress = dailyXPGoal > 0 ? min(Double(todayXP) / Double(dailyXPGoal), 1.0) : 0

        // Streak freeze
        if let streak {
            freezesAvailable = max(0, streak.freezesAvailable - streak.freezesUsed)
            freezesUsed = streak.freezesUsed
        }

        // Weekly recap calculations
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let weekEvents = xpEvents.filter { $0.date >= weekStart }
        weeklyXPEarned = weekEvents.reduce(0) { $0 + $1.amount }
        weeklyAchievementsUnlocked = achievements
            .count(where: { $0.isEarned && ($0.earnedAt ?? .distantPast) >= weekStart })

        // Activity feed
        recentActivityEvents = activityEvents
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(20)
            .map(\.self)

        // XP gain animation -- trigger when todayXP increases
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
}

// MARK: - XPBreakdownRow

struct XPBreakdownRow: Identifiable {
    let id = UUID()
    let source: XPSource
    let xp: Int
    let count: Int

    var emoji: String {
        switch source {
        case .workout: "🏋️"
        case .study: "📖"
        case .meal: "🍴"
        case .sleep: "🌙"
        case .steps: "🦶"
        case .nonNegotiable: "✓"
        case .streak: "🔥"
        case .challenge: "⚔️"
        case .achievement: "🏅"
        case .perfectDay: "⭐"
        case .penalty: "⚠️"
        case .earlyBird: "🌅"
        }
    }

    var label: String {
        switch source {
        case .workout: "Workout"
        case .study: "Study"
        case .meal: "Meals"
        case .sleep: "Sleep"
        case .steps: "Steps"
        case .nonNegotiable: "Tasks"
        case .streak: "Streak"
        case .challenge: "Challenge"
        case .achievement: "Achievement"
        case .perfectDay: "Perfect Day"
        case .penalty: "Penalty"
        case .earlyBird: "Early Bird"
        }
    }
}

// MARK: - LeaderboardEntry

struct LeaderboardEntry: Identifiable {
    let id = UUID()
    let rank: Int
    let username: String
    let displayName: String
    let xp: Int
    let level: Int
    let isMe: Bool
}

// MARK: - Collection Safe Access

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
