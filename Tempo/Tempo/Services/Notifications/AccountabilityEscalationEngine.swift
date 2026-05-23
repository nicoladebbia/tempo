//
// AccountabilityEscalationEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import os
import UserNotifications

// MARK: - Accountability Escalation Engine

// Per BUILD_PLAN step 12.3 — 4-tier escalation system.
// Per STATE_MACHINES.md Section 11 — Push Notification Escalation.
// Per ONBOARDING_AND_NOTIFICATIONS.md — Channels 2-6.

@Observable
final class AccountabilityEscalationEngine: @unchecked Sendable {
    // MARK: - State

    // Per STATE_MACHINES.md Section 11 — Swift Enum.

    enum EscalationState: Codable, Equatable {
        case quiet
        case gentle(briefingSentAt: Date)
        case firm(lastNotificationAt: Date)
        case urgent(lastNotificationAt: Date, notificationCount: Int)
        case critical(lastNotificationAt: Date)
        case resolved(reason: ResolutionReason)

        enum ResolutionReason: String, Codable {
            case allTasksComplete
            case dayEnded
            case overrideActivated
        }
    }

    // MARK: - Properties

    private(set) var state: EscalationState = .quiet
    private let notificationService: NotificationService
    private let logger = Logger(subsystem: "app.tempo", category: "Escalation")

    // Per STATE_MACHINES.md Section 11 — Persistence via UserDefaults.
    private let stateKey = "notification_escalation_state"
    private let dateKey = "notification_escalation_date"

    init(notificationService: NotificationService) {
        self.notificationService = notificationService
        loadState()
    }

    // MARK: - Escalation Scheduling

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Timing relative to evening start.
    // Gentle: E - 5.5h, Firm: E - 2.5h, Urgent: E - 1h, Final: E - 30min.

    /// Schedule all escalation tiers for today based on current progress.
    /// Called at app launch and on non-negotiable status changes.
    func scheduleEscalations(
        eveningStartTime: Date,
        completedCount: Int,
        totalCount: Int,
        userName: String,
        studyDone: String,
        studyTarget: String,
        tasksRemaining: Int,
        notificationIntensity: Int = 3
    ) {
        guard totalCount > 0 else {
            return
        }
        let intensity = CopyIntensity(notificationIntensity: notificationIntensity)

        let completionPercent = Double(completedCount) / Double(totalCount)
        let now = Date()

        // If already resolved today, don't re-schedule
        if case .resolved = state {
            return
        }

        var escalations: [(tier: EscalationTier, time: Date, content: String)] = []

        // Build a context once; each tier reuses it with intensity-aware copy
        // selection from the recency-aware pool (per spec D7).
        let baseContext = CopyContext(
            remaining: tasksRemaining,
            done: completedCount,
            total: totalCount,
            studyDone: studyDone,
            studyTarget: studyTarget,
            timeRemaining: timeString(from: now, to: eveningStartTime),
            streakDays: 0
        )

        // Tier 1: Gentle — E - 5.5h
        let gentleTime = eveningStartTime.addingTimeInterval(-5.5 * 3600)
        if gentleTime > now, completionPercent < 0.5 {
            let content = AccountabilityCopyPool.shared.pick(
                tier: .gentle, intensity: intensity, context: baseContext
            )
            escalations.append((.gentle, gentleTime, content))
        }

        // Tier 2: Firm — E - 2.5h
        let firmTime = eveningStartTime.addingTimeInterval(-2.5 * 3600)
        if firmTime > now, completionPercent < 0.75 {
            let content = AccountabilityCopyPool.shared.pick(
                tier: .firm, intensity: intensity, context: baseContext
            )
            escalations.append((.firm, firmTime, content))
        }

        // Tier 3: Urgent — E - 1h
        let urgentTime = eveningStartTime.addingTimeInterval(-1 * 3600)
        if urgentTime > now, completionPercent < 1.0 {
            let content = AccountabilityCopyPool.shared.pick(
                tier: .urgent, intensity: intensity, context: baseContext
            )
            escalations.append((.urgent, urgentTime, content))
        }

        // Tier 4: Critical — E - 30min
        let criticalTime = eveningStartTime.addingTimeInterval(-30 * 60)
        if criticalTime > now, completionPercent < 1.0 {
            let content = AccountabilityCopyPool.shared.pick(
                tier: .critical, intensity: intensity, context: baseContext
            )
            escalations.append((.critical, criticalTime, content))
        }

        // Schedule via NotificationService
        for escalation in escalations {
            notificationService.scheduleAccountabilityEscalation(
                tier: escalation.tier,
                time: escalation.time,
                content: escalation.content
            )
        }

        // Update state
        if state == .quiet, !escalations.isEmpty {
            state = .gentle(briefingSentAt: Date())
            saveState()
        }

        logger.info("Scheduled \(escalations.count) escalation tiers (completion: \(Int(completionPercent * 100))%)")
    }

    // MARK: - Streak At-Risk

    /// Fire a streak-at-risk warning ahead of the evening cutoff when the user
    /// still has incomplete non-negotiables and a streak worth defending.
    /// Canonical replacement for the deleted
    /// `AccountabilityViewModel.scheduleSmartNotifications` streak branch.
    func scheduleStreakWarningIfAtRisk(
        eveningStartTime: Date,
        streakDays: Int,
        tasksRemaining: Int
    ) {
        guard streakDays > 3, tasksRemaining > 0 else {
            return
        }
        if case .resolved = state {
            return
        }
        let warningTime = eveningStartTime.addingTimeInterval(-45 * 60)
        guard warningTime > Date().addingTimeInterval(60) else {
            return
        }
        notificationService.scheduleStreakWarning(
            streakDays: streakDays,
            tasksRemaining: tasksRemaining,
            time: warningTime
        )
        logger.info("Scheduled streak-at-risk warning (\(streakDays)d streak, \(tasksRemaining) left)")
    }

    // MARK: - All Tasks Complete

    // Per STATE_MACHINES.md Section 11 — Any non-resolved → resolved.
    // Cancels all pending escalation notifications, fires All Clear.

    func allTasksCompleted(
        userName: String,
        totalTasks: Int,
        streakDays: Int,
        recoveryScore: Double?,
        notificationIntensity: Int = 3
    ) {
        // Cancel all pending accountability notifications
        notificationService.cancelCategory("ACCOUNTABILITY_GENTLE")
        notificationService.cancelCategory("ACCOUNTABILITY_FIRM")
        notificationService.cancelCategory("ACCOUNTABILITY_URGENT")
        notificationService.cancelCategory("ACCOUNTABILITY_FINAL")

        // Fire All Clear immediately
        let intensity = CopyIntensity(notificationIntensity: notificationIntensity)
        let context = CopyContext(
            remaining: 0,
            done: totalTasks,
            total: totalTasks,
            streakDays: streakDays
        )
        let content = AccountabilityCopyPool.shared.pick(
            tier: .allClear, intensity: intensity, context: context
        )
        _ = recoveryScore // reserved for future copy variants
        _ = userName
        fireImmediateNotification(
            id: "all_clear_\(todayKey())",
            title: "ALL CLEAR",
            body: content,
            categoryID: "ACCOUNTABILITY_CLEAR"
        )

        // Clear badge
        notificationService.updateBadgeCount(0)

        // Transition to resolved
        state = .resolved(reason: .allTasksComplete)
        saveState()

        logger.info("All tasks complete — fired All Clear, cancelled escalations")
    }

    // MARK: - Override / Rest Day

    func activateOverride() {
        notificationService.cancelCategory("ACCOUNTABILITY_GENTLE")
        notificationService.cancelCategory("ACCOUNTABILITY_FIRM")
        notificationService.cancelCategory("ACCOUNTABILITY_URGENT")
        notificationService.cancelCategory("ACCOUNTABILITY_FINAL")
        notificationService.updateBadgeCount(0)

        state = .resolved(reason: .overrideActivated)
        saveState()

        logger.info("Override activated — cancelled all escalation notifications")
    }

    // MARK: - New Day Reset

    // Per STATE_MACHINES.md Section 11 — resolved → quiet at 00:00.

    func resetForNewDay() {
        state = .quiet
        saveState()
        logger.info("Escalation state reset for new day")
    }

    // MARK: - Persistence

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
        UserDefaults.standard.set(todayKey(), forKey: dateKey)
    }

    private func loadState() {
        let savedDate = UserDefaults.standard.string(forKey: dateKey)
        if savedDate != todayKey() {
            // New day — reset to quiet
            state = .quiet
            return
        }
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(EscalationState.self, from: data)
        {
            state = decoded
        }
    }

    // MARK: - Copy Generators

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Channel 2-6 copy variations.
    // Using Drill Sergeant intensity as default (most common for target users).

    private func gentleCopy(name: String, tasksRemaining: Int, totalCount: Int, completedCount: Int) -> String {
        "\(tasksRemaining) tasks left today. \(completedCount)/\(totalCount) done so far. You've got time — pick one and start."
    }

    private func firmCopy(tasksRemaining: Int, studyDone: String, studyTarget: String, timeUntilEvening: String) -> String {
        "\(tasksRemaining) tasks incomplete. Study: \(studyDone)/\(studyTarget). \(timeUntilEvening) remaining. Time is running."
    }

    private func urgentCopy(studyDone: String, studyTarget: String, timeUntilEvening: String) -> String {
        "Study: \(studyDone)/\(studyTarget). \(timeUntilEvening) before evening. DO IT NOW."
    }

    private func criticalCopy(tasksRemaining: Int) -> String {
        "You're about to waste another evening. \(tasksRemaining) tasks undone. This is your last chance today."
    }

    private func allClearCopy(name: String, totalTasks: Int, streakDays: Int, recoveryScore: Double?) -> String {
        if streakDays > 0 {
            return "ALL CLEAR. \(totalTasks)/\(totalTasks) complete. Day \(streakDays) of your streak. You earned your evening."
        }
        return "ALL CLEAR. Every non-negotiable done. You earned your evening. Whatever you do next, you do it knowing you handled your business first."
    }

    // MARK: - Helpers

    private func fireImmediateNotification(id: String, title: String, body: String, categoryID: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryID
        content.sound = UNNotificationSound(named: UNNotificationSoundName("tempo_clear.caf"))

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // nil = fire immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to fire immediate notification: \(error.localizedDescription)")
            }
        }
    }

    private func timeString(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        }
        return "\(minutes) min"
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
