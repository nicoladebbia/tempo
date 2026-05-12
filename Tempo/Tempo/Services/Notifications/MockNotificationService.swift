//
// MockNotificationService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import os

@Observable
final class MockNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    private(set) var scheduledNotifications: [ScheduledNotification] = []
    private let logger = Logger(subsystem: "app.tempo", category: "MockNotifications")

    func requestAuthorization() async throws -> Bool {
        logger.debug("Mock: notification authorization granted")
        return true
    }

    func scheduleMorningBriefing(for date: Date, content: BriefingContent) {
        let notification = ScheduledNotification(
            category: "morning_briefing",
            title: "Good morning, soldier.",
            body: "Recovery: \(content.recoveryScore.map { "\(Int($0))%" } ?? "N/A"). Top priority: \(content.topPriority).",
            triggerDate: date
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled morning briefing for \(date)")
    }

    func scheduleAccountabilityEscalation(tier: EscalationTier, time: Date, content: String) {
        let notification = ScheduledNotification(
            category: "accountability_\(tier.rawValue)",
            title: tier == .critical ? "FINAL WARNING" : "Accountability Check",
            body: content,
            triggerDate: time
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled \(tier.rawValue) escalation at \(time)")
    }

    func scheduleMealReminder(mealName: String, time: Date) {
        let notification = ScheduledNotification(
            category: "meal_reminder",
            title: "Fuel Up",
            body: "Time for \(mealName). Don't skip it.",
            triggerDate: time
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled meal reminder '\(mealName)' at \(time)")
    }

    func scheduleBedtimeReminder(time: Date) {
        let notification = ScheduledNotification(
            category: "bedtime",
            title: "Lights Out",
            body: "Hit the rack. Recovery starts now.",
            triggerDate: time
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled bedtime reminder at \(time)")
    }

    func scheduleDefrostReminder(
        mealID: UUID,
        ingredientID: UUID,
        ingredientName: String,
        mealName: String,
        leadTimeHours: Int,
        fireDate: Date
    ) {
        let notification = ScheduledNotification(
            category: "defrost_\(mealID.uuidString)_\(ingredientID.uuidString)",
            title: "Move \(ingredientName) out of the freezer.",
            body: "\(mealName) is in \(leadTimeHours) hours. Defrost it now.",
            triggerDate: fireDate
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled defrost reminder \(ingredientName) for \(mealName) at \(fireDate)")
    }

    func cancelDefrostReminders(forMealID mealID: UUID) {
        let prefix = "defrost_\(mealID.uuidString)_"
        let before = scheduledNotifications.count
        scheduledNotifications.removeAll { $0.category.hasPrefix(prefix) }
        let removed = before - scheduledNotifications.count
        if removed > 0 {
            logger.debug("Mock: cancelled \(removed) defrost reminders for meal \(mealID.uuidString)")
        }
    }

    func cancelAll() {
        scheduledNotifications.removeAll()
        logger.debug("Mock: cancelled all notifications")
    }

    func cancelCategory(_ category: String) {
        scheduledNotifications.removeAll { $0.category == category }
        logger.debug("Mock: cancelled category '\(category)'")
    }
}
