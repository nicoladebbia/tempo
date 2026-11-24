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

// MARK: - NotificationDestination

/// Where a notification wants the app to land.
struct NotificationDestination: Equatable {
    var tab: AppTab
    /// A page to open on top of Today (only with `tab == .today`).
    var todayRoute: TodayRoute?
    /// Fuel tab section to show (only with `tab == .fuel`).
    var nutritionSection: NutritionSection?
    /// Kitchen sub-section (implies the Kitchen section).
    var kitchenSection: KitchenSection?
    var meal: MealRequest?
    /// Open the Recovery Coach for this WHOOP session (id is a UUID string).
    var coachSessionID: String?
    /// Open the weekly check-in sheet.
    var weeklyCheckIn = false
    /// Pull the server-built plan (the "week is ready" push).
    var syncPlans = false

    static func tab(_ tab: AppTab) -> NotificationDestination {
        NotificationDestination(tab: tab)
    }

    /// Today, with Recovery or Lockdown opened on top of it.
    static func today(_ route: TodayRoute) -> NotificationDestination {
        NotificationDestination(tab: .today, todayRoute: route)
    }

    static func nutrition(
        _ section: NutritionSection? = nil, kitchen: KitchenSection? = nil, meal: MealRequest? = nil
    ) -> NotificationDestination {
        NotificationDestination(tab: .fuel, nutritionSection: section, kitchenSection: kitchen, meal: meal)
    }
}

// MARK: - NotificationRouter

enum NotificationRouter {
    static let defaultActionID = UNNotificationDefaultActionIdentifier
    static let dismissActionID = UNNotificationDismissActionIdentifier

    /// Buttons that act without opening anything.
    private static let quietActions: Set<String> = Set([
        dismissActionID, "DONE", "DELAY_15MIN", "DELAY_30MIN", "SKIP_TODAY", "IM_ON_IT",
        "SUPPLEMENT_TAKEN", "SUPPLEMENT_SNOOZE_15",
    ]).union(CoachQuickAnswerAction.allCases.map(\.rawValue))

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
        case "MEAL_REMINDER",
             "OVERDUE_MEAL_REMINDER",
             "DEFROST_REMINDER",
             "PREP_START_REMINDER":
            let request = TempoNotificationDelegate.mealRequest(category: category, action: action, mealID: mealID)
            return request.map { .nutrition(.today, meal: $0) } ?? .nutrition(.today)
        case CoachNotifications.postCategoryID:
            return coach(userInfo: userInfo)
        case CoachNotifications.preCategoryID:
            return .nutrition(.today)
        case "SUPPLEMENT_REMINDER":
            return .nutrition(kitchen: .supplements)
        case "SUPPLEMENT_REORDER":
            return .nutrition(kitchen: action == "SUPPLEMENT_ADD_TO_LIST" ? .groceries : .supplements)
        case "USE_IT_UP":
            return .nutrition(kitchen: .pantry)
        case "TRAINING_REMINDER":
            return .tab(.train)
        case "RECOVERY_REPORT":
            return action == "VIEW_WORKOUT" ? .tab(.train) : .today(.recovery)
        case "BEDTIME_REMINDER":
            return .today(.recovery)
        case "MORNING_BRIEFING",
             "WEEKLY_SUMMARY":
            return .tab(.today)
        case "ARENA_SOCIAL":
            return .tab(.arena)
        case "STREAK_WARNING",
             "ACCOUNTABILITY",
             "ACCOUNTABILITY_GENTLE",
             "ACCOUNTABILITY_FIRM",
             "ACCOUNTABILITY_URGENT",
             "ACCOUNTABILITY_FINAL",
             "ACCOUNTABILITY_CLEAR":
            return .today(.lockdown)
        default:
            return destination(forPushType: type, mealID: mealID, userInfo: userInfo)
        }
    }

    /// "Session done. Weigh in now.": Fuel > Coach, where that session sits at the top of the page.
    static func coach(userInfo: [AnyHashable: Any]) -> NotificationDestination {
        var destination = NotificationDestination.nutrition(.coach)
        destination.coachSessionID = CoachNotifications.sessionID(from: userInfo)
        return destination
    }

    /// "Your week is ready": the Plan section with the new week.
    static func planReady() -> NotificationDestination {
        var destination = NotificationDestination.nutrition(.plan)
        destination.syncPlans = true
        return destination
    }

    /// Server pushes whose category isn't registered on the device still route by type.
    private static func destination(forPushType type: String?, mealID: String?, userInfo: [AnyHashable: Any]) -> NotificationDestination? {
        switch type {
        case "meal_plan_ready":
            return planReady()
        case "meal_reminder":
            let request = TempoNotificationDelegate.mealRequest(category: "MEAL_REMINDER", action: defaultActionID, mealID: mealID)
            return request.map { .nutrition(.today, meal: $0) } ?? .nutrition(.today)
        case CoachNotifications.pushType:
            return coach(userInfo: userInfo)
        case "training_reminder":
            return .tab(.train)
        case "recovery_morning":
            return .today(.recovery)
        case "bedtime_reminder":
            return .today(.recovery)
        case "streak_warning",
             "accountability_tier1",
             "accountability_tier2",
             "accountability_tier3",
             "accountability_tier4":
            return .today(.lockdown)
        case "weekly_summary":
            return .tab(.today)
        case "leaderboard_change",
             "challenge_invite",
             "challenge_update",
             "achievement_unlock":
            return .tab(.arena)
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
