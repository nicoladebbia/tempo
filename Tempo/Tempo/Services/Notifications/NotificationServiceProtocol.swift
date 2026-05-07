//
// NotificationServiceProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - EscalationTier

enum EscalationTier: String, CaseIterable {
    case gentle
    case firm
    case urgent
    case critical
}

// MARK: - BriefingContent

struct BriefingContent {
    let recoveryScore: Double?
    let workoutType: String?
    let nonNegotiablesCount: Int
    let topPriority: String
}

// MARK: - ScheduledNotification

struct ScheduledNotification {
    let category: String
    let title: String
    let body: String
    let triggerDate: Date
}

// MARK: - NotificationServiceProtocol

protocol NotificationServiceProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func scheduleMorningBriefing(for date: Date, content: BriefingContent)
    func scheduleAccountabilityEscalation(tier: EscalationTier, time: Date, content: String)
    func scheduleMealReminder(mealName: String, time: Date)
    func scheduleBedtimeReminder(time: Date)
    func cancelAll()
    func cancelCategory(_ category: String)
}
