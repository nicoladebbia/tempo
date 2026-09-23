//
// GlanceHomeView.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import SwiftUI

// MARK: - Glance Home View

// Per APPLE_WATCH_APP.md Section 3 — Main watch face (daily score, recovery, next task).

struct GlanceHomeView: View {
    let connectivity: WatchConnectivityService

    var body: some View {
        let data = connectivity.latestSnapshot
        ScrollView {
            if !data.hasRealData {
                WatchEmptyStateView()
            } else {
                VStack(spacing: 12) {
                    // Score ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(data.dailyScore) / 100)
                            .stroke(scoreColor(data.dailyScore), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(data.dailyScore)")
                                .font(.system(size: 28, weight: .bold))
                            Text("SCORE")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 80, height: 80)

                    // Recovery zone
                    HStack(spacing: 4) {
                        Circle()
                            .fill(zoneColor(data.recoveryZone))
                            .frame(width: 8, height: 8)
                        Text("\(data.recoveryScore)% Recovery")
                            .font(.system(size: 14, weight: .medium))
                    }

                    // Next task
                    if !data.nextTaskName.isEmpty {
                        VStack(spacing: 2) {
                            Text("NEXT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(data.nextTaskName)
                                .font(.system(size: 15, weight: .semibold))
                            Text(data.nextTaskTimeRemaining)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Non-negotiables progress
                    HStack(spacing: 4) {
                        Text("\(data.nnCompleted)/\(data.nnTotal)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("non-negs")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // Streak
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("\(data.currentStreak)d streak")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 {
            return .green
        }
        if score >= 50 {
            return .orange
        }
        return .red
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "green": .green
        case "yellow": .yellow
        case "red": .red
        case "unknown": .gray
        default: .green
        }
    }
}
