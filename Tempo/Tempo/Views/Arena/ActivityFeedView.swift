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
                ForEach(dayGroups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: Tide.s3) {
                        TideSectionLabel(title: dayTitle(group.day))
                        VStack(spacing: 0) {
                            ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                if index > 0 {
                                    TideDivider()
                                }
                                activityRow(event)
                            }
                        }
                        .tideCard(padding: Tide.s2)
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Days

    /// The latest 50 events, newest first, grouped by calendar day.
    private var dayGroups: [(day: Date, events: [ActivityEvent])] {
        let calendar = Calendar.current
        var groups: [(day: Date, events: [ActivityEvent])] = []
        for event in activityEvents.prefix(50) {
            let day = calendar.startOfDay(for: event.timestamp)
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].events.append(event)
            } else {
                groups.append((day: day, events: [event]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
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
