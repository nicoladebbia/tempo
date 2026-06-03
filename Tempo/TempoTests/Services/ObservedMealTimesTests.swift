//
// ObservedMealTimesTests.swift
// Tempo
//
// Pins the meal-time precedence rule in MealPlanGeneratorService.observedMealTimes.
// The user's breakfast was stuck at 09:50 regardless of a 09:30 Whoop wake; the
// device probe showed `learned[1]=590` (09:50) WINNING over the wake-derived
// default — i.e. ≥2 historical eat-times at 09:50 override the wake anchor.
// These tests document that behavior and become the regression net for the
// upcoming precedence change (explicit signals should outrank inferred history).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ObservedMealTimesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: MealPlanGeneratorService!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, UserSettings.self,
            configurations: config
        )
        context = container.mainContext
        // observedMealTimes only reads the modelContext; the apiClient is
        // unused by this path, so a default client is fine.
        service = MealPlanGeneratorService(apiClient: APIClient())
    }

    override func tearDown() async throws {
        container = nil; context = nil; service = nil
        try await super.tearDown()
    }

    /// Insert an eaten breakfast (mealNumber 1) `daysAgo` days back at HH:MM.
    private func eatenBreakfast(daysAgo: Int, hour: Int, minute: Int) {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        let eatenAt = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        let meal = PlannedMeal(
            dayDate: day, mealNumber: 1, mealName: "Breakfast",
            scheduledTime: "09:50", totalCalories: 500
        )
        meal.actualEatenAt = eatenAt
        meal.status = .eaten
        context.insert(meal)
    }

    private func breakfast(_ result: MealPlanPrompts.ObservedMealTimes?) -> String? {
        result?[1]
    }

    // MARK: - Current behavior (documents the bug the user hit)

    func testTwoLearnedBreakfasts_overrideWakeAnchor_currentBehavior() {
        // Wake 09:30 → wake+60 default = 10:30. But two eaten breakfasts at
        // 09:50 produce learned[1]=590 which currently WINS → 09:50.
        eatenBreakfast(daysAgo: 1, hour: 9, minute: 50)
        eatenBreakfast(daysAgo: 2, hour: 9, minute: 50)
        let result = service.observedMealTimes(modelContext: context, wakeMinutesOverride: 570)
        XCTAssertEqual(breakfast(result), "09:50",
                       "Documents current rule: ≥2 learned breakfasts override the wake anchor")
    }

    func testSingleLearnedBreakfast_doesNotOverride_usesWake() {
        // Only ONE observation (< 2 threshold) → no learned signal → wake+60.
        eatenBreakfast(daysAgo: 1, hour: 9, minute: 50)
        let result = service.observedMealTimes(modelContext: context, wakeMinutesOverride: 570)
        XCTAssertEqual(breakfast(result), "10:30",
                       "One observation is below the ≥2 threshold → wake-derived 10:30")
    }

    func testNoHistory_usesWakeAnchor() {
        let result = service.observedMealTimes(modelContext: context, wakeMinutesOverride: 570)
        XCTAssertEqual(breakfast(result), "10:30", "No history → wake+60 = 10:30")
    }

    func testNoWake_fallsBackToStaticDefault() {
        let result = service.observedMealTimes(modelContext: context, wakeMinutesOverride: nil)
        // No UserSettings row → 07:00 default → breakfast 08:00.
        XCTAssertEqual(breakfast(result), "08:00", "No wake + no settings → 07:00 default → 08:00")
    }
}
