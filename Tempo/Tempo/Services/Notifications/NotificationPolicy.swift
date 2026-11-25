//
// NotificationPolicy.swift
// Tempo
//
// What Tempo is allowed to send, in one place. Two rules, both applied where a
// notification is scheduled:
//
//   1. A topic that is switched off is not scheduled. Before this, the switches
//      only cancelled what was already pending, so the next reschedule brought
//      the reminder straight back.
//   2. Inside quiet hours only urgent things get through.
//
// The policy is a plain value. `NotificationPolicyStore` keeps a copy in
// UserDefaults because the schedulers are not on the main actor and cannot read
// SwiftData; the Settings page writes it on every change and the app seeds it at
// launch. With no copy saved yet everything is allowed, which is how the app
// behaved before this existed.
//

import Foundation
import SwiftData

// MARK: - NotificationTopic

/// One switch on the Notifications page. A topic can cover several categories.
enum NotificationTopic: String, CaseIterable, Codable, Sendable {
    case morningBriefing
    case recovery
    case meals
    case bedtime
    case weeklyReport
    case accountability
    case streak
    case training
    case trainerSession
    case weeklyUpload
    case arena

    /// The topic a notification category belongs to. nil for categories that have no switch
    /// here (supplements, Sunday planning, pantry, coach): the policy never turns those off.
    init?(categoryID: String) {
        switch categoryID {
        case "MORNING_BRIEFING": self = .morningBriefing
        case "RECOVERY_REPORT": self = .recovery
        case "MEAL_REMINDER",
             "OVERDUE_MEAL_REMINDER",
             "PREP_START_REMINDER": self = .meals
        case "BEDTIME_REMINDER": self = .bedtime
        case "WEEKLY_SUMMARY": self = .weeklyReport
        case "ACCOUNTABILITY_GENTLE",
             "ACCOUNTABILITY_FIRM",
             "ACCOUNTABILITY_URGENT",
             "ACCOUNTABILITY_FINAL",
             "ACCOUNTABILITY_CLEAR": self = .accountability
        case "STREAK_WARNING": self = .streak
        case "TRAINING_REMINDER": self = .training
        case "ARENA_SOCIAL": self = .arena
        default: return nil
        }
    }

    /// Categories to clear from the pending list when the topic is switched off.
    /// Trainer-session and weekly-upload reminders share `TRAINING_REMINDER`, so they
    /// have their own cancel calls and are not listed here.
    var categoryIDs: [String] {
        switch self {
        case .morningBriefing: ["MORNING_BRIEFING"]
        case .recovery: ["RECOVERY_REPORT"]
        case .meals: ["MEAL_REMINDER", "OVERDUE_MEAL_REMINDER", "PREP_START_REMINDER"]
        case .bedtime: ["BEDTIME_REMINDER"]
        case .weeklyReport: ["WEEKLY_SUMMARY"]
        case .accountability:
            ["ACCOUNTABILITY_GENTLE", "ACCOUNTABILITY_FIRM", "ACCOUNTABILITY_URGENT", "ACCOUNTABILITY_FINAL"]
        case .streak: ["STREAK_WARNING"]
        case .training: ["TRAINING_REMINDER"]
        case .arena: ["ARENA_SOCIAL"]
        case .trainerSession,
             .weeklyUpload: []
        }
    }

    /// Categories that still come through during quiet hours: the escalating accountability
    /// warnings (their Time Sensitive level is the point of them) and the defrost reminder
    /// (food left out is a real-world cost). Everything else waits.
    static let urgentCategoryIDs: Set<String> = [
        "ACCOUNTABILITY_FIRM", "ACCOUNTABILITY_URGENT", "ACCOUNTABILITY_FINAL", "DEFROST_REMINDER",
    ]

    /// Every category Tempo schedules itself, so a sweep of the pending list can tell
    /// ours from the Recovery Coach's.
    static let scheduledCategoryIDs: Set<String> = Set(allCases.flatMap(\.categoryIDs)).union([
        "ACCOUNTABILITY_CLEAR", "DEFROST_REMINDER", "USE_IT_UP", "SUPPLEMENT_REMINDER", "SUPPLEMENT_REORDER",
    ])
}

// MARK: - NotificationLevel

/// The one setting most people need: how much Tempo may say. It is a preset over the
/// topic switches, which stay under "Fine tune". The level is never stored: it is read
/// back from the switches, and is nil ("Custom") when they match no preset.
enum NotificationLevel: String, CaseIterable, Identifiable, Sendable {
    case essential
    case balanced
    case everything

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .essential: String(localized: "Essential")
        case .balanced: String(localized: "Balanced")
        case .everything: String(localized: "Everything")
        }
    }

    var summary: String {
        switch self {
        case .essential: String(localized: "Only what you would be upset to miss: meals, training and streaks.")
        case .balanced: String(localized: "Adds your morning briefing, accountability, recovery and bedtime.")
        case .everything: String(localized: "Every reminder Tempo has, including weekly reports and Arena.")
        }
    }

    /// The topics that are on at this level.
    var topics: Set<NotificationTopic> {
        let essential: Set<NotificationTopic> = [.meals, .training, .trainerSession, .weeklyUpload, .streak]
        switch self {
        case .essential:
            return essential
        case .balanced:
            return essential.union([.morningBriefing, .accountability, .bedtime, .recovery])
        case .everything:
            return Set(NotificationTopic.allCases)
        }
    }

    /// The preset whose topics are exactly `enabled`, or nil.
    static func matching(_ enabled: Set<NotificationTopic>) -> NotificationLevel? {
        allCases.first { $0.topics == enabled }
    }
}

// MARK: - QuietHours

/// A daily window, in minutes from midnight. It may run past midnight (23:00 to 07:00).
/// The start is inside the window and the end is not, so a 07:00 briefing still goes out
/// when quiet hours end at 07:00.
struct QuietHours: Equatable, Codable, Sendable {
    var startMinutes: Int
    var endMinutes: Int

    /// Start and end the same time means no window at all.
    var isEmpty: Bool {
        startMinutes == endMinutes
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard !isEmpty else {
            return false
        }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinutes < endMinutes {
            return minute >= startMinutes && minute < endMinutes
        }
        return minute >= startMinutes || minute < endMinutes
    }

    /// The next moment the window ends, after `date`.
    func nextEnd(after date: Date, calendar: Calendar = .current) -> Date? {
        let parts = DateComponents(hour: endMinutes / 60, minute: endMinutes % 60)
        return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
    }
}

// MARK: - NotificationPolicy

struct NotificationPolicy: Equatable, Codable, Sendable {
    var enabledTopics: Set<NotificationTopic>
    var quietHours: QuietHours?

    /// Everything on, no quiet hours: the app's behaviour before the policy existed.
    static let permissive = NotificationPolicy(enabledTopics: Set(NotificationTopic.allCases), quietHours: nil)

    enum Reason: Equatable, Sendable {
        case topicOff
        case quietHours
    }

    enum Decision: Equatable, Sendable {
        case allow
        case skip(Reason)

        var isAllowed: Bool {
            self == .allow
        }
    }

    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        quietHours?.contains(date, calendar: calendar) ?? false
    }

    /// Whether a notification may be scheduled for `fireDate`.
    /// - Parameters:
    ///   - topic: pass it when the category alone can't say (trainer-session and
    ///     weekly-upload reminders share the training category).
    func decide(
        category: String, topic: NotificationTopic? = nil, fireDate: Date, calendar: Calendar = .current
    ) -> Decision {
        if let topic = topic ?? NotificationTopic(categoryID: category), !enabledTopics.contains(topic) {
            return .skip(.topicOff)
        }
        if isQuiet(at: fireDate, calendar: calendar), !NotificationTopic.urgentCategoryIDs.contains(category) {
            return .skip(.quietHours)
        }
        return .allow
    }

    /// When a notification with no fixed time (it would fire right now) may go out: now, or
    /// the end of quiet hours.
    func deliveryDate(category: String, now: Date, calendar: Calendar = .current) -> Date {
        guard isQuiet(at: now, calendar: calendar), !NotificationTopic.urgentCategoryIDs.contains(category)
        else {
            return now
        }
        return quietHours?.nextEnd(after: now, calendar: calendar) ?? now
    }

    /// The level the topic switches add up to, nil when they match no preset.
    var level: NotificationLevel? {
        NotificationLevel.matching(enabledTopics)
    }

    // MARK: Pending requests

    struct Pending: Equatable, Sendable {
        let identifier: String
        let category: String
        /// nil for requests that repeat or have no calendar time: those are left alone.
        let fireDate: Date?
        /// Set when the category alone can't say (trainer-session and weekly-upload
        /// reminders share the training category).
        var topic: NotificationTopic?
    }

    /// Pending requests that the policy no longer allows. Only categories Tempo schedules
    /// itself are ever listed; anything else in the queue is not ours to remove.
    func identifiersToRemove(_ pending: [Pending], calendar: Calendar = .current) -> [String] {
        pending.compactMap { request in
            guard NotificationTopic.scheduledCategoryIDs.contains(request.category),
                  let fireDate = request.fireDate
            else {
                return nil
            }
            return decide(category: request.category, topic: request.topic, fireDate: fireDate, calendar: calendar).isAllowed
                ? nil : request.identifier
        }
    }
}

// MARK: - From the settings

extension UserSettings {
    /// One topic's switch.
    func isOn(_ topic: NotificationTopic) -> Bool {
        switch topic {
        case .morningBriefing: morningBriefingEnabled
        case .recovery: recoveryEnabled
        case .meals: mealRemindersEnabled
        case .bedtime: bedtimeReminderEnabled
        case .weeklyReport: weeklyReportEnabled
        case .accountability: accountabilityEnabled
        case .streak: streakWarningEnabled
        case .training: trainingReminderEnabled
        case .trainerSession: trainerSessionReminderEnabled
        case .weeklyUpload: weeklyUploadReminderEnabled
        case .arena: arenaNotificationsEnabled
        }
    }

    func set(_ topic: NotificationTopic, on: Bool) {
        switch topic {
        case .morningBriefing: morningBriefingEnabled = on
        case .recovery: recoveryEnabled = on
        case .meals: mealRemindersEnabled = on
        case .bedtime: bedtimeReminderEnabled = on
        case .weeklyReport: weeklyReportEnabled = on
        case .accountability: accountabilityEnabled = on
        case .streak: streakWarningEnabled = on
        case .training: trainingReminderEnabled = on
        case .trainerSession: trainerSessionReminderEnabled = on
        case .weeklyUpload: weeklyUploadReminderEnabled = on
        case .arena: arenaNotificationsEnabled = on
        }
        updatedAt = Date()
    }
}

extension NotificationPolicy {
    init(settings: UserSettings) {
        let quiet = settings.quietHoursEnabled
            ? QuietHours(startMinutes: settings.quietHoursStartMinutes, endMinutes: settings.quietHoursEndMinutes)
            : nil
        self.init(
            enabledTopics: Set(NotificationTopic.allCases.filter { settings.isOn($0) }),
            quietHours: quiet.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - NotificationPolicyStore

/// The saved copy the schedulers read. Safe to call from any thread.
enum NotificationPolicyStore {
    static let key = "tempo.notifications.policy.v1"

    /// Nothing saved, or the saved copy can't be read: everything is allowed.
    static func load(defaults: UserDefaults = .standard) -> NotificationPolicy {
        guard let data = defaults.data(forKey: key),
              let policy = try? JSONDecoder().decode(NotificationPolicy.self, from: data)
        else {
            return .permissive
        }
        return policy
    }

    static func save(_ policy: NotificationPolicy, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(policy) {
            defaults.set(data, forKey: key)
        }
    }

    static var current: NotificationPolicy {
        load()
    }

    /// Copies the settings into the saved policy. Returns it.
    @discardableResult
    static func sync(from settings: UserSettings?, defaults: UserDefaults = .standard) -> NotificationPolicy {
        guard let settings else {
            return load(defaults: defaults)
        }
        let policy = NotificationPolicy(settings: settings)
        save(policy, defaults: defaults)
        return policy
    }

    /// Launch seeding: reads the one `UserSettings` row from the store.
    @MainActor
    static func sync(from container: ModelContainer, defaults: UserDefaults = .standard) {
        let settings = try? container.mainContext.fetch(FetchDescriptor<UserSettings>()).first
        // No row (a fresh or in-memory store): a copy left from another store must not keep gating reminders.
        if let settings {
            sync(from: settings, defaults: defaults)
        } else {
            save(.permissive, defaults: defaults)
        }
    }
}
