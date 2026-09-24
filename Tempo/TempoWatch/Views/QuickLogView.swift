//
// QuickLogView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Quick Log View

// Per APPLE_WATCH_APP.md Section 3.5 — Rapid actions from wrist.
// Tap to check off non-negotiables. No keyboards, no text input.
// §22 — real non-negotiable titles/ids (not "Task N") and the real next
// meal name/id (not an untargeted "Log Meal"), and haptics gated on the
// phone's ack instead of firing optimistically on tap.

struct QuickLogView: View {
    let connectivity: WatchConnectivityService

    var body: some View {
        let data = connectivity.latestSnapshot
        ScrollView {
            if !data.hasRealData {
                WatchEmptyStateView()
            } else {
                VStack(spacing: 8) {
                    Text("QUICK LOG")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)

                    // Non-negotiable items — real titles/ids from the phone.
                    ForEach(data.nonNegotiables, id: \.id) { item in
                        Button {
                            connectivity.sendAction(.markNonNegotiableDone, payload: [
                                "id": item.id,
                            ]) { ack in
                                switch ack {
                                case .confirmed: WatchHapticService.playNonNegotiableComplete()
                                case .queued: WatchHapticService.playQueued()
                                case .failed: WatchHapticService.playError()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                                Text(item.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(item.isCompleted)
                    }

                    // Log meal button — targets the real next planned meal.
                    if let meal = data.nextMeal {
                        Button {
                            connectivity.sendAction(.markMealEaten, payload: [
                                "id": meal.id,
                            ]) { ack in
                                switch ack {
                                case .confirmed: WatchHapticService.playMealLogged()
                                case .queued: WatchHapticService.playQueued()
                                case .failed: WatchHapticService.playError()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(.orange)
                                Text("Log \(meal.name)")
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    if data.nonNegotiables.isEmpty, data.nextMeal == nil {
                        Text("Nothing due right now.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
