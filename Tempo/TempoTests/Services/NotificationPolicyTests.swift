//
// NotificationPolicyTests.swift
// TempoTests
//
// What Tempo may send: switched-off reminders are not scheduled, quiet hours let
// only urgent ones through, and the Essential / Balanced / Everything level is a
// preset over the switches.
//

import Foundation
@testable import Tempo
import Testing
import UserNotifications

// MARK: - NotificationPolicyTests

struct NotificationPolicyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .now
    }

    /// 23:00 to 07:00, everything else on.
    private var overnight: NotificationPolicy {
        NotificationPolicy(
            enabledTopics: Set(NotificationTopic.allCases),
            quietHours: QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)
        )
    }

    // MARK: - Quiet hours window

    @Test
    func windowThatCrossesMidnightCoversBothSides() {
        let quiet = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)
        #expect(quiet.contains(at(23, 0), calendar: calendar))
        #expect(quiet.contains(at(23, 59), calendar: calendar))
        #expect(quiet.contains(at(0, 0, day: 11), calendar: calendar))
        #expect(quiet.contains(at(6, 59), calendar: calendar))
        #expect(!quiet.contains(at(7, 0), calendar: calendar))
        #expect(!quiet.contains(at(12, 0), calendar: calendar))
        #expect(!quiet.contains(at(22, 59), calendar: calendar))
    }

    @Test
    func windowWithinOneDay() {
        let quiet = QuietHours(startMinutes: 13 * 60, endMinutes: 15 * 60)
        #expect(!quiet.contains(at(12, 59), calendar: calendar))
        #expect(quiet.contains(at(13, 0), calendar: calendar))
        #expect(quiet.contains(at(14, 59), calendar: calendar))
        #expect(!quiet.contains(at(15, 0), calendar: calendar))
    }

    @Test
    func sameStartAndEndIsNoWindow() {
        let quiet = QuietHours(startMinutes: 600, endMinutes: 600)
        #expect(quiet.isEmpty)
        #expect(!quiet.contains(at(10, 0), calendar: calendar))
    }

    @Test
    func nextEndIsTheComingMorning() {
        let quiet = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)
        #expect(quiet.nextEnd(after: at(23, 30), calendar: calendar) == at(7, 0, day: 11))
        #expect(quiet.nextEnd(after: at(3, 0), calendar: calendar) == at(7, 0))
    }

    // MARK: - Decisions

    @Test
    func morningBriefingAtTheEndOfQuietHoursStillGoesOut() {
        #expect(overnight.decide(category: "MORNING_BRIEFING", fireDate: at(7, 0), calendar: calendar) == .allow)
        #expect(overnight.decide(category: "MORNING_BRIEFING", fireDate: at(6, 59), calendar: calendar) == .skip(.quietHours))
    }

    @Test
    func nonUrgentIsSkippedInsideTheWindow() {
        for category in [
            "MEAL_REMINDER",
            "TRAINING_REMINDER",
            "BEDTIME_REMINDER",
            "STREAK_WARNING",
            "ACCOUNTABILITY_GENTLE",
            "ACCOUNTABILITY_CLEAR",
            "SUPPLEMENT_REMINDER",
            "USE_IT_UP",
        ] {
            #expect(
                overnight.decide(category: category, fireDate: at(23, 30), calendar: calendar) == .skip(.quietHours),
                "\(category) should wait"
            )
        }
    }

    @Test
    func urgentGetsThroughInsideTheWindow() {
        for category in ["ACCOUNTABILITY_FIRM", "ACCOUNTABILITY_URGENT", "ACCOUNTABILITY_FINAL", "DEFROST_REMINDER"] {
            #expect(overnight.decide(category: category, fireDate: at(2, 0), calendar: calendar) == .allow, "\(category)")
        }
    }

    @Test
    func switchedOffTopicIsSkippedWhateverTheTime() {
        var policy = NotificationPolicy.permissive
        policy.enabledTopics.remove(.morningBriefing)
        #expect(policy.decide(category: "MORNING_BRIEFING", fireDate: at(12), calendar: calendar) == .skip(.topicOff))
        #expect(policy.decide(category: "MEAL_REMINDER", fireDate: at(12), calendar: calendar) == .allow)
    }

    @Test
    func switchedOffTopicBeatsUrgent() {
        var policy = NotificationPolicy.permissive
        policy.enabledTopics.remove(.accountability)
        for category in [
            "ACCOUNTABILITY_GENTLE",
            "ACCOUNTABILITY_FIRM",
            "ACCOUNTABILITY_URGENT",
            "ACCOUNTABILITY_FINAL",
            "ACCOUNTABILITY_CLEAR",
        ] {
            #expect(policy.decide(category: category, fireDate: at(12), calendar: calendar) == .skip(.topicOff), "\(category)")
        }
    }

    @Test
    func categoriesWithoutASwitchAreNeverTurnedOff() {
        let nothingOn = NotificationPolicy(enabledTopics: [], quietHours: nil)
        for category in [
            "SUPPLEMENT_REMINDER",
            "SUPPLEMENT_REORDER",
            "USE_IT_UP",
            "DEFROST_REMINDER",
            "WEEKLY_PLAN_PROMPT",
            "SOMETHING_NEW",
        ] {
            #expect(nothingOn.decide(category: category, fireDate: at(12), calendar: calendar) == .allow, "\(category)")
        }
    }

    @Test
    func trainerSessionsAndUploadRemindersFollowTheirOwnSwitch() {
        // Both are TRAINING_REMINDER notifications, so the caller names the topic.
        var policy = NotificationPolicy.permissive
        policy.enabledTopics.remove(.trainerSession)
        #expect(policy
            .decide(category: "TRAINING_REMINDER", topic: .trainerSession, fireDate: at(12), calendar: calendar) == .skip(.topicOff))
        #expect(policy.decide(category: "TRAINING_REMINDER", topic: .weeklyUpload, fireDate: at(12), calendar: calendar) == .allow)
        #expect(policy.decide(category: "TRAINING_REMINDER", fireDate: at(12), calendar: calendar) == .allow)
    }

    @Test
    func theDefaultPolicyAllowsEverything() {
        #expect(NotificationPolicy.permissive.level == .everything)
        for topic in NotificationTopic.allCases {
            for category in topic.categoryIDs {
                #expect(NotificationPolicy.permissive.decide(category: category, fireDate: at(3), calendar: calendar) == .allow)
            }
        }
    }

    // MARK: - Held-back alerts

    @Test
    func anAlertWithNoFixedTimeWaitsForTheWindowToEnd() {
        let now = at(23, 30)
        #expect(overnight.deliveryDate(category: "SUPPLEMENT_REORDER", now: now, calendar: calendar) == at(7, 0, day: 11))
        #expect(overnight.deliveryDate(category: "DEFROST_REMINDER", now: now, calendar: calendar) == now)
        #expect(overnight.deliveryDate(category: "SUPPLEMENT_REORDER", now: at(12), calendar: calendar) == at(12))
        #expect(NotificationPolicy.permissive.deliveryDate(category: "SUPPLEMENT_REORDER", now: now) == now)
    }

    // MARK: - Pending requests

    @Test
    func sweepRemovesOnlyWhatThePolicyForbids() {
        var policy = overnight
        policy.enabledTopics.remove(.arena)
        let pending: [NotificationPolicy.Pending] = [
            .init(identifier: "meal-late", category: "MEAL_REMINDER", fireDate: at(23, 30)),
            .init(identifier: "meal-noon", category: "MEAL_REMINDER", fireDate: at(12)),
            .init(identifier: "final-warning", category: "ACCOUNTABILITY_FINAL", fireDate: at(23, 45)),
            .init(identifier: "arena", category: "ARENA_SOCIAL", fireDate: at(12)),
            .init(identifier: "coach", category: "COACH_POST_SESSION", fireDate: at(23, 30)),
            .init(identifier: "sunday-prompt", category: "WEEKLY_PLAN_PROMPT", fireDate: nil),
            .init(identifier: "repeating", category: "MEAL_REMINDER", fireDate: nil),
        ]
        let removed = policy.identifiersToRemove(pending, calendar: calendar)
        #expect(Set(removed) == ["meal-late", "arena"])
    }

    // MARK: - Mapping

    @Test
    func everyTopicCategoryMapsBackToItsTopic() {
        for topic in NotificationTopic.allCases {
            for category in topic.categoryIDs {
                #expect(NotificationTopic(categoryID: category) == topic, "\(category)")
            }
        }
    }

    @Test
    func theSweepKnowsEveryCategoryTheSchedulersUse() {
        let known = NotificationTopic.scheduledCategoryIDs
        for category in [
            "MORNING_BRIEFING",
            "ACCOUNTABILITY_CLEAR",
            "DEFROST_REMINDER",
            "USE_IT_UP",
            "SUPPLEMENT_REORDER",
            "TRAINING_REMINDER",
        ] {
            #expect(known.contains(category), "\(category)")
        }
        #expect(!known.contains(CoachNotifications.postCategoryID))
    }
}

// MARK: - NotificationLevelTests

struct NotificationLevelTests {
    @Test
    func levelsGrowAndEverythingIsEverything() {
        #expect(NotificationLevel.essential.topics.isSubset(of: NotificationLevel.balanced.topics))
        #expect(NotificationLevel.balanced.topics.isSubset(of: NotificationLevel.everything.topics))
        #expect(NotificationLevel.essential.topics != NotificationLevel.balanced.topics)
        #expect(NotificationLevel.balanced.topics != NotificationLevel.everything.topics)
        #expect(NotificationLevel.everything.topics == Set(NotificationTopic.allCases))
    }

    @Test
    func essentialKeepsWhatYouWouldBeUpsetToMiss() {
        let essential = NotificationLevel.essential.topics
        #expect(essential.isSuperset(of: [.meals, .training, .trainerSession, .weeklyUpload, .streak]))
        #expect(essential.isDisjoint(with: [.morningBriefing, .weeklyReport, .arena, .bedtime]))
    }

    @Test
    func eachLevelIsReadBackFromItsSwitches() {
        for level in NotificationLevel.allCases {
            #expect(NotificationLevel.matching(level.topics) == level)
            #expect(NotificationPolicy(enabledTopics: level.topics, quietHours: nil).level == level)
        }
    }

    @Test
    func switchesThatMatchNoPresetAreCustom() {
        var topics = NotificationLevel.balanced.topics
        topics.remove(.recovery)
        #expect(NotificationLevel.matching(topics) == nil)
        #expect(NotificationLevel.matching([]) == nil)
    }

    @Test
    func aLevelIsAppliedByTheSwitchesAndComesBackFromThem() {
        let settings = UserSettings()
        for level in NotificationLevel.allCases {
            for topic in NotificationTopic.allCases {
                settings.set(topic, on: level.topics.contains(topic))
            }
            #expect(NotificationPolicy(settings: settings).level == level, "\(level)")
        }
    }

    @Test
    func everyTopicHasItsOwnSwitchOnTheSettings() {
        for topic in NotificationTopic.allCases {
            let settings = UserSettings()
            settings.set(topic, on: false)
            let off = NotificationPolicy(settings: settings).enabledTopics
            #expect(off == Set(NotificationTopic.allCases).subtracting([topic]), "\(topic)")
            #expect(!settings.isOn(topic))
        }
    }
}

// MARK: - NotificationPolicyStoreTests

struct NotificationPolicyStoreTests {
    private func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "NotificationPolicyStoreTests.\(name)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func freshSettingsAreTodaysBehaviour() {
        let policy = NotificationPolicy(settings: UserSettings())
        #expect(policy == .permissive)
    }

    @Test
    func quietHoursComeFromTheSettings() {
        let settings = UserSettings()
        settings.quietHoursEnabled = true
        settings.quietHoursStartMinutes = 22 * 60
        settings.quietHoursEndMinutes = 6 * 60 + 30
        #expect(NotificationPolicy(settings: settings).quietHours == QuietHours(startMinutes: 1320, endMinutes: 390))

        settings.quietHoursEnabled = false
        #expect(NotificationPolicy(settings: settings).quietHours == nil)

        settings.quietHoursEnabled = true
        settings.quietHoursEndMinutes = settings.quietHoursStartMinutes
        #expect(NotificationPolicy(settings: settings).quietHours == nil, "an empty window is no window")
    }

    @Test
    func nothingSavedMeansNothingBlocked() {
        #expect(NotificationPolicyStore.load(defaults: defaults()) == .permissive)
    }

    @Test
    func theSavedCopyRoundTrips() {
        let store = defaults()
        let policy = NotificationPolicy(
            enabledTopics: NotificationLevel.essential.topics,
            quietHours: QuietHours(startMinutes: 1380, endMinutes: 420)
        )
        NotificationPolicyStore.save(policy, defaults: store)
        #expect(NotificationPolicyStore.load(defaults: store) == policy)
    }

    @Test
    func anUnreadableCopyFallsBackToAllowEverything() {
        let store = defaults()
        store.set(Data("not json".utf8), forKey: NotificationPolicyStore.key)
        #expect(NotificationPolicyStore.load(defaults: store) == .permissive)
    }

    @Test
    func syncCopiesTheSettings() {
        let store = defaults()
        let settings = UserSettings()
        settings.set(.arena, on: false)
        settings.quietHoursEnabled = true
        let synced = NotificationPolicyStore.sync(from: settings, defaults: store)
        #expect(NotificationPolicyStore.load(defaults: store) == synced)
        #expect(!synced.enabledTopics.contains(.arena))
        #expect(synced.quietHours != nil)
    }

    @Test
    func syncWithoutSettingsKeepsWhatWasSaved() {
        let store = defaults()
        let saved = NotificationPolicy(enabledTopics: [.meals], quietHours: nil)
        NotificationPolicyStore.save(saved, defaults: store)
        #expect(NotificationPolicyStore.sync(from: nil, defaults: store) == saved)
    }
}

// MARK: - NotificationServiceGateTests

struct NotificationServiceGateTests {
    private func pendingIDs() async -> Set<String> {
        await Set(UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
    }

    /// Waits for iOS to list a request (adding is asynchronous).
    private func waitFor(_ id: String, present: Bool) async -> Bool {
        for _ in 0 ..< 40 {
            if await pendingIDs().contains(id) == present {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test
    func aSwitchedOffReminderIsNotScheduledAndAnAllowedOneIs() async {
        let center = UNUserNotificationCenter.current()
        let fire = Date().addingTimeInterval(6 * 3600)
        let blockedMeal = UUID()
        let allowedMeal = UUID()
        let blockedID = NotificationService.mealReminderID(mealID: blockedMeal)
        let allowedID = NotificationService.mealReminderID(mealID: allowedMeal)
        defer { center.removePendingNotificationRequests(withIdentifiers: [blockedID, allowedID]) }

        var draft = NotificationPolicy.permissive
        draft.enabledTopics.remove(.meals)
        let blocked = draft
        NotificationService(policy: { blocked })
            .scheduleMealReminder(mealID: blockedMeal, mealName: "Gate test", fireDate: fire)
        NotificationService(policy: { .permissive })
            .scheduleMealReminder(mealID: allowedMeal, mealName: "Gate test", fireDate: fire)

        #expect(await waitFor(allowedID, present: true), "an allowed reminder is scheduled")
        #expect(await !(pendingIDs().contains(blockedID)), "a switched-off reminder never reaches iOS")
    }

    @Test
    func aReminderInsideQuietHoursIsNotScheduled() async {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        // A window that holds the fire time, whatever the clock says.
        let fire = Date().addingTimeInterval(6 * 3600)
        let minute = calendar.component(.hour, from: fire) * 60 + calendar.component(.minute, from: fire)
        let quiet = QuietHours(startMinutes: (minute + 1440 - 30) % 1440, endMinutes: (minute + 30) % 1440)
        let meal = UUID()
        let id = NotificationService.mealReminderID(mealID: meal)
        defer { center.removePendingNotificationRequests(withIdentifiers: [id]) }

        let policy = NotificationPolicy(enabledTopics: Set(NotificationTopic.allCases), quietHours: quiet)
        NotificationService(policy: { policy })
            .scheduleMealReminder(mealID: meal, mealName: "Gate test", fireDate: fire)

        try? await Task.sleep(for: .milliseconds(400))
        #expect(await !(pendingIDs().contains(id)))
    }
}
