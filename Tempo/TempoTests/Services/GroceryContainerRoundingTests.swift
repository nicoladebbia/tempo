//
// GroceryContainerRoundingTests.swift
// Tempo
//
// BUILD item 1d: fractional container quantities ("0.4 cans") aren't
// purchasable — every path that can produce one must round UP to a whole
// unit instead. Covers the shared `PantryUnit.wholeUnitQuantity` helper, the
// reapplyPantry partial-coverage shrink, and manual add.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GroceryContainerRoundingTests: XCTestCase {
    // MARK: - PantryUnit.wholeUnitQuantity (pure)

    func testWholeUnitQuantity_roundsCountableUnitsUp() {
        XCTAssertEqual(PantryUnit.cans.wholeUnitQuantity(0.4), 1)
        XCTAssertEqual(PantryUnit.packs.wholeUnitQuantity(2.1), 3)
        XCTAssertEqual(PantryUnit.jars.wholeUnitQuantity(1.0), 1)
    }

    func testWholeUnitQuantity_passesThroughNonCountableUnits() {
        XCTAssertEqual(PantryUnit.grams.wholeUnitQuantity(180.5), 180.5)
        XCTAssertEqual(PantryUnit.milliliters.wholeUnitQuantity(33.3), 33.3)
    }

    func testWholeUnitQuantity_zeroOrNegativePassesThrough() {
        // Zero means "fully covered" — must NOT become "buy 1".
        XCTAssertEqual(PantryUnit.cans.wholeUnitQuantity(0), 0)
    }

    // MARK: - reapplyPantry partial coverage on a countable unit

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

    func testReapplyPartialCoverage_roundsCountableUnitUpInsteadOfFractional() throws {
        // "tart cherry juice" buys by the (1000g) bottle — a non-staple food
        // with a real container conversion, so pantry coverage math can
        // cross grams↔bottles cleanly. 4800g need → ceil(4800/1000) = 5 bottles.
        let plan = makeSingleFoodPlan(context: context, name: "Tart Cherry Juice", grams: 4800)
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let before = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "tart cherry juice" })
        XCTAssertEqual(before.unit, .bottles, "Sanity: generator rounds this food to whole bottles")
        XCTAssertEqual(before.quantity, 5)

        // Pantry holds 3 bottles (3000 g) → 1800 g still needed → buy 2 whole
        // bottles (purchase units round UP; the pantry itself is fractional).
        _ = try pantry.mergeOrCreate(
            rawName: "Tart Cherry Juice", quantity: 3, unit: .bottles, storageLocation: .pantry,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        _ = try grocery.reapplyPantry(pantry)

        let after = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "tart cherry juice" })
        XCTAssertEqual(after.quantity, after.quantity.rounded(), "Shopping quantities stay whole bottles")
        XCTAssertEqual(after.quantity, 2, "1800 g short rounds UP to 2 bottles, never subtracted twice")
    }

    func testAddItem_roundsCountableUnitQuantityUp() throws {
        let plan = makeSingleFoodPlan(context: context, name: "Rice", grams: 200)
        _ = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let item = try grocery.addItem(name: "Sparkling Water", quantity: 2.3, unit: .packs, category: "pantry")
        XCTAssertEqual(item.quantity, 3, "2.3 packs rounds up to 3 whole packs")
    }

    func testAddItem_nonCountableUnitKeepsFraction() throws {
        let plan = makeSingleFoodPlan(context: context, name: "Rice", grams: 200)
        _ = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let item = try grocery.addItem(name: "Milk", quantity: 1.5, unit: .liters, category: "dairy")
        XCTAssertEqual(item.quantity, 1.5, "Weight/volume units keep their fraction")
    }

    private func makeSingleFoodPlan(context: ModelContext, name: String, grams: Double) -> WeeklyMealPlan {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let plan = WeeklyMealPlan(startDate: start, endDate: end)
        context.insert(plan)
        let meal = PlannedMeal(
            dayDate: start, mealNumber: 1, mealName: "Meal 1", scheduledTime: "12:00",
            foods: [PlannedFood(name: name, quantityGrams: grams, calories: 0, proteinG: 0, carbsG: 0, fatG: 0)],
            mealPlan: plan
        )
        context.insert(meal)
        return plan
    }
}
