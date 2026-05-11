//
// ActivityFeedView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Activity Feed View

// Social activity feed showing recent user actions.
// Inspired by Strava's activity feed pattern.

struct ActivityFeedView: View {
    @Query(sort: \ActivityEvent.timestamp, order: .reverse)
    private var activityEvents: [ActivityEvent]

    var body: some View {
        VStack(spacing: 0) {
            if activityEvents.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(activityEvents.prefix(50), id: \.id) { event in
                            activityRow(event)
                            if event.id != activityEvents.prefix(50).last?.id {
                                Divider()
                                    .background(Color.tempoDivider)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .padding(.bottom, TempoSpacing.xxxl)
                }
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("ACTIVITY")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Activity Row

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor(for: event.eventType).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: event.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor(for: event.eventType))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.tempoTextPrimary)

                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Text(event.timeAgo)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Spacer()

            if event.xpAwarded > 0 {
                Text("+\(event.xpAwarded)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tempoSignal)
            }
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.md)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No activity yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Complete workouts, study sessions, and daily tasks to see your activity here.")
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xxl)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func iconColor(for type: ActivityEventType) -> Color {
        switch type {
        case .workoutCompleted: Color.tempoSuccess
        case .studyCompleted: Color.tempoSignal
        case .streakMilestone: Color.tempoAmber
        case .achievementUnlocked: Color.tempoViolet
        case .levelUp: Color.tempoSignal
        case .perfectDay: Color.tempoAmber
        case .challengeJoined: Color.tempoInfo
        case .challengeWon: Color.tempoAmber
        case .generic: Color.tempoTextSecondary
        }
    }
}
