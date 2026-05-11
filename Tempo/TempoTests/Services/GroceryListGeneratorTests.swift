//
// GroceryListGeneratorTests.swift
// Tempo
//
// Verifies aggregation across meals, pantry subtraction, and dropped-item
// behavior when the pantry already covers a need.
//

@testable import Tempo
import XCTest

@MainActor
final class GroceryListGeneratorTests: XCTestCase {
    // MARK: - Fixture helpers

    private func makePlan(foodsByMeal: [[PlannedFood]]) -> WeeklyMealPlan {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let plan = WeeklyMealPlan(startDate: start, endDate: end)
        let meals: [PlannedMeal] = foodsByMeal.enumerated().map { idx, foods in
            let meal = PlannedMeal(
                dayDate: Date(),
                mealNumber: idx + 1,
                mealName: "Meal \(idx + 1)",
                scheduledTime: "12:00",
                foods: foods,
                totalCalories: 0,
                totalProtein: 0,
                totalCarbs: 0,
                totalFat: 0,
                status: .planned,
                mealPlan: plan
            )
            return meal
        }
        plan.meals = meals
        return plan
    }

    private func food(_ name: String, _ g: Double) -> PlannedFood {
        PlannedFood(
            name: name,
            quantityGrams: g,
            calories: 0,
            proteinG: 0,
            carbsG: 0,
            fatG: 0
        )
    }

    // MARK: - Aggregation

    func testGenerate_aggregatesAcrossMeals() {
        let plan = makePlan(foodsByMeal: [
            [food("Chicken Breast", 200), food("Rice", 150)],
            [food("chicken breast", 250)], // canonical match
            [food("Salmon", 200)],
        ])
        let aggregated = GroceryListGenerator.generate(from: .init(
            mealPlan: plan, pantry: [], weekStartDate: Date()
        ))
        let byName = Dictionary(uniqueKeysWithValues: aggregated.map { ($0.canonicalName, $0) })
        XCTAssertEqual(byName["chicken breast"]?.quantity, 450)
        XCTAssertEqual(byName["rice"]?.quantity, 150)
        XCTAssertEqual(byName["salmon"]?.quantity, 200)
    }

    // MARK: - Pantry subtraction

    func testGenerate_subtractsPantry() {
        let plan = makePlan(foodsByMeal: [
            [food("Chicken Breast", 600), food("Oats", 200)],
        ])
        let pantry = [
            PantryItem(canonicalName: "chicken breast", displayName: "Chicken Breast",
                       quantity: 400, unit: .grams),
            PantryItem(canonicalName: "oats", displayName: "Oats",
                       quantity: 300, unit: .grams), // more than needed
        ]
        let aggregated = GroceryListGenerator.generate(from: .init(
            mealPlan: plan, pantry: pantry, weekStartDate: Date()
        ))
        let byName = Dictionary(uniqueKeysWithValues: aggregated.map { ($0.canonicalName, $0) })
        XCTAssertEqual(byName["chicken breast"]?.quantity, 200)
        // Oats fully covered → dropped from the list.
        XCTAssertNil(byName["oats"])
    }

    func testGenerate_dropsFullyCovered() {
        let plan = makePlan(foodsByMeal: [
            [food("Salmon", 200)],
        ])
        let pantry = [
            PantryItem(canonicalName: "salmon", displayName: "Salmon",
                       quantity: 200, unit: .grams),
        ]
        let aggregated = GroceryListGenerator.generate(from: .init(
            mealPlan: plan, pantry: pantry, weekStartDate: Date()
        ))
        XCTAssertTrue(aggregated.isEmpty)
    }

    // MARK: - Categorization

    func testCategory_routesByName() {
        XCTAssertEqual(GroceryListGenerator.category(for: "chicken breast"), "protein")
        XCTAssertEqual(GroceryListGenerator.category(for: "salmon"), "protein")
        XCTAssertEqual(GroceryListGenerator.category(for: "greek yogurt"), "dairy")
        XCTAssertEqual(GroceryListGenerator.category(for: "rice"), "grains")
        XCTAssertEqual(GroceryListGenerator.category(for: "oats"), "grains")
        XCTAssertEqual(GroceryListGenerator.category(for: "spinach"), "produce")
        XCTAssertEqual(GroceryListGenerator.category(for: "olive oil"), "oils")
        XCTAssertEqual(GroceryListGenerator.category(for: "quinoa"), "pantry")
    }

    // MARK: - Italian fixtures via canonicalizer

    func testGenerate_italianInputCanonicalizesAndAggregates() {
        let plan = makePlan(foodsByMeal: [
            [food("petto di pollo", 200)],
            [food("Chicken", 150)],
        ])
        let aggregated = GroceryListGenerator.generate(from: .init(
            mealPlan: plan, pantry: [], weekStartDate: Date()
        ))
        let byName = Dictionary(uniqueKeysWithValues: aggregated.map { ($0.canonicalName, $0) })
        XCTAssertEqual(byName["chicken breast"]?.quantity, 350)
    }
}
