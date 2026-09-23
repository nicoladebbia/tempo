//
// TempoComplicationProvider.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import SwiftUI
import WidgetKit

// MARK: - TempoComplicationData

// Per APPLE_WATCH_APP.md Section 2 — TimelineProvider for all complication families.

struct TempoComplicationData: Codable {
    let dailyScore: Int
    let recoveryZone: String
    let recoveryScore: Int
    let nextTaskName: String
    let nextTaskTimeRemaining: String
    let nnProgress: String
    let leisureUnlocked: Bool
    let currentStreak: Int
    let xp: Int
    let leaderboardPosition: Int?

    /// §22 — PREVIEW-ONLY fake numbers for the widget gallery
    /// (`TempoComplicationProvider.placeholder(in:)`), which WidgetKit shows
    /// while the user is choosing a complication — never a real user's
    /// data. `getSnapshot`/`getTimeline` below build `TempoComplicationData`
    /// from `WatchConnectivityService.shared.latestSnapshot` instead, which
    /// is the real last-synced snapshot (or the honest `WatchSnapshot.empty`
    /// zeros before the first real sync) — never this placeholder.
    static let placeholder = TempoComplicationData(
        dailyScore: 78,
        recoveryZone: "green",
        recoveryScore: 82,
        nextTaskName: "Study",
        nextTaskTimeRemaining: "1h23m",
        nnProgress: "3/5",
        leisureUnlocked: false,
        currentStreak: 12,
        xp: 4200,
        leaderboardPosition: 3
    )
}

// MARK: - TempoComplicationEntry

struct TempoComplicationEntry: TimelineEntry {
    let date: Date
    let data: TempoComplicationData
}

// MARK: - TempoComplicationProvider

struct TempoComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> TempoComplicationEntry {
        TempoComplicationEntry(date: .now, data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TempoComplicationEntry) -> Void) {
        let snapshot = WatchConnectivityService.shared.latestSnapshot
        let data = TempoComplicationData(
            dailyScore: snapshot.dailyScore,
            recoveryZone: snapshot.recoveryZone,
            recoveryScore: snapshot.recoveryScore,
            nextTaskName: snapshot.nextTaskName,
            nextTaskTimeRemaining: snapshot.nextTaskTimeRemaining,
            nnProgress: "\(snapshot.nnCompleted)/\(snapshot.nnTotal)",
            leisureUnlocked: snapshot.leisureUnlocked,
            currentStreak: snapshot.currentStreak,
            xp: snapshot.xp,
            leaderboardPosition: snapshot.leaderboardPosition
        )
        completion(TempoComplicationEntry(date: .now, data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TempoComplicationEntry>) -> Void) {
        let snapshot = WatchConnectivityService.shared.latestSnapshot
        let data = TempoComplicationData(
            dailyScore: snapshot.dailyScore,
            recoveryZone: snapshot.recoveryZone,
            recoveryScore: snapshot.recoveryScore,
            nextTaskName: snapshot.nextTaskName,
            nextTaskTimeRemaining: snapshot.nextTaskTimeRemaining,
            nnProgress: "\(snapshot.nnCompleted)/\(snapshot.nnTotal)",
            leisureUnlocked: snapshot.leisureUnlocked,
            currentStreak: snapshot.currentStreak,
            xp: snapshot.xp,
            leaderboardPosition: snapshot.leaderboardPosition
        )

        let now = Date()
        var entries: [TempoComplicationEntry] = []
        for minuteOffset in stride(from: 0, through: 60, by: 15) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now) ?? now
            entries.append(TempoComplicationEntry(date: entryDate, data: data))
        }

        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        let timeline = Timeline(entries: entries, policy: .after(nextRefresh))
        completion(timeline)
    }
}
