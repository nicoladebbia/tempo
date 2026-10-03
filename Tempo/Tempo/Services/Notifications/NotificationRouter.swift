//
// NotificationRouter.swift
// Tempo
//
// Pure mapping from a notification tap / action button to the place the app
// should open. No UI, no services: TempoNotificationDelegate applies the result
// to AppState, ContentView does the rest. Covers every category the app
// registers plus the server-only ones (APNsService.NotificationType).
//

import Foundation
import UserNotifications

/// Where a notification wants the app to land.
struct NotificationDestination: Equatable {
    var tab: Tab
    /// Nutrition tab section to show (only with `tab == .nutrition`).
    var nutritionSection: NutritionSection?
    /// Kitchen sub-section (implies the Kitchen section).
    var kitchenSection: KitchenSection?
    var meal: MealRequest?
    /// Open the weekly check-in sheet.
    var weeklyCheckIn = false
    /// Pull the server-built plan (the "week is ready" push).
    var syncPlans = false

    static func tab(_ tab: Tab) -> NotificationDestination {
        NotificationDestination(tab: tab)
    }

    static func nutrition(
        _ section: NutritionSection? = nil, kitchen: KitchenSection? = nil, meal: MealRequest? = nil
    ) -> NotificationDestination {
        NotificationDestination(tab: .nutrition, nutritionSection: section, kitchenSection: kitchen, meal: meal)
    }
}

enum NotificationRouter {
    static let defaultActionID = UNNotificationDefaultActionIdentifier
    static let dismissActionID = UNNotificationDismissActionIdentifier

    /// Buttons that act without opening anything.
    private static let quietActions: Set<String> = [
        dismissActionID, "DONE", "DELAY_15MIN", "DELAY_30MIN", "SKIP_TODAY", "IM_ON_IT",
        "SUPPLEMENT_TAKEN", "SUPPLEMENT_SNOOZE_15",
    ]

    /// `userInfo` is the notification's raw payload: server pushes nest custom
    /// keys under `"data"`, local ones put them at the top level.
    static func destination(category: String, action: String, userInfo: [AnyHashable: Any]) -> NotificationDestination? {
        if quietActions.contains(action) {
            return nil
        }
        let type = TempoNotificationDelegate.pushType(from: userInfo)
        let mealID = string(NotificationService.mealIDUserInfoKey, in: userInfo)

        switch category {
        case WeeklyPlanReminder.readyCategoryID:
            return planReady()
        case WeeklyPlanReminder.categoryID:
            var destination = NotificationDestination.nutrition(.plan)
            destination.weeklyCheckIn = action == WeeklyPlanReminder.checkInActionID || action == defaultActionID
            return destination
        case "MEAL_REMINDER", "OVERDUE_MEAL_REMINDER", "DEFROST_REMINDER", "PREP_START_REMINDER":
            let request = TempoNotificationDelegate.mealRequest(category: category, action: action, mealID: mealID)
            return request.map { .nutrition(.today, meal: $0) } ?? .nutrition(.today)
        case "SUPPLEMENT_REMINDER":
            return .nutrition(kitchen: .supplements)
        case "SUPPLEMENT_REORDER":
            return .nutrition(kitchen: action == "SUPPLEMENT_ADD_TO_LIST" ? .groceries : .supplements)
        case "USE_IT_UP":
            return .nutrition(kitchen: .pantry)
        case "TRAINING_REMINDER":
            return .tab(.training)
        case "RECOVERY_REPORT":
            return .tab(action == "VIEW_WORKOUT" ? .training : .recovery)
        case "BEDTIME_REMINDER":
            return .tab(.recovery)
        case "MORNING_BRIEFING", "WEEKLY_SUMMARY", "ARENA_SOCIAL":
            return .tab(.dashboard)
        case "STREAK_WARNING", "ACCOUNTABILITY", "ACCOUNTABILITY_GENTLE", "ACCOUNTABILITY_FIRM",
             "ACCOUNTABILITY_URGENT", "ACCOUNTABILITY_FINAL", "ACCOUNTABILITY_CLEAR":
            return .tab(.lockdown)
        default:
            return destination(forPushType: type, mealID: mealID)
        }
    }

    /// "Your week is ready": the Plan section with the new week.
    static func planReady() -> NotificationDestination {
        var destination = NotificationDestination.nutrition(.plan)
        destination.syncPlans = true
        return destination
    }

    /// Server pushes whose category isn't registered on the device still route by type.
    private static func destination(forPushType type: String?, mealID: String?) -> NotificationDestination? {
        switch type {
        case "meal_plan_ready":
            return planReady()
        case "meal_reminder":
            let request = TempoNotificationDelegate.mealRequest(category: "MEAL_REMINDER", action: defaultActionID, mealID: mealID)
            return request.map { .nutrition(.today, meal: $0) } ?? .nutrition(.today)
        case "training_reminder":
            return .tab(.training)
        case "recovery_morning":
            return .tab(.recovery)
        case "bedtime_reminder":
            return .tab(.recovery)
        case "streak_warning", "accountability_tier1", "accountability_tier2", "accountability_tier3", "accountability_tier4":
            return .tab(.lockdown)
        case "weekly_summary", "leaderboard_change", "challenge_invite", "challenge_update", "achievement_unlock":
            return .tab(.dashboard)
        default:
            return nil
        }
    }

    private static func string(_ key: String, in userInfo: [AnyHashable: Any]) -> String? {
        if let data = userInfo["data"] as? [String: Any], let value = data[key] as? String {
            return value
        }
        return userInfo[key] as? String
    }
}
