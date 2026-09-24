//
// AdaptiveDietServiceTests.swift
// Tempo
//
// AdaptiveDietService reads canonical eaten PlannedMeals, not MealLog —
// a Mark-Eaten-only day (no MealLog rows) must register its real deficit.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class AdaptiveDietServiceTests: XCTestCase {
    func testMarkEatenOnlyDeficitCarriesForward() throws {
        let container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, MealLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let cal = Calendar.current
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())))
        let plan = try WeeklyMealPlan(startDate: yesterday, endDate: XCTUnwrap(cal.date(byAdding: .day, value: 6, to: yesterday)))
        ctx.insert(plan)
        for (n, status) in [(1, MealStatus.eaten), (2, MealStatus.skipped)] {
            ctx.insert(PlannedMeal(
                dayDate: yesterday, mealNumber: n, mealName: "Meal \(n)", scheduledTime: "12:00",
                totalCalories: 1000, totalProtein: 60, totalCarbs: 100, totalFat: 30,
                status: status, mealPlan: plan
            ))
        }
        try ctx.save()

        let adj = AdaptiveDietService.calculateDailyAdjustment(
            modelContext: ctx, whoopRecovery: nil, whoopStrain: nil, sleepHours: nil
        )
        XCTAssertGreaterThan(adj.calorieDelta, 0, "A 1000 kcal Mark-Eaten deficit must be seen")
        XCTAssertTrue(adj.explanation.contains("deficit"))
    }
}
