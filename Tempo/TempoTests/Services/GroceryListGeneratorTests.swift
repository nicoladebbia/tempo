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

    // The bug: generate() only subtracted pantry stock when the pantry item's
    // unit EXACTLY matched the (always-grams) aggregated need. A voice/scan
    // pantry holds items in ml / lb / pieces, so they were silently NOT
    // subtracted → the list told you to buy food you already had. The fix
    // converts both sides to grams via gramsApprox (same as reapplyPantry).
    func testGenerate_subtractsPantryAcrossUnits_gramConvertible() throws {
        // Ground beef is non-staple (so the staple gate can't mask the result)
        // and lb→g convertible. Need 2000g; pantry holds 2 lb (~907g) in a
        // DIFFERENT unit than the grams need. Cross-unit subtraction must leave
        // ~1093g to buy. Compare against the no-pantry baseline: if the
        // subtraction is unit-blind (the bug), both are identical.
        let plan = makePlan(foodsByMeal: [
            [food("Ground Beef", 2000)],
        ])
        let baseline = GroceryListGenerator.generate(from: .init(
            mealPlan: plan, pantry: [], weekStartDate: Date()
        )).first { $0.canonicalName == "ground beef" }
        let withPantry = GroceryListGenerator.generate(from: .init(
            mealPlan: plan,
            pantry: [PantryItem(canonicalName: "ground beef", displayName: "Ground Beef",
                                quantity: 2, unit: .pounds)],
            weekStartDate: Date()
        )).first { $0.canonicalName == "ground beef" }

        let base = try XCTUnwrap(baseline)
        let withP = try XCTUnwrap(withPantry, "Still some to buy after partial cover")
        XCTAssertLessThan(
            withP.quantity, base.quantity,
            "2 lb of pantry beef must reduce the 2000g need even though units differ"
        )
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
        // Meat + seafood are now distinct aisles (was a single "protein").
        XCTAssertEqual(GroceryListGenerator.category(for: "chicken breast"), "meat")
        XCTAssertEqual(GroceryListGenerator.category(for: "salmon"), "seafood")
        XCTAssertEqual(GroceryListGenerator.category(for: "greek yogurt"), "dairy")
        XCTAssertEqual(GroceryListGenerator.category(for: "rice"), "grains")
        XCTAssertEqual(GroceryListGenerator.category(for: "oats"), "grains")
        XCTAssertEqual(GroceryListGenerator.category(for: "spinach"), "produce")
        XCTAssertEqual(GroceryListGenerator.category(for: "olive oil"), "oils")
        XCTAssertEqual(GroceryListGenerator.category(for: "quinoa"), "grains") // now categorized
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
