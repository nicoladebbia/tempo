//
// PantryDepletionPlanCheckTests.swift
// Tempo
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PantryDepletionPlanCheckTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: WeeklyMealPlan.self, PlannedMeal.self, Recipe.self, RecipeIngredient.self,
            GroceryList.self, GroceryListItem.self,
            configurations: config
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makePlan(startOffset: Int = 0, endOffset: Int = 6) -> WeeklyMealPlan {
        let start = Calendar.current.date(byAdding: .day, value: startOffset, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: endOffset, to: Date())!
        let plan = WeeklyMealPlan(startDate: start, endDate: end)
        context.insert(plan)
        return plan
    }

    @discardableResult
    private func addMeal(
        to plan: WeeklyMealPlan, dayOffset: Int, foods: [PlannedFood] = [],
        status: MealStatus = .planned, recipe: Recipe? = nil
    ) -> PlannedMeal {
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())!
        let meal = PlannedMeal(dayDate: day, mealName: "Meal", foods: foods, status: status, mealPlan: plan, recipe: recipe)
        context.insert(meal)
        return meal
    }

    private func food(_ name: String) -> PlannedFood {
        PlannedFood(name: name, quantityGrams: 100, calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }

    // MARK: - isNeededSoon via meal.foods

    func testIsNeededSoon_planMealWithinWindow_matchesViaFoods() throws {
        let plan = makePlan()
        addMeal(to: plan, dayOffset: 1, foods: [food("rice")])
        try context.save()

        XCTAssertTrue(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan))
    }

    func testIsNeededSoon_noMatchingFood_returnsFalse() throws {
        let plan = makePlan()
        addMeal(to: plan, dayOffset: 1, foods: [food("pasta")])
        try context.save()

        XCTAssertFalse(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan))
    }

    func testIsNeededSoon_mealAlreadyEaten_isIgnored() throws {
        let plan = makePlan()
        addMeal(to: plan, dayOffset: 1, foods: [food("rice")], status: .eaten)
        try context.save()

        XCTAssertFalse(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan), "Only still-.planned meals count")
    }

    func testIsNeededSoon_dayOutsideWindow_returnsFalse() throws {
        let plan = makePlan(endOffset: 10)
        addMeal(to: plan, dayOffset: 5, foods: [food("rice")]) // default withinDays: 3
        try context.save()

        XCTAssertFalse(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan))
    }

    func testIsNeededSoon_dayInPast_returnsFalse() throws {
        let plan = makePlan(startOffset: -5)
        addMeal(to: plan, dayOffset: -2, foods: [food("rice")])
        try context.save()

        XCTAssertFalse(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan))
    }

    func testIsNeededSoon_nilPlan_returnsFalse() {
        XCTAssertFalse(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: nil))
    }

    func testIsNeededSoon_emptyPlan_returnsFalse() throws {
        let plan = makePlan()
        try context.save()
        XCTAssertFalse(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan))
    }

    func testIsNeededSoon_customWithinDaysWidensWindow() throws {
        let plan = makePlan(endOffset: 10)
        addMeal(to: plan, dayOffset: 5, foods: [food("rice")])
        try context.save()

        XCTAssertTrue(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan, withinDays: 7))
    }

    // MARK: - isNeededSoon via recipe.ingredients

    func testIsNeededSoon_matchesViaRecipeIngredients() throws {
        let plan = makePlan()
        let recipe = Recipe(name: "Rice Bowl")
        context.insert(recipe)
        let ingredient = RecipeIngredient(recipe: recipe, orderIndex: 0, canonicalFoodName: "rice", displayName: "Rice", quantityGrams: 150)
        context.insert(ingredient)
        recipe.ingredients = [ingredient]
        addMeal(to: plan, dayOffset: 1, recipe: recipe)
        try context.save()

        XCTAssertTrue(PantryDepletionPlanCheck.isNeededSoon(canonicalName: "rice", in: plan))
    }

    // MARK: - handleDepletions

    func testHandleDepletions_addsOnlyDepletedAndNeededSoonItems() throws {
        let plan = makePlan()
        addMeal(to: plan, dayOffset: 1, foods: [food("rice")])
        try context.save()

        let results: [PantryDecrementResult] = [
            PantryDecrementResult(canonicalName: "rice", requestedGrams: 100, outcome: .depleted),
            PantryDecrementResult(canonicalName: "pasta", requestedGrams: 100, outcome: .depleted), // not on plan
            PantryDecrementResult(canonicalName: "chicken", requestedGrams: 100, outcome: .decremented(remaining: 50)), // not depleted
        ]

        let added = PantryDepletionPlanCheck.handleDepletions(results, weeklyPlan: plan, modelContext: context)

        XCTAssertEqual(added, 1)
        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        let names = (lists.first?.items ?? []).map(\.canonicalFoodName)
        XCTAssertEqual(names, ["rice"])
    }

    func testHandleDepletions_noPlan_addsNothing() {
        let results: [PantryDecrementResult] = [
            PantryDecrementResult(canonicalName: "rice", requestedGrams: 100, outcome: .depleted),
        ]

        let added = PantryDepletionPlanCheck.handleDepletions(results, weeklyPlan: nil, modelContext: context)

        XCTAssertEqual(added, 0)
    }

    func testHandleDepletions_emptyResults_addsNothing() {
        let added = PantryDepletionPlanCheck.handleDepletions([], weeklyPlan: nil, modelContext: context)
        XCTAssertEqual(added, 0)
    }
}
