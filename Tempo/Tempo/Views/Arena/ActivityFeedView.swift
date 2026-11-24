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

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        Group {
            if activityEvents.isEmpty {
                // Nothing yet: say where it comes from, in a page that is not a bare card.
                ArenaEmptyPage(
                    title: "No activity yet",
                    message: "Finish workouts, study sessions and daily tasks to see them here.",
                    art: { ArenaEmptyArt(systemImage: "bubble.left.and.bubble.right.fill") }
                )
            } else {
                feed
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var feed: some View {
        TideScrollPage {
            ForEach(Array(dayGroups.enumerated()), id: \.element.day) { groupIndex, group in
                VStack(alignment: .leading, spacing: Tide.s3) {
                    TideSectionLabel(title: dayTitle(group.day), trailing: dayXP(group.events))
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
                .arenaReveal(groupIndex)
            }
        }
    }

    /// The XP the day's events earned, shown at the right of the day heading.
    private func dayXP(_ events: [ActivityEvent]) -> String? {
        let total = events.reduce(0) { $0 + $1.xpAwarded }
        return total > 0 ? "+\(total) XP" : nil
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
        let stacked = typeSize.isAccessibilitySize
        let xp = TideNumber(
            "+\(event.xpAwarded)", unit: "XP", size: Tide.numeralS, relativeTo: .headline,
            weight: .semibold
        )

        return HStack(alignment: .top, spacing: Tide.s3) {
            TideAreaIconTile(systemName: event.iconName, tint: iconColor(for: event.eventType))

            VStack(alignment: .leading, spacing: stacked ? Tide.s1 : Tide.hair) {
                Text(event.title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // At large text the XP sits with the time, not squeezed beside the title.
                if stacked, event.xpAwarded > 0 {
                    xp
                }

                Text(event.timeAgo)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }

            if !stacked {
                Spacer(minLength: Tide.s2)

                if event.xpAwarded > 0 {
                    xp
                }
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
