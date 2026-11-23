//
// NotificationRouterTests.swift
// TempoTests
//
// Every registered notification category / action maps to a sensible place.
//

import Foundation
import Testing
import UserNotifications
@testable import Tempo

struct NotificationRouterTests {
    private let meal = UUID()
    private var mealInfo: [AnyHashable: Any] { [NotificationService.mealIDUserInfoKey: meal.uuidString] }
    private let tap = UNNotificationDefaultActionIdentifier

    private func route(_ category: String, _ action: String? = nil, _ info: [AnyHashable: Any] = [:]) -> NotificationDestination? {
        NotificationRouter.destination(category: category, action: action ?? tap, userInfo: info)
    }

    @Test
    func weekReadyOpensPlanAndSyncs() {
        let serverPush: [AnyHashable: Any] = ["data": ["type": "meal_plan_ready", "jobId": "x"]]
        let dest = route("MEAL_PLAN_READY", nil, serverPush)
        #expect(dest?.tab == .fuel)
        #expect(dest?.nutritionSection == .plan)
        #expect(dest?.syncPlans == true)
    }

    @Test
    func weekReadyWithoutRegisteredCategoryStillRoutesByType() {
        let dest = route("", nil, ["data": ["type": "meal_plan_ready"]])
        #expect(dest?.nutritionSection == .plan)
        #expect(dest?.syncPlans == true)
    }

    @Test
    func mealReminderTapOpensThatMeal() {
        let dest = route("MEAL_REMINDER", nil, mealInfo)
        #expect(dest?.meal == MealRequest(id: meal, action: .open))
        #expect(dest?.tab == .fuel)
    }

    @Test
    func logMealOpensMarkEaten() {
        #expect(route("MEAL_REMINDER", "LOG_MEAL", mealInfo)?.meal == MealRequest(id: meal, action: .markEaten))
    }

    @Test
    func viewMealOpensMealForPrepAndDefrost() {
        #expect(route("DEFROST_REMINDER", "VIEW_MEAL", mealInfo)?.meal == MealRequest(id: meal, action: .open))
        #expect(route("PREP_START_REMINDER", "VIEW_MEAL", mealInfo)?.meal == MealRequest(id: meal, action: .open))
    }

    @Test
    func mealNotificationWithoutValidIDOpensNutritionToday() {
        #expect(route("MEAL_REMINDER")?.meal == nil)
        #expect(route("MEAL_REMINDER", nil, [NotificationService.mealIDUserInfoKey: "nope"])?.nutritionSection == .today)
    }

    @Test
    func supplementAndGroceryRoutesGoToKitchen() {
        #expect(route("SUPPLEMENT_REMINDER")?.kitchenSection == .supplements)
        #expect(route("SUPPLEMENT_REORDER")?.kitchenSection == .supplements)
        #expect(route("SUPPLEMENT_REORDER", "SUPPLEMENT_ADD_TO_LIST")?.kitchenSection == .groceries)
        #expect(route("USE_IT_UP", "VIEW_PANTRY")?.kitchenSection == .pantry)
    }

    @Test
    func quietActionsDoNotNavigate() {
        for action in ["DONE", "DELAY_15MIN", "DELAY_30MIN", "SKIP_TODAY", "IM_ON_IT", UNNotificationDismissActionIdentifier] {
            #expect(route("MEAL_REMINDER", action, mealInfo) == nil)
        }
    }

    @Test
    func sundayPromptOpensPlan() {
        #expect(route("WEEKLY_PLAN_PROMPT", "WEEKLY_PLAN_CHECK_IN")?.nutritionSection == .plan)
    }

    @Test
    func otherModulesLandOnTheirTab() {
        #expect(route("TRAINING_REMINDER", "VIEW_WORKOUT")?.tab == .train)
        #expect(route("RECOVERY_REPORT", "VIEW_WORKOUT")?.tab == .train)
        #expect(route("ARENA_SOCIAL")?.tab == .arena)
        #expect(route("WEEKLY_SUMMARY") == .tab(.today))
        #expect(route("MORNING_BRIEFING") == .tab(.today))
    }

    /// Recovery and Lockdown have no tab any more: their notifications open
    /// that page on top of Today.
    @Test
    func recoveryAndLockdownOpenOnToday() {
        #expect(route("RECOVERY_REPORT", "VIEW_RECOVERY") == .today(.recovery))
        #expect(route("BEDTIME_REMINDER") == .today(.recovery))
        #expect(route("STREAK_WARNING") == .today(.lockdown))
        for category in [
            "ACCOUNTABILITY", "ACCOUNTABILITY_GENTLE", "ACCOUNTABILITY_FIRM",
            "ACCOUNTABILITY_URGENT", "ACCOUNTABILITY_FINAL", "ACCOUNTABILITY_CLEAR",
        ] {
            #expect(route(category, "START_NOW") == .today(.lockdown))
        }
    }

    /// Server pushes with no registered category route by their type.
    @Test
    func serverPushTypesStillLand() {
        func push(_ type: String) -> NotificationDestination? {
            NotificationRouter.destination(
                category: "", action: NotificationRouter.defaultActionID, userInfo: ["data": ["type": type]]
            )
        }
        #expect(push("training_reminder") == .tab(.train))
        #expect(push("recovery_morning") == .today(.recovery))
        #expect(push("bedtime_reminder") == .today(.recovery))
        #expect(push("weekly_summary") == .tab(.today))
        for type in ["streak_warning", "accountability_tier1", "accountability_tier2", "accountability_tier3", "accountability_tier4"] {
            #expect(push(type) == .today(.lockdown))
        }
        for type in ["leaderboard_change", "challenge_invite", "challenge_update", "achievement_unlock"] {
            #expect(push(type) == .tab(.arena))
        }
        #expect(push("meal_plan_ready")?.tab == .fuel)
    }

    /// A route only makes sense on Today.
    @Test
    func todayRouteImpliesTodayTab() {
        #expect(NotificationDestination.today(.recovery).tab == .today)
        #expect(NotificationDestination.tab(.arena).todayRoute == nil)
    }

    @Test
    func unknownCategoryIsHarmless() {
        #expect(route("SOMETHING_NEW") == nil)
        #expect(route("GENERAL", nil, ["data": ["type": "general"]]) == nil)
    }

    @Test
    func everyRegisteredCategoryRoutesWithoutTrapping() {
        let categories = [
            "MORNING_BRIEFING", "ACCOUNTABILITY_GENTLE", "ACCOUNTABILITY_FIRM", "ACCOUNTABILITY_URGENT",
            "ACCOUNTABILITY_FINAL", "ACCOUNTABILITY_CLEAR", "WEEKLY_PLAN_PROMPT", "MEAL_PLAN_READY", "MEAL_REMINDER",
            "OVERDUE_MEAL_REMINDER", "TRAINING_REMINDER", "RECOVERY_REPORT", "BEDTIME_REMINDER", "DEFROST_REMINDER",
            "PREP_START_REMINDER", "ARENA_SOCIAL", "WEEKLY_SUMMARY", "USE_IT_UP", "STREAK_WARNING",
            "SUPPLEMENT_REMINDER", "SUPPLEMENT_REORDER",
        ]
        for category in categories {
            #expect(route(category, nil, mealInfo) != nil, "\(category) tap must land somewhere")
        }
    }

    @Test @MainActor
    func nutritionRouteShowsKitchenSection() {
        let viewModel = NutritionTabViewModel()
        viewModel.apply(NutritionRoute(section: .kitchen, kitchen: .supplements))
        #expect(viewModel.selectedTab == .kitchen)
        #expect(viewModel.selectedKitchen == .supplements)
        viewModel.apply(NutritionRoute(section: .plan, kitchen: nil))
        #expect(viewModel.selectedTab == .plan)
    }
}
