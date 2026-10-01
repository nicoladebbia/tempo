//
// GroceryWeekAnchorTests.swift
// Tempo
//
// BUILD item 1a: the grocery list's weekStartDate must be the source plan's
// Monday, not "today" — so a mid-week regenerate REPLACES that week's list
// instead of spawning a second one. Also covers the 4-week retention prune
// that runs on every generate().
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GroceryWeekAnchorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var grocery: LocalGroceryListService!
    private var pantry: LocalPantryService!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: GroceryList.self, GroceryListItem.self, WeeklyMealPlan.self,
            PlannedMeal.self, PantryItem.self,
            configurations: config
        )
        context = container.mainContext
        grocery = LocalGroceryListService(modelContext: context)
        pantry = LocalPantryService(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil; context = nil; grocery = nil; pantry = nil
        try await super.tearDown()
    }

    private func makePlan(startDate: Date, foods: [(String, Double)]) -> WeeklyMealPlan {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let plan = WeeklyMealPlan(startDate: start, endDate: end)
        context.insert(plan)
        let meal = PlannedMeal(
            dayDate: start, mealNumber: 1, mealName: "Meal 1", scheduledTime: "12:00",
            foods: foods.map { PlannedFood(name: $0.0, quantityGrams: $0.1, calories: 0, proteinG: 0, carbsG: 0, fatG: 0) },
            mealPlan: plan
        )
        context.insert(meal)
        return plan
    }

    /// Monday of THIS week — matches how the plan's own startDate is anchored.
    private var thisMonday: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let daysSinceMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    func testGenerate_usesPlanStartDateNotToday() throws {
        // A plan for NEXT week (not "today") — the resulting list must be
        // stamped with the PLAN's Monday, matching what the caller passes as
        // weekStartDate (NutritionTabViewModel now passes plan.startDate).
        let nextMonday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: thisMonday))
        let plan = makePlan(startDate: nextMonday, foods: [("Rice", 200)])

        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)

        XCTAssertEqual(
            Calendar.current.startOfDay(for: list.weekStartDate),
            Calendar.current.startOfDay(for: nextMonday),
            "List must be anchored to the PLAN's week, not today's"
        )
    }

    func testGenerate_midWeekRegenerateReplacesSameWeekList_notDuplicate() throws {
        let plan = makePlan(startDate: thisMonday, foods: [("Rice", 200)])
        grocery.now = { plan.startDate }
        _ = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)

        // Simulate "today" being mid-week by regenerating with the SAME
        // plan.startDate (as the real call site now always does) — this must
        // replace, not add a second list for the week.
        grocery.now = { plan.startDate }
        _ = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)

        let all = try grocery.fetchAll()
        XCTAssertEqual(all.count, 1, "Regenerating for the same week must replace, not duplicate")
    }

    func testGenerate_pruningRemovesListsOlderThanFourWeeks() throws {
        // A list 6 weeks in the past — should be pruned once ANY generate() runs.
        let sixWeeksAgo = try XCTUnwrap(Calendar.current.date(byAdding: .weekOfYear, value: -6, to: thisMonday))
        let oldPlan = makePlan(startDate: sixWeeksAgo, foods: [("Oats", 200)])
        grocery.now = { oldPlan.startDate }
        _ = try grocery.generate(from: oldPlan, pantry: pantry, weekStartDate: oldPlan.startDate)
        XCTAssertEqual(try grocery.fetchAll().count, 1)

        // A fresh generate for THIS week should prune the 6-week-old list.
        let currentPlan = makePlan(startDate: thisMonday, foods: [("Rice", 200)])
        grocery.now = { currentPlan.startDate }
        _ = try grocery.generate(from: currentPlan, pantry: pantry, weekStartDate: currentPlan.startDate)

        let all = try grocery.fetchAll()
        XCTAssertEqual(all.count, 1, "The 6-week-old list must be pruned")
        XCTAssertEqual(Calendar.current.startOfDay(for: all[0].weekStartDate), thisMonday)
    }

    func testGenerate_recentListsWithinRetentionAreKept() throws {
        // A list 2 weeks old must survive (within the 4-week retention window).
        let twoWeeksAgo = try XCTUnwrap(Calendar.current.date(byAdding: .weekOfYear, value: -2, to: thisMonday))
        let oldPlan = makePlan(startDate: twoWeeksAgo, foods: [("Oats", 200)])
        grocery.now = { oldPlan.startDate }
        _ = try grocery.generate(from: oldPlan, pantry: pantry, weekStartDate: oldPlan.startDate)

        let currentPlan = makePlan(startDate: thisMonday, foods: [("Rice", 200)])
        grocery.now = { currentPlan.startDate }
        _ = try grocery.generate(from: currentPlan, pantry: pantry, weekStartDate: currentPlan.startDate)

        XCTAssertEqual(try grocery.fetchAll().count, 2, "2-week-old list is within retention")
    }
}
