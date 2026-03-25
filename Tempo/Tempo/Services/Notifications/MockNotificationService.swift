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

    func cancelAll() {
        scheduledNotifications.removeAll()
        logger.debug("Mock: cancelled all notifications")
    }

    func cancelCategory(_ category: String) {
        scheduledNotifications.removeAll { $0.category == category }
        logger.debug("Mock: cancelled category '\(category)'")
    }
}
