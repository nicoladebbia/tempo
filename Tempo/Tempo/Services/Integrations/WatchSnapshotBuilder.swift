//
// WatchSnapshotBuilder.swift
// Tempo
//
// Created by Tempo on 9/23/26.
//
//

import Foundation

enum WatchSnapshotBuilder {
    struct Input {
        let dailyScore: Int?
        let recoveryScore: Double?
        let recoveryZone: RecoveryZone?
        let sleepHours: Double?
        let hrv: Double?
        let rhr: Double?
        /// Today's real non-negotiables — same rows the Dashboard and
        /// Lockdown read. Order preserved.
        let nonNegotiables: [WatchNonNegotiableItem]
        let leisureUnlocked: Bool
        /// Seconds until the leisure-unlock (PS5) time — nil once unlocked
        /// or unknown. Never negative (callers clamp).
        let timeToLeisureUnlock: TimeInterval?
        let currentStreak: Int
        /// Sum of today's real XPEvent amounts. There is currently no real
        /// leaderboard data source anywhere in the app (LeaderboardView's
        /// rankings are an explicitly-labeled mock pending backend sync —
        /// see LeaderboardView.loadMockData) — so `leaderboardPosition`
        /// must stay `nil` rather than inventing a rank.
        let totalXP: Int
        let leaderboardPosition: Int?
        let nextMeal: WatchNextMeal?
        let now: Date

        init(
            dailyScore: Int?,
            recoveryScore: Double?,
            recoveryZone: RecoveryZone?,
            sleepHours: Double?,
            hrv: Double?,
            rhr: Double?,
            nonNegotiables: [WatchNonNegotiableItem],
            leisureUnlocked: Bool,
            timeToLeisureUnlock: TimeInterval?,
            currentStreak: Int,
            totalXP: Int,
            leaderboardPosition: Int? = nil,
            nextMeal: WatchNextMeal?,
            now: Date = Date()
        ) {
            self.dailyScore = dailyScore
            self.recoveryScore = recoveryScore
            self.recoveryZone = recoveryZone
            self.sleepHours = sleepHours
            self.hrv = hrv
            self.rhr = rhr
            self.nonNegotiables = nonNegotiables
            self.leisureUnlocked = leisureUnlocked
            self.timeToLeisureUnlock = timeToLeisureUnlock
            self.currentStreak = currentStreak
            self.totalXP = totalXP
            self.leaderboardPosition = leaderboardPosition
            self.nextMeal = nextMeal
            self.now = now
        }
    }

    static func build(from input: Input) -> WatchSnapshot {
        let completed = input.nonNegotiables.count(where: \.isCompleted)
        let total = input.nonNegotiables.count
        let nextTask = input.nonNegotiables.first(where: { !$0.isCompleted })
        let showNextTask = !input.leisureUnlocked && nextTask != nil

        return WatchSnapshot(
            dailyScore: input.dailyScore ?? 0,
            recoveryZone: input.recoveryZone?.rawValue ?? "unknown",
            recoveryScore: Int(input.recoveryScore ?? 0),
            sleepHours: input.sleepHours ?? 0,
            hrv: input.hrv ?? 0,
            rhr: Int(input.rhr ?? 0),
            nextTaskName: showNextTask ? (nextTask?.title ?? "") : "",
            nextTaskTimeRemaining: showNextTask ? formattedRemaining(input.timeToLeisureUnlock) : "",
            nonNegotiables: input.nonNegotiables,
            nnCompleted: completed,
            nnTotal: total,
            leisureUnlocked: input.leisureUnlocked,
            currentStreak: input.currentStreak,
            xp: input.totalXP,
            leaderboardPosition: input.leaderboardPosition,
            nextMeal: input.nextMeal,
            hasRealData: true,
            updatedAt: input.now
        )
    }

    /// "1h23m" / "45m" — matches the format the old placeholder used.
    /// Empty when there's nothing meaningful to show.
    private static func formattedRemaining(_ interval: TimeInterval?) -> String {
        guard let interval, interval > 0 else {
            return ""
        }
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }
}
