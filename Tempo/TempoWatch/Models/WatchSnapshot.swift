//
// WatchSnapshot.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import Foundation

// MARK: - WatchNonNegotiableItem

/// One real non-negotiable, by id/title — replaces the old "Task N" stub.
struct WatchNonNegotiableItem: Codable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
}

// MARK: - WatchNextMeal

/// The next real planned meal — replaces the untargeted "Log Meal" button.
struct WatchNextMeal: Codable, Equatable {
    let id: String
    let name: String
}

// MARK: - WatchSnapshot

// Per APPLE_WATCH_APP.md Section 1.3 — Lightweight daily data from iPhone.
// Per XCODE_PROJECT_STRUCTURE.md Section 11.6 — Watch receives lightweight snapshot, no SwiftData.

struct WatchSnapshot: Codable, Equatable {
    let dailyScore: Int
    let recoveryZone: String
    let recoveryScore: Int
    let sleepHours: Double
    let hrv: Double
    let rhr: Int
    let nextTaskName: String
    let nextTaskTimeRemaining: String
    let nonNegotiables: [WatchNonNegotiableItem]
    let nnCompleted: Int
    let nnTotal: Int
    let leisureUnlocked: Bool
    let currentStreak: Int
    let xp: Int
    let leaderboardPosition: Int?
    let nextMeal: WatchNextMeal?
    /// False until the phone has pushed at least one real snapshot this
    /// install. The watch uses this — not zero-checking individual fields —
    /// to decide whether to show real data or the honest "Open Tempo on
    /// iPhone" empty state, so a genuine 0% recovery day never gets mistaken
    /// for "no data yet".
    let hasRealData: Bool
    let updatedAt: Date

    /// Honest default: no fake achievement numbers. Used before the phone
    /// has ever synced (fresh install) and restored from disk otherwise —
    /// see `WatchConnectivityService`.
    static let empty = WatchSnapshot(
        dailyScore: 0,
        recoveryZone: "unknown",
        recoveryScore: 0,
        sleepHours: 0,
        hrv: 0,
        rhr: 0,
        nextTaskName: "",
        nextTaskTimeRemaining: "",
        nonNegotiables: [],
        nnCompleted: 0,
        nnTotal: 0,
        leisureUnlocked: false,
        currentStreak: 0,
        xp: 0,
        leaderboardPosition: nil,
        nextMeal: nil,
        hasRealData: false,
        updatedAt: .distantPast
    )

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> WatchSnapshot? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}
