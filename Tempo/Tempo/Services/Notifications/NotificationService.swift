//
// NotificationService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import os
import UserNotifications

// MARK: - Notification Service (Real Implementation)

// Per BUILD_PLAN step 12.2 — Local notification scheduling engine.
// Per TECHNICAL_FEASIBILITY_AUDIT.md Section 3.1 — Priority queue, 64-slot limit.
// Per ONBOARDING_AND_NOTIFICATIONS.md — Categories, actions, budget, anti-spam.

@Observable
final class NotificationService: NotificationServiceProtocol, @unchecked Sendable {
    // MARK: - Constants

    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 3.1 — iOS hard limit.
    private static let maxPendingNotifications = 64
    private static let maxPreScheduleHours: TimeInterval = 48 * 3600

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Notification Smart Logic.
    private static let dailyBudgetCap: Double = 6.0
    private static let minIntervalBetweenNotifications: TimeInterval = 30 * 60 // 30 min

    private let logger = Logger(subsystem: "app.tempo", category: "Notifications")
    private let center = UNUserNotificationCenter.current()

    // MARK: - Budget Tracking

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Hard Daily Notification Budget.

    private var budgetSpentToday: Double = 0.0
    private var budgetDate: String = ""
    private var lastNotificationTime: Date?

    // MARK: - Category Registration

    /// Register all notification categories at app launch.
    /// Per ONBOARDING_AND_NOTIFICATIONS.md — Notification Categories and Actions.
    func registerCategories() {
        let categories: Set<UNNotificationCategory> = [
            // Morning Briefing
            makeCategory(
                id: "MORNING_BRIEFING",
                actions: [
                    UNNotificationAction(identifier: "VIEW_DAY", title: "View Day", options: .foreground),
                    UNNotificationAction(identifier: "START_WORKOUT", title: "Start Workout", options: .foreground),
                ]
            ),
            // Accountability — Gentle
            makeCategory(
                id: "ACCOUNTABILITY_GENTLE",
                actions: [
                    UNNotificationAction(identifier: "START_STUDY", title: "Start Study", options: .foreground),
                    UNNotificationAction(identifier: "VIEW_TASKS", title: "View Tasks", options: .foreground),
                ]
            ),
            // Accountability — Firm
            makeCategory(
                id: "ACCOUNTABILITY_FIRM",
                actions: [
                    UNNotificationAction(identifier: "START_NOW", title: "Start Now", options: .foreground),
                    UNNotificationAction(identifier: "VIEW_TASKS", title: "View Tasks", options: .foreground),
                ]
            ),
            // Accountability — Urgent
            makeCategory(
                id: "ACCOUNTABILITY_URGENT",
                actions: [
                    UNNotificationAction(identifier: "START_STUDY_TIMER", title: "Start Study Timer", options: .foreground),
                    UNNotificationAction(identifier: "IM_ON_IT", title: "I'm On It"),
                ]
            ),
            // Accountability — Final Warning
            makeCategory(
                id: "ACCOUNTABILITY_FINAL",
                actions: [
                    UNNotificationAction(identifier: "START_NOW", title: "Start Now", options: .foreground),
                    UNNotificationAction(identifier: "OVERRIDE", title: "Override", options: [.foreground, .destructive]),
                ]
            ),
            // Accountability — All Clear
            makeCategory(
                id: "ACCOUNTABILITY_CLEAR",
                actions: [
                    UNNotificationAction(identifier: "VIEW_STATS", title: "View Stats", options: .foreground),
                ]
            ),
            // Meal Reminder
            makeCategory(
                id: "MEAL_REMINDER",
                actions: [
                    UNNotificationAction(identifier: "LOG_MEAL", title: "Log Meal", options: .foreground),
                    UNNotificationAction(identifier: "DELAY_30MIN", title: "Delay 30min"),
                ]
            ),
            // Training Reminder
            makeCategory(
                id: "TRAINING_REMINDER",
                actions: [
                    UNNotificationAction(identifier: "VIEW_WORKOUT", title: "View Workout", options: .foreground),
                    UNNotificationAction(identifier: "SKIP_TODAY", title: "Skip Today", options: .destructive),
                ]
            ),
            // Recovery Report
            makeCategory(
                id: "RECOVERY_REPORT",
                actions: [
                    UNNotificationAction(identifier: "VIEW_RECOVERY", title: "View Recovery", options: .foreground),
                    UNNotificationAction(identifier: "VIEW_WORKOUT", title: "View Workout", options: .foreground),
                ]
            ),
            // Bedtime Reminder
            makeCategory(
                id: "BEDTIME_REMINDER",
                actions: [
                    UNNotificationAction(identifier: "WIND_DOWN", title: "Wind Down", options: .foreground),
                ]
            ),
            // Defrost Reminder (Phase C)
            makeCategory(
                id: "DEFROST_REMINDER",
                actions: [
                    UNNotificationAction(identifier: "VIEW_MEAL", title: "View Meal", options: .foreground),
                    UNNotificationAction(identifier: "DONE", title: "Done"),
                ]
            ),
            // Prep-Start Reminder (Phase polish)
            makeCategory(
                id: "PREP_START_REMINDER",
                actions: [
                    UNNotificationAction(identifier: "VIEW_MEAL", title: "View Meal", options: .foreground),
                    UNNotificationAction(identifier: "DELAY_15MIN", title: "Delay 15 min"),
                ]
            ),
            // Arena Social
            makeCategory(
                id: "ARENA_SOCIAL",
                actions: [
                    UNNotificationAction(identifier: "VIEW_ARENA", title: "View Arena", options: .foreground),
                ]
            ),
            // Weekly Summary
            makeCategory(
                id: "WEEKLY_SUMMARY",
                actions: [
                    UNNotificationAction(identifier: "VIEW_REPORT", title: "View Report", options: .foreground),
                ]
            ),
            // Streak Warning
            makeCategory(
                id: "STREAK_WARNING",
                actions: [
                    UNNotificationAction(identifier: "SAVE_STREAK", title: "Save Streak", options: .foreground),
                    UNNotificationAction(identifier: "VIEW_TASKS", title: "View Tasks", options: .foreground),
                ]
            ),
        ]

        center.setNotificationCategories(categories)
        logger.info("Registered \(categories.count) notification categories")
    }

    // MARK: - Protocol Implementation

    func requestAuthorization() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        if granted {
            registerCategories()
        }
        return granted
    }

    func scheduleMorningBriefing(for date: Date, content: BriefingContent) {
        guard isWithinPreScheduleWindow(date) else {
            logger.debug("Morning briefing date \(date) outside 48h window, skipping")
            return
        }

        let body = if let score = content.recoveryScore {
            "Recovery: \(Int(score))%. \(content.nonNegotiablesCount) tasks today. Top priority: \(content.topPriority)."
        } else {
            "\(content.nonNegotiablesCount) tasks today. Top priority: \(content.topPriority)."
        }

        scheduleNotification(
            id: "morning_briefing_\(dateKey(date))",
            title: "TEMPO",
            body: body,
            date: date,
            categoryID: "MORNING_BRIEFING",
            threadID: "tempo.briefing.\(dateKey(date))",
            interruptionLevel: .timeSensitive,
            budgetCost: 1.0,
            priority: 1
        )
    }

    func scheduleAccountabilityEscalation(tier: EscalationTier, time: Date, content: String) {
        guard isWithinPreScheduleWindow(time) else {
            return
        }

        let categoryID: String
        let interruptionLevel: UNNotificationInterruptionLevel
        let budgetCost: Double
        let title: String

        switch tier {
        case .gentle:
            categoryID = "ACCOUNTABILITY_GENTLE"
            interruptionLevel = .active
            budgetCost = 1.0
            title = "Accountability Check"
        case .firm:
            categoryID = "ACCOUNTABILITY_FIRM"
            interruptionLevel = .timeSensitive
            budgetCost = 0.5
            title = "Time Check"
        case .urgent:
            categoryID = "ACCOUNTABILITY_URGENT"
            interruptionLevel = .timeSensitive
            budgetCost = 0.5
            title = "URGENT"
        case .critical:
            categoryID = "ACCOUNTABILITY_FINAL"
            interruptionLevel = .timeSensitive
            budgetCost = 1.0
            title = "FINAL WARNING"
        }

        scheduleNotification(
            id: "accountability_\(tier.rawValue)_\(dateKey(time))",
            title: title,
            body: content,
            date: time,
            categoryID: categoryID,
            threadID: "tempo.accountability.\(dateKey(time))",
            interruptionLevel: interruptionLevel,
            budgetCost: budgetCost,
            priority: 2
        )
    }

    func scheduleMealReminder(mealName: String, time: Date) {
        guard isWithinPreScheduleWindow(time) else {
            return
        }

        scheduleNotification(
            id: "meal_\(mealName.lowercased())_\(dateKey(time))",
            title: "Fuel Up",
            body: "Time for \(mealName). Don't skip it.",
            date: time,
            categoryID: "MEAL_REMINDER",
            threadID: "tempo.meals.\(dateKey(time))",
            interruptionLevel: .active,
            budgetCost: 0.5,
            priority: 5
        )
    }

    // MARK: - Defrost Reminder (Phase C)

    /// Identifier convention for defrost notifications. Stable so cancellations
    /// on meal eat/skip/reschedule can target the exact pending request.
    static func defrostReminderID(mealID: UUID, ingredientID: UUID) -> String {
        "defrost_\(mealID.uuidString)_\(ingredientID.uuidString)"
    }

    func scheduleDefrostReminder(
        mealID: UUID,
        ingredientID: UUID,
        ingredientName: String,
        mealName: String,
        leadTimeHours: Int,
        fireDate: Date
    ) {
        guard isWithinPreScheduleWindow(fireDate) else {
            return
        }
        let leadDescriptor = leadTimeHours == 1 ? "an hour" : "\(leadTimeHours) hours"
        scheduleNotification(
            id: Self.defrostReminderID(mealID: mealID, ingredientID: ingredientID),
            title: "Move \(ingredientName) out of the freezer.",
            body: "\(mealName) is in \(leadDescriptor). Defrost it now or skip the meal — your call.",
            date: fireDate,
            categoryID: "DEFROST_REMINDER",
            threadID: "tempo.defrost.\(mealID.uuidString)",
            interruptionLevel: .timeSensitive,
            budgetCost: 0.5,
            priority: 4,
            // Defrost reminders are discrete, time-critical events tied to food
            // physically spoiling — never skip them due to daily-budget pressure.
            bypassBudget: true
        )
    }

    func cancelDefrostReminders(forMealID mealID: UUID) {
        let prefix = "defrost_\(mealID.uuidString)_"
        center.getPendingNotificationRequests { [weak self] requests in
            let idsToCancel = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            guard !idsToCancel.isEmpty else {
                return
            }
            self?.center.removePendingNotificationRequests(withIdentifiers: idsToCancel)
            self?.logger.info("Cancelled \(idsToCancel.count) defrost reminders for meal \(mealID.uuidString)")
        }
    }

    // MARK: - Prep-Start Reminder

    static func prepStartReminderID(mealID: UUID) -> String {
        "prepstart_\(mealID.uuidString)"
    }

    func schedulePrepStartReminder(
        mealID: UUID,
        mealName: String,
        prepStartDate: Date
    ) {
        guard isWithinPreScheduleWindow(prepStartDate) else {
            return
        }
        scheduleNotification(
            id: Self.prepStartReminderID(mealID: mealID),
            title: "Start prepping \(mealName).",
            body: "It's go time. Knife down the phone first, soldier.",
            date: prepStartDate,
            categoryID: "PREP_START_REMINDER",
            threadID: "tempo.prepstart.\(mealID.uuidString)",
            interruptionLevel: .timeSensitive,
            budgetCost: 0.5,
            priority: 4,
            // Same rationale as defrost — discrete, time-critical, food-physical.
            bypassBudget: true
        )
    }

    func cancelPrepStartReminder(forMealID mealID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.prepStartReminderID(mealID: mealID)]
        )
    }

    // MARK: - Recovery Notification

    // Per BUILD_PLAN step 12.4 — Fires for red/yellow recovery zones.

    func scheduleRecoveryNotification(recoveryScore: Int, time: Date) {
        guard isWithinPreScheduleWindow(time) else {
            return
        }

        let body: String
        if recoveryScore < 34 {
            body = "Your recovery is RED today (\(recoveryScore)%). Consider rest or light mobility. Don't push through this."
        } else if recoveryScore < 67 {
            body = "Yellow recovery (\(recoveryScore)%). Adjust intensity down 20% — not commitment, just volume. Stay smart."
        } else {
            return // Green recovery: no notification needed
        }

        scheduleNotification(
            id: "recovery_\(dateKey(time))",
            title: "TEMPO",
            body: body,
            date: time,
            categoryID: "RECOVERY_REPORT",
            threadID: "tempo.recovery.\(dateKey(time))",
            interruptionLevel: .active,
            budgetCost: 0, // Merged into morning briefing budget
            priority: 7
        )
    }

    // MARK: - Streak Warning

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Channel 13: Streak Warning.
    // Fires at E + 1.5h if streak > 3 days and tasks incomplete.

    func scheduleStreakWarning(streakDays: Int, tasksRemaining: Int, time: Date) {
        guard isWithinPreScheduleWindow(time) else {
            return
        }
        guard streakDays > 3, tasksRemaining > 0 else {
            return
        }

        scheduleNotification(
            id: "streak_warning_\(dateKey(time))",
            title: "STREAK AT RISK",
            body: "Your \(streakDays)-day streak is at risk! Complete \(tasksRemaining) more task\(tasksRemaining == 1 ? "" : "s") to keep it alive.",
            date: time,
            categoryID: "STREAK_WARNING",
            threadID: "tempo.streak.\(dateKey(time))",
            interruptionLevel: .timeSensitive,
            budgetCost: 1.0,
            priority: 3
        )
    }

    // MARK: - Training Reminder

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Channel 8: Training Reminder.

    func scheduleTrainingReminder(workoutType: String, time: Date) {
        guard isWithinPreScheduleWindow(time) else {
            return
        }

        scheduleNotification(
            id: "training_\(dateKey(time))",
            title: "Training Time",
            body: "\(workoutType) day. Your workout is ready. Get after it.",
            date: time,
            categoryID: "TRAINING_REMINDER",
            threadID: "tempo.training.\(dateKey(time))",
            interruptionLevel: .active,
            budgetCost: 1.0,
            priority: 4
        )
    }

    func scheduleBedtimeReminder(time: Date) {
        guard isWithinPreScheduleWindow(time) else {
            return
        }

        scheduleNotification(
            id: "bedtime_\(dateKey(time))",
            title: "Lights Out",
            body: "Hit the rack. Recovery starts now.",
            date: time,
            categoryID: "BEDTIME_REMINDER",
            threadID: "tempo.bedtime.\(dateKey(time))",
            interruptionLevel: .timeSensitive,
            budgetCost: 1.0,
            priority: 6
        )
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        resetDailyBudget()
        logger.info("Cancelled all notifications")
    }

    func cancelCategory(_ category: String) {
        center.getPendingNotificationRequests { [weak self] requests in
            let idsToCancel = requests
                .filter { $0.content.categoryIdentifier == category }
                .map(\.identifier)
            self?.center.removePendingNotificationRequests(withIdentifiers: idsToCancel)
            self?.logger.info("Cancelled \(idsToCancel.count) notifications for category \(category)")
        }
    }

    // MARK: - Anti-Spam: Cancel on App Foreground

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Anti-Spam Rules.
    // Opening the app cancels pending escalation notifications.

    func cancelPendingEscalationsOnForeground() {
        let escalationCategories = [
            "ACCOUNTABILITY_GENTLE",
            "ACCOUNTABILITY_FIRM",
            "ACCOUNTABILITY_URGENT",
            "ACCOUNTABILITY_FINAL",
        ]

        center.getPendingNotificationRequests { [weak self] requests in
            let idsToCancel = requests
                .filter { escalationCategories.contains($0.content.categoryIdentifier) }
                .map(\.identifier)
            if !idsToCancel.isEmpty {
                self?.center.removePendingNotificationRequests(withIdentifiers: idsToCancel)
                self?.logger.info("Cancelled \(idsToCancel.count) pending escalation notifications on foreground")
            }
        }
    }

    // MARK: - Reschedule All

    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 3.1 — Reschedule on app foreground.

    func rescheduleAllForToday(
        briefing: BriefingContent?,
        briefingTime: Date?,
        escalations: [(tier: EscalationTier, time: Date, content: String)],
        meals: [(name: String, time: Date)],
        bedtime: Date?
    ) {
        // Clear all existing local notifications
        center.removeAllPendingNotificationRequests()
        resetDailyBudget()

        // 1. Schedule today's notifications first (highest priority)
        if let briefing, let time = briefingTime, time > Date() {
            scheduleMorningBriefing(for: time, content: briefing)
        }

        for escalation in escalations where escalation.time > Date() {
            scheduleAccountabilityEscalation(
                tier: escalation.tier,
                time: escalation.time,
                content: escalation.content
            )
        }

        for meal in meals where meal.time > Date() {
            scheduleMealReminder(mealName: meal.name, time: meal.time)
        }

        if let bedtime, bedtime > Date() {
            scheduleBedtimeReminder(time: bedtime)
        }

        // 2. Log pending count
        logPendingCount()
    }

    // MARK: - Badge Count

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Badge Count Logic.

    func updateBadgeCount(_ count: Int) {
        Task {
            do {
                try await center.setBadgeCount(count)
            } catch {
                logger.error("Failed to set badge count: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Internal Scheduling

    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        date: Date,
        categoryID: String,
        threadID: String,
        interruptionLevel: UNNotificationInterruptionLevel,
        budgetCost: Double,
        priority: Int,
        bypassBudget: Bool = false
    ) {
        // Budget check — bypassable for time-critical, discrete-event notifications
        // (e.g. defrost reminders) whose suppression would cause real-world harm.
        refreshBudgetDateIfNeeded()
        if !bypassBudget {
            guard canSpendBudget(cost: budgetCost) else {
                logger.info("Budget exhausted (\(self.budgetSpentToday)/\(Self.dailyBudgetCap)), skipping \(id)")
                return
            }
        }

        // Anti-spam: min 30 min between notifications (unless Time Sensitive or All Clear)
        if interruptionLevel != .timeSensitive,
           categoryID != "ACCOUNTABILITY_CLEAR",
           let lastTime = lastNotificationTime,
           date.timeIntervalSince(lastTime) < Self.minIntervalBetweenNotifications
        {
            logger.debug("Anti-spam: too close to last notification, skipping \(id)")
            return
        }

        // 64-slot enforcement
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else {
                return
            }
            if requests.count >= Self.maxPendingNotifications {
                // Evict lowest-priority (furthest future) notification
                if let evictable = requests
                    .sorted(by: { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                            > ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                    })
                    .first
                {
                    center.removePendingNotificationRequests(withIdentifiers: [evictable.identifier])
                    logger.info("Evicted notification \(evictable.identifier) to make room (64 limit)")
                }
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = categoryID
            content.threadIdentifier = threadID
            content.interruptionLevel = interruptionLevel
            content.sound = sound(for: categoryID)

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            center.add(request) { error in
                if let error {
                    self.logger.error("Failed to schedule notification \(id): \(error.localizedDescription)")
                } else {
                    if !bypassBudget {
                        self.spendBudget(cost: budgetCost)
                    }
                    self.lastNotificationTime = date
                    self.logger.debug("Scheduled \(categoryID) at \(date) (budget: \(self.budgetSpentToday)/\(Self.dailyBudgetCap))")
                }
            }
        }
    }

    // MARK: - Budget Management

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Hard Daily Notification Budget.

    private func refreshBudgetDateIfNeeded() {
        let today = dateKey(Date())
        if budgetDate != today {
            budgetDate = today
            budgetSpentToday = 0.0
            logger.debug("Budget reset for new day \(today)")
        }
    }

    private func canSpendBudget(cost: Double) -> Bool {
        budgetSpentToday + cost <= Self.dailyBudgetCap
    }

    private func spendBudget(cost: Double) {
        budgetSpentToday += cost
    }

    private func resetDailyBudget() {
        budgetSpentToday = 0.0
        budgetDate = dateKey(Date())
    }

    // MARK: - Helpers

    private func isWithinPreScheduleWindow(_ date: Date) -> Bool {
        date.timeIntervalSinceNow <= Self.maxPreScheduleHours && date > Date()
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func makeCategory(id: String, actions: [UNNotificationAction]) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: id,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
    }

    /// Per ONBOARDING_AND_NOTIFICATIONS.md — Sound Strategy.
    private func sound(for categoryID: String) -> UNNotificationSound {
        switch categoryID {
        case "ACCOUNTABILITY_URGENT",
             "STREAK_WARNING":
            UNNotificationSound(named: UNNotificationSoundName("tempo_urgent.caf"))
        case "ACCOUNTABILITY_FINAL":
            UNNotificationSound(named: UNNotificationSoundName("tempo_final.caf"))
        case "ACCOUNTABILITY_CLEAR":
            UNNotificationSound(named: UNNotificationSoundName("tempo_clear.caf"))
        case "BEDTIME_REMINDER":
            UNNotificationSound(named: UNNotificationSoundName("tempo_bedtime.caf"))
        default:
            .default
        }
    }

    /// Per TECHNICAL_FEASIBILITY_AUDIT.md Section 3.1 — Log count on every schedule.
    private func logPendingCount() {
        center.getPendingNotificationRequests { [weak self] requests in
            self?.logger.info("Pending notification count: \(requests.count)/\(Self.maxPendingNotifications)")
        }
    }
}
