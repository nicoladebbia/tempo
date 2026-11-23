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
        TideScrollPage {
            if activityEvents.isEmpty {
                TideEmptyPanel(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No activity yet",
                    message: "Finish workouts, study sessions and daily tasks to see them here."
                )
                .tideCard()
            } else {
                let events = Array(activityEvents.prefix(50))
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            TideDivider()
                        }
                        activityRow(event)
                    }
                }
                .tideCard(padding: Tide.s2)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Activity Row

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideAreaIconTile(systemName: event.iconName, tint: iconColor(for: event.eventType))

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(event.title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)

                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }

                Text(event.timeAgo)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }

            Spacer(minLength: Tide.s2)

            if event.xpAwarded > 0 {
                TideNumber(
                    "+\(event.xpAwarded)", unit: "XP", size: Tide.numeralS, relativeTo: .headline,
                    weight: .semibold
                )
            }
        }
        .padding(.horizontal, Tide.s3)
        .padding(.vertical, Tide.s3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func iconColor(for type: ActivityEventType) -> Color {
        switch type {
        case .workoutCompleted: TideTone.mint
        case .studyCompleted: Tide.water
        case .streakMilestone: Tide.streak
        case .achievementUnlocked: TideTone.violet
        case .levelUp: TideTone.sky
        case .perfectDay: TideTone.amber
        case .challengeJoined: TideTone.indigo
        case .challengeWon: TideTone.gold
        case .generic: Tide.text2
        }
    }
}
