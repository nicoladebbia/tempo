//
// ActivityEvent.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - ActivityEvent

// Social activity feed model. Stores user actions for display in the Arena feed.
// Inspired by Strava's activity feed pattern.

@Model
final class ActivityEvent {
    @Attribute(.unique)
    var id: UUID

    var timestamp: Date

    var eventTypeRaw: String

    var title: String

    var subtitle: String?

    var xpAwarded: Int

    var iconName: String

    // MARK: - Computed

    @Transient
    var eventType: ActivityEventType {
        get { ActivityEventType(rawValue: eventTypeRaw) ?? .generic }
        set { eventTypeRaw = newValue.rawValue }
    }

    @Transient
    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 {
            return "Just now"
        }
        if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        }
        if interval < 604_800 {
            return "\(Int(interval / 86400))d ago"
        }
        return timestamp.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: ActivityEventType,
        title: String,
        subtitle: String? = nil,
        xpAwarded: Int = 0,
        iconName: String = "star.fill"
    ) {
        self.id = id
        self.timestamp = timestamp
        eventTypeRaw = eventType.rawValue
        self.title = title
        self.subtitle = subtitle
        self.xpAwarded = xpAwarded
        self.iconName = iconName
    }

    // MARK: - Factory Methods

    static func workoutCompleted(name: String, duration: Int, volume: Double) -> ActivityEvent {
        ActivityEvent(
            eventType: .workoutCompleted,
            title: "Completed \(name)",
            subtitle: "\(duration) min, \(String(format: "%.0f", volume)) kg volume",
            xpAwarded: 50,
            iconName: "dumbbell.fill"
        )
    }

    static func streakHit(days: Int) -> ActivityEvent {
        ActivityEvent(
            eventType: .streakMilestone,
            title: "Hit a \(days)-day streak!",
            subtitle: days >= 30 ? "Unstoppable." : "Keep pushing.",
            xpAwarded: 0,
            iconName: "flame.fill"
        )
    }

    static func achievementUnlocked(name: String, xp: Int) -> ActivityEvent {
        ActivityEvent(
            eventType: .achievementUnlocked,
            title: "Unlocked '\(name)'",
            subtitle: "+\(xp) XP",
            xpAwarded: xp,
            iconName: "medal.fill"
        )
    }

    static func levelUp(level: Int, name: String) -> ActivityEvent {
        ActivityEvent(
            eventType: .levelUp,
            title: "Reached Level \(level): \(name)",
            subtitle: "New rank achieved!",
            xpAwarded: 0,
            iconName: "arrow.up.circle.fill"
        )
    }

    static func perfectDay() -> ActivityEvent {
        ActivityEvent(
            eventType: .perfectDay,
            title: "Perfect Day!",
            subtitle: "All 5 quadrants green",
            xpAwarded: 150,
            iconName: "star.circle.fill"
        )
    }

    static func studySession(pomodoros: Int, minutes: Int) -> ActivityEvent {
        ActivityEvent(
            eventType: .studyCompleted,
            title: "Study session complete",
            subtitle: "\(pomodoros) pomodoros (\(minutes) min)",
            xpAwarded: pomodoros * 25,
            iconName: "book.fill"
        )
    }

    static func challengeJoined(name: String) -> ActivityEvent {
        ActivityEvent(
            eventType: .challengeJoined,
            title: "Joined '\(name)'",
            subtitle: "Let's go!",
            xpAwarded: 0,
            iconName: "figure.fencing"
        )
    }

    static func challengeWon(name: String) -> ActivityEvent {
        ActivityEvent(
            eventType: .challengeWon,
            title: "Won '\(name)'",
            subtitle: "Champion!",
            xpAwarded: 0,
            iconName: "trophy.fill"
        )
    }
}

// MARK: - ActivityEventType

enum ActivityEventType: String, Codable, CaseIterable {
    case workoutCompleted = "workout_completed"
    case studyCompleted = "study_completed"
    case streakMilestone = "streak_milestone"
    case achievementUnlocked = "achievement_unlocked"
    case levelUp = "level_up"
    case perfectDay = "perfect_day"
    case challengeJoined = "challenge_joined"
    case challengeWon = "challenge_won"
    case generic
}
