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

    func schedulePrepStartReminder(
        mealID: UUID,
        mealName: String,
        prepStartDate: Date
    ) {
        let notification = ScheduledNotification(
            category: "prepstart_\(mealID.uuidString)",
            title: "Start prepping \(mealName).",
            body: "It's go time.",
            triggerDate: prepStartDate
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled prep-start reminder for \(mealName) at \(prepStartDate)")
    }

    func cancelPrepStartReminder(forMealID mealID: UUID) {
        let category = "prepstart_\(mealID.uuidString)"
        scheduledNotifications.removeAll { $0.category == category }
        logger.debug("Mock: cancelled prep-start reminder for meal \(mealID.uuidString)")
    }

    func scheduleOverdueMealReminder(
        mealID: UUID,
        mealName: String,
        scheduledTime: Date,
        lateMinutes: Int
    ) {
        let fireDate = scheduledTime.addingTimeInterval(Double(lateMinutes) * 60)
        let notification = ScheduledNotification(
            category: "overdue_\(mealID.uuidString)",
            title: "Hey, have you done your \(mealName.lowercased())?",
            body: "It was scheduled \(lateMinutes) min ago. Tap to mark it eaten or skip.",
            triggerDate: fireDate
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled overdue reminder for \(mealName) at \(fireDate)")
    }

    func cancelOverdueMealReminder(forMealID mealID: UUID) {
        let category = "overdue_\(mealID.uuidString)"
        scheduledNotifications.removeAll { $0.category == category }
        logger.debug("Mock: cancelled overdue reminder for meal \(mealID.uuidString)")
    }

    // MARK: - Trainer Session Reminder (fix #12)

    private static let trainerSessionReminderPrefix = "trainer_session_"

    func scheduleTrainerSessionReminder(sessionKey: String, date: Date, title: String, body: String, fireDate: Date) {
        let notification = ScheduledNotification(
            category: "\(Self.trainerSessionReminderPrefix)\(sessionKey)_\(TempoDateFormatters.isoDate.string(from: date))",
            title: title,
            body: body,
            triggerDate: fireDate
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled trainer session reminder '\(title)' at \(fireDate)")
    }

    func cancelTrainerSessionReminders() {
        let before = scheduledNotifications.count
        scheduledNotifications.removeAll { $0.category.hasPrefix(Self.trainerSessionReminderPrefix) }
        let removed = before - scheduledNotifications.count
        if removed > 0 {
            logger.debug("Mock: cancelled \(removed) trainer session reminders")
        }
    }

    // MARK: - Weekly Upload Reminder

    static let weeklyUploadSundayCategory = "weekly_upload_sunday"
    static let weeklyUploadMondayCategory = "weekly_upload_monday"

    func scheduleWeeklyUploadSundayReminder(programName: String, fireDate: Date) {
        let notification = ScheduledNotification(
            category: Self.weeklyUploadSundayCategory,
            title: "New week from your trainer",
            body: "Upload it so Monday's ready.",
            triggerDate: fireDate
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled weekly upload Sunday reminder for \(programName) at \(fireDate)")
    }

    func scheduleWeeklyUploadMondayReminder(programName: String, fireDate: Date) {
        let notification = ScheduledNotification(
            category: Self.weeklyUploadMondayCategory,
            title: "Still no new program from your trainer",
            body: "\(programName) is running on last week's plan. Get the new one in.",
            triggerDate: fireDate
        )
        scheduledNotifications.append(notification)
        logger.debug("Mock: scheduled weekly upload Monday reminder for \(programName) at \(fireDate)")
    }

    func cancelWeeklyUploadReminders() {
        scheduledNotifications.removeAll {
            $0.category == Self.weeklyUploadSundayCategory || $0.category == Self.weeklyUploadMondayCategory
        }
        logger.debug("Mock: cancelled weekly upload reminders")
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
