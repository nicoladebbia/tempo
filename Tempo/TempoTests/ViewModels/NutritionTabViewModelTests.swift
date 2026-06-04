//
// NutritionTabViewModelTests.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - Nutrition Tab ViewModel Tests

// Phase 4 — recovery-adjusted targets, macro math sanity, meal-reminder scheduling.

@MainActor
final class NutritionTabViewModelTests: XCTestCase {
    private var viewModel: NutritionTabViewModel!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self,
            MealFeedback.self, PantryItem.self,
            configurations: config
        )
        viewModel = NutritionTabViewModel()
    }

    // MARK: - Macro Math (P×4 + C×4 + F×9 ≈ kcal)

    func testMacroMath_planning_sumsWithin10kcal() {
        // P×4 + C×4 + F×9 = 160 + 200 + 135 = 495 kcal
        viewModel._testSetTodayMeals([
            makePlanned(meal: 1, p: 40, c: 50, f: 15, kcal: 495, status: .eaten),
        ])
        let computed = viewModel.todayProteinConsumed * 4
            + viewModel.todayCarbsConsumed * 4
            + viewModel.todayFatConsumed * 9
        XCTAssertLessThanOrEqual(abs(computed - viewModel.todayCaloriesConsumed), 10)
    }

    // MARK: - Recovery-Adjusted Targets

    func testRecoveryAdjustedTarget_neutralWhenNoRecovery() {
        viewModel._testSetTodayRecovery(nil)
        XCTAssertEqual(viewModel.recoveryCalorieMultiplier, 1.0)
        XCTAssertEqual(viewModel.recoveryAdjustedCalorieTarget, viewModel.todayCalorieTarget)
        XCTAssertNil(viewModel.recoveryAdjustmentLabel)
    }

    func testRecoveryAdjustedTarget_addsCaloriesOnHighRecovery() {
        viewModel._testSetTodayRecovery(WhoopRecoveryData(
            score: 80, hrvRmssd: 65, restingHeartRate: 55,
            spo2: 98, skinTemp: 33.5, date: Date()
        ))
        XCTAssertEqual(viewModel.recoveryCalorieMultiplier, 1.05, accuracy: 0.001)
        XCTAssertGreaterThan(viewModel.recoveryAdjustedCalorieTarget, viewModel.todayCalorieTarget)
        XCTAssertNotNil(viewModel.recoveryAdjustmentLabel)
    }

    func testRecoveryAdjustedTarget_subtractsOnLowRecovery() {
        viewModel._testSetTodayRecovery(WhoopRecoveryData(
            score: 25, hrvRmssd: 30, restingHeartRate: 70,
            spo2: 96, skinTemp: 33.0, date: Date()
        ))
        XCTAssertEqual(viewModel.recoveryCalorieMultiplier, 0.95, accuracy: 0.001)
        XCTAssertLessThan(viewModel.recoveryAdjustedCalorieTarget, viewModel.todayCalorieTarget)
        XCTAssertNotNil(viewModel.recoveryAdjustmentLabel)
    }

    func testRecoveryAdjustedCarbs_absorbExtraCalories() {
        viewModel._testSetTodayRecovery(WhoopRecoveryData(
            score: 80, hrvRmssd: 65, restingHeartRate: 55,
            spo2: 98, skinTemp: 33.5, date: Date()
        ))
        XCTAssertGreaterThan(viewModel.recoveryAdjustedCarbsTarget, viewModel.todayCarbsTarget)
    }

    // MARK: - Meal Reminder Scheduling

    func testScheduleMealReminders_skipsAlreadyEaten() {
        let mock = MockNotificationService()
        viewModel._testSetTodayMeals([
            makePlanned(
                meal: 1,
                p: 30,
                c: 40,
                f: 10,
                kcal: 370,
                status: .eaten,
                scheduled: nextTimeString(addingMinutes: 30)
            ),
            makePlanned(
                meal: 2,
                p: 30,
                c: 40,
                f: 10,
                kcal: 370,
                status: .planned,
                scheduled: nextTimeString(addingMinutes: 60)
            ),
        ])
        viewModel.scheduleMealReminders(notifications: mock)
        let reminders = mock.scheduledNotifications.filter { $0.category == "meal_reminder" }
        XCTAssertEqual(reminders.count, 1, "Only the planned meal should be scheduled")
    }

    func testScheduleMealReminders_skipsPastTimes() {
        let mock = MockNotificationService()
        viewModel._testSetTodayMeals([
            // Scheduled 30 minutes ago — skipped because the 5-min-prior fire time is in the past.
            makePlanned(
                meal: 1,
                p: 30,
                c: 40,
                f: 10,
                kcal: 370,
                status: .planned,
                scheduled: nextTimeString(addingMinutes: -30)
            ),
        ])
        viewModel.scheduleMealReminders(notifications: mock)
        let reminders = mock.scheduledNotifications.filter { $0.category == "meal_reminder" }
        XCTAssertTrue(reminders.isEmpty)
    }

    // MARK: - Helpers

    private func makePlanned(
        meal: Int, p: Double, c: Double, f: Double, kcal: Double,
        status: MealStatus, scheduled: String = "12:00"
    ) -> PlannedMeal {
        PlannedMeal(
            dayDate: Date(),
            mealNumber: meal,
            mealName: "Meal \(meal)",
            scheduledTime: scheduled,
            foods: [],
            totalCalories: kcal,
            totalProtein: p,
            totalCarbs: c,
            totalFat: f,
            status: status
        )
    }

    // MARK: - Today's supplement decisions (weekday-key resolution)

    func testTodaySupplementDecisions_resolvesTodayByPlanDayIndex() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Anchor the plan to THIS week's Monday, matching persistPlan.
        let weekdayOfToday = cal.component(.weekday, from: today) // 1=Sun..7=Sat
        let mondayOffset = (weekdayOfToday + 5) % 7 // days since Monday
        let monday = cal.date(byAdding: .day, value: -mondayOffset, to: today)!
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!

        let plan = WeeklyMealPlan(
            startDate: monday, endDate: sunday,
            dayTypeAssignments: [:], isActive: true
        )
        // Key each day (1=Mon..7=Sun) to a uniquely named supplement so we can
        // prove the resolver picks TODAY's, not a neighbor's (off-by-one guard).
        var decisions: [Int: [SupplementDecision]] = [:]
        for key in 1 ... 7 {
            decisions[key] = [SupplementDecision(name: "Day\(key)", take: true, reason: nil)]
        }
        plan.supplementDecisions = decisions
        viewModel._testSetWeeklyPlan(plan)

        let todayKey = mondayOffset + 1 // (days since Monday) + 1
        let resolved = viewModel.todaySupplementDecisions
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.name, "Day\(todayKey)",
                       "Must resolve TODAY's decisions, not a neighboring day's")
    }

    func testTodaySupplementDecisions_emptyWhenNoPlan() {
        viewModel._testSetWeeklyPlan(nil)
        XCTAssertTrue(viewModel.todaySupplementDecisions.isEmpty)
    }

    private func nextTimeString(addingMinutes minutes: Int) -> String {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Undo meal eaten
    //
    // All three tests share the SINGLE setUp `container`. Standing up a SECOND
    // in-memory container mid-test (both registering PlannedMeal) traps
    // SwiftData on insert — that, not MealFeedback-in-schema, was the crash.

    func testUndoMealEaten_revertsStatusClearsTimeAndDeletesFeedback() throws {
        let ctx = container.mainContext
        let meal = makePlanned(meal: 1, p: 20, c: 80, f: 10, kcal: 480, status: .eaten)
        meal.actualEatenAt = Date()
        ctx.insert(meal)
        let feedback = MealFeedback(plannedMeal: meal, mealFeel: .clean)
        ctx.insert(feedback)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(meal.status, .planned, "Undo must revert to planned")
        XCTAssertNil(meal.actualEatenAt, "Eaten time must be cleared")
        let remaining = (try? ctx.fetch(FetchDescriptor<MealFeedback>())) ?? []
        XCTAssertTrue(remaining.isEmpty, "The meal's feedback row must be deleted")
    }

    func testUndoMealEaten_reCreditsPantryWhenDecrementedThenResetsFlag() throws {
        let ctx = container.mainContext
        let meal = makePlanned(meal: 1, p: 5, c: 40, f: 2, kcal: 200, status: .eaten)
        // Non-staple, grams unit so re-credit is direct: 1000 − 153 (eaten) =
        // 847; undo adds 153 back → 1000.
        meal.foods = [PlannedFood(name: "rice", quantityGrams: 153,
                                  calories: 200, proteinG: 5, carbsG: 40, fatG: 2)]
        meal.didDecrementPantry = true
        let rice = PantryItem(canonicalName: "rice", displayName: "Rice",
                              quantity: 847, unit: .grams, storageLocation: .pantry)
        ctx.insert(meal)
        ctx.insert(rice)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(rice.quantity, 1000, accuracy: 0.001,
                       "Undo must re-credit the 153g it had decremented")
        XCTAssertFalse(meal.didDecrementPantry,
                       "Flag reset so a re-log can decrement again")
    }

    func testUndoMealEaten_doesNotCreditPantryWhenNeverDecremented() throws {
        let ctx = container.mainContext
        // "Ate out" substitute: eaten but pantry never touched (flag false).
        let meal = makePlanned(meal: 1, p: 5, c: 40, f: 2, kcal: 200, status: .eaten)
        meal.foods = [PlannedFood(name: "rice", quantityGrams: 153,
                                  calories: 200, proteinG: 5, carbsG: 40, fatG: 2)]
        meal.didDecrementPantry = false
        let rice = PantryItem(canonicalName: "rice", displayName: "Rice",
                              quantity: 500, unit: .grams, storageLocation: .pantry)
        ctx.insert(meal)
        ctx.insert(rice)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(rice.quantity, 500,
                       "No decrement happened → undo must not invent stock")
    }

    func testUndoMealEaten_revertsASkippedMealToPlanned() throws {
        // Un-skip: undoMealEaten is status-agnostic. A skipped meal never
        // decremented pantry or stored feedback, so undo just flips it back
        // to planned so it counts again.
        let ctx = container.mainContext
        let meal = makePlanned(meal: 1, p: 30, c: 60, f: 15, kcal: 500, status: .skipped)
        ctx.insert(meal)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(meal.status, .planned, "Undo skip must put the meal back to planned")
        XCTAssertNil(meal.actualEatenAt)
    }
}
