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

    private func nextTimeString(addingMinutes minutes: Int) -> String {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
