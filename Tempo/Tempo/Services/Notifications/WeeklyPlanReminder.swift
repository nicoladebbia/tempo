//
// WeeklyPlanReminder.swift
// Tempo
//
// The repeating Sunday notification that starts the week-by-week loop:
// "Plan next week?" → Yes (built in the background, no app launch needed)
// or "Something's different" (opens the 30-second check-in). Lives outside
// NotificationService's daily budget: it's one repeating request the user
// asked for, not a nudge.
//

import Foundation
import UserNotifications

enum WeeklyPlanReminder {
    static let requestID = "weekly_plan_prompt"
    static let categoryID = "WEEKLY_PLAN_PROMPT"
    static let readyCategoryID = "MEAL_PLAN_READY"
    static let buildActionID = "WEEKLY_PLAN_BUILD"
    static let checkInActionID = "WEEKLY_PLAN_CHECKIN"
    static let defaultMinutes = 18 * 60

    /// Sunday (weekday 1) at `minutes`, every week.
    static func trigger(minutes: Int) -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.weekday = 1
        components.hour = minutes / 60
        components.minute = minutes % 60
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    /// Schedule (or remove) the Sunday prompt to match the settings.
    static func sync(enabled: Bool, minutes: Int, center: UNUserNotificationCenter = .current()) async {
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        guard enabled else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Sunday. Plan the week."
        content.body = "Next week's meals, built around your routine. Tap Yes and it's done in minutes."
        content.categoryIdentifier = categoryID
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger(minutes: minutes))
        try? await center.add(request)
    }

    @MainActor
    static func sync(settings: UserSettings?) async {
        await sync(
            enabled: settings?.weeklyPlanPromptEnabled ?? true,
            minutes: settings?.weeklyPlanPromptMinutes ?? defaultMinutes
        )
    }

    /// A one-off local notice (e.g. "couldn't start the plan") right now.
    static func notify(title: String, body: String, center: UNUserNotificationCenter = .current()) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryID
        let request = UNNotificationRequest(identifier: "weekly_plan_notice", content: content, trigger: nil)
        try? await center.add(request)
    }
}
