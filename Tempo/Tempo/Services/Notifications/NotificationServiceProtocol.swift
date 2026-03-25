import Foundation

// MARK: - Escalation Tier

enum EscalationTier: String, Sendable, CaseIterable {
    case gentle
    case firm
    case urgent
    case critical
}

// MARK: - Briefing Content

struct BriefingContent: Sendable {
    let recoveryScore: Double?
    let workoutType: String?
    let nonNegotiablesCount: Int
    let topPriority: String
}

// MARK: - Scheduled Notification Record (for testing)

struct ScheduledNotification: Sendable {
    let category: String
    let title: String
    let body: String
    let triggerDate: Date
}

// MARK: - Protocol

protocol NotificationServiceProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func scheduleMorningBriefing(for date: Date, content: BriefingContent)
    func scheduleAccountabilityEscalation(tier: EscalationTier, time: Date, content: String)
    func scheduleMealReminder(mealName: String, time: Date)
    func scheduleBedtimeReminder(time: Date)
    func cancelAll()
    func cancelCategory(_ category: String)
}
