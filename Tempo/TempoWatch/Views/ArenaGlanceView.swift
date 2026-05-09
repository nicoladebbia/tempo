//
// ArenaGlanceView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Arena Glance View

// Per APPLE_WATCH_APP.md — XP + leaderboard position on Watch.

struct ArenaGlanceView: View {
    let connectivity: WatchConnectivityService

    var body: some View {
        let data = connectivity.latestSnapshot
        VStack(spacing: 12) {
            Text("ARENA")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            // XP display
            VStack(spacing: 4) {
                Text("\(data.xp)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.orange)
                Text("XP")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            // Leaderboard position
            if let position = data.leaderboardPosition {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    Text("#\(position)")
                        .font(.system(size: 20, weight: .bold))
                }
            }

            // Streak
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("\(data.currentStreak) day streak")
                    .font(.system(size: 14, weight: .medium))
            }
        }
    }
}
