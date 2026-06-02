//
// PlanArchiveNoDuplicateTests.swift
// Tempo
//
// §2a archive-retention guard — the duplicate-meals regression. We switched
// plan regeneration from hard-DELETE to soft-ARCHIVE (isActive=false +
// isArchived=true) so the personalization engine keeps last week's behavior.
// The original delete existed to stop the Today surfaces showing meals from
// EVERY prior plan (each slot 2×/3×). Archiving is only safe because every
// today/active reader filters `mealPlan?.isActive == true`. This pins that:
// with an archived plan AND an active plan both dated today, loadToday must
// return ONLY the active plan's meals — no duplicates.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PlanArchiveNoDuplicateTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makePlan(active: Bool, archived: Bool, mealName: String) -> WeeklyMealPlan {
        let today = Calendar.current.startOfDay(for: Date())
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: today)!
        let plan = WeeklyMealPlan(startDate: today, endDate: weekEnd, isActive: active)
        plan.isArchived = archived
        context.insert(plan)
        let meal = PlannedMeal(
            dayDate: today,
            mealNumber: 1,
            mealName: mealName,
            scheduledTime: "08:00",
            totalCalories: 600,
            mealPlan: plan
        )
        context.insert(meal)
        return plan
    }

    func testLoadTodayReturnsOnlyActivePlanMeals() throws {
        // An archived past plan AND a fresh active plan, both covering today.
        _ = makePlan(active: false, archived: true, mealName: "OldBreakfast")
        _ = makePlan(active: true, archived: false, mealName: "NewBreakfast")
        try context.save()

        let vm = NutritionTabViewModel()
        vm.loadToday(modelContext: context)

        XCTAssertEqual(vm.todayMeals.count, 1,
                       "Only the active plan's meal should show — archived plan must not duplicate it")
        XCTAssertEqual(vm.todayMeals.first?.mealName, "NewBreakfast")
        // And the resolved weekly plan is the active, non-archived one.
        XCTAssertEqual(vm.weeklyPlan?.isActive, true)
        XCTAssertEqual(vm.weeklyPlan?.isArchived, false)
    }

    func testArchivedOnlyPlanYieldsNoActivePlan() throws {
        // After regen, if somehow only an archived plan exists for today, the
        // active-plan resolution returns nil (drives the no-plan empty state).
        _ = makePlan(active: false, archived: true, mealName: "OldBreakfast")
        try context.save()

        let vm = NutritionTabViewModel()
        vm.loadToday(modelContext: context)

        XCTAssertTrue(vm.todayMeals.isEmpty,
                      "Archived-plan meals must not surface on Today")
        XCTAssertNil(vm.weeklyPlan, "An archived-only state has no active plan")
    }
}
