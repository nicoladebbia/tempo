//
// GroceryReapplyTests.swift
// Tempo
//
// The grocery↔pantry loop: after you shop and the bought items land in the
// pantry (via receipt scan / voice / manual add), the active grocery list must
// shrink — items you now have drop off "to buy". This is `reapplyPantry`, now
// auto-fired from every pantry-entry path. These pin its contract:
//   - a fully-covered item is removed,
//   - an item you already CHECKED OFF (in your cart) is preserved,
//   - a partially-covered item shrinks to the remainder.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GroceryReapplyTests: XCTestCase {
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

    /// Build a one-meal plan needing the given foods (grams), persisted.
    private func makePlan(_ foods: [(String, Double)]) -> WeeklyMealPlan {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let plan = WeeklyMealPlan(startDate: start, endDate: end)
        context.insert(plan)
        let meal = PlannedMeal(
            dayDate: start, mealNumber: 1, mealName: "Meal 1", scheduledTime: "12:00",
            foods: foods.map {
                PlannedFood(name: $0.0, quantityGrams: $0.1, calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
            },
            mealPlan: plan
        )
        context.insert(meal)
        return plan
    }

    func testReapply_dropsItemNowInPantry() throws {
        // Use grams on both sides so the coverage math is unit-clean. (The
        // generator can normalize a grocery item into purchase units like
        // "pieces"; cross-unit coverage relies on FoodMacroDatabase portion
        // data and is exercised by the real flow — here we isolate the loop.)
        let plan = makePlan([("Oats", 600), ("Rice", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: Date())
        let oatsBefore = list.orderedItems.first { $0.canonicalFoodName == "oats" }
        XCTAssertNotNil(oatsBefore, "Oats needed initially")

        // You shopped → enough oats now in the pantry to fully cover the need.
        _ = try pantry.mergeOrCreate(
            rawName: "Oats", quantity: oatsBefore!.quantity, unit: oatsBefore!.unit,
            storageLocation: .pantry,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        let removed = try grocery.reapplyPantry(pantry)

        XCTAssertEqual(removed, 1, "Oats now fully on hand → drops off the list")
        XCTAssertFalse(list.orderedItems.contains { $0.canonicalFoodName == "oats" })
    }

    func testReapply_preservesCheckedItems() throws {
        let plan = makePlan([("Salmon", 300)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: Date())
        let salmon = try XCTUnwrap(list.orderedItems.first)

        // You ticked salmon off in the store (it's in your cart).
        try grocery.toggleChecked(salmon)
        XCTAssertTrue(salmon.isChecked)

        // Even though it's not yet in the pantry, a reapply must NOT delete a
        // checked item — it's part of the current trip.
        let removed = try grocery.reapplyPantry(pantry)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(list.orderedItems.count, 1, "Checked item preserved")
    }

    func testReapply_partialCoverageShrinks() throws {
        let plan = makePlan([("Oats", 500)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: Date())

        _ = try pantry.mergeOrCreate(
            rawName: "Oats", quantity: 200, unit: .grams, storageLocation: .pantry,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        let removed = try grocery.reapplyPantry(pantry)

        XCTAssertEqual(removed, 0, "Partially covered → shrunk, not removed")
        let oats = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "oats" })
        XCTAssertEqual(oats.quantity, 300, accuracy: 1, "500 needed − 200 on hand = 300 to buy")
    }
}
