//
// GroceryPreservationTests.swift
// Tempo
//
// BUILD item 1b: regenerating the grocery list for a week must PRESERVE the
// user's ticks (by canonical name) and manually-added items — otherwise every
// "add a new meal to the plan" mid-week wipes out the trip in progress.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GroceryPreservationTests: XCTestCase {
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

    private func makePlan(startDate: Date = Date(), foods: [(String, Double)]) -> WeeklyMealPlan {
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

    func testRegenerate_preservesCheckedState_forItemsStillNeeded() throws {
        let plan = makePlan(foods: [("Salmon", 300), ("Rice", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let salmon = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "salmon" })
        try grocery.toggleChecked(salmon)
        XCTAssertTrue(salmon.isChecked)

        // Regenerate the SAME week (e.g. the plan got a new meal added).
        let regenerated = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)

        let salmonAfter = try XCTUnwrap(regenerated.orderedItems.first { $0.canonicalFoodName == "salmon" })
        XCTAssertTrue(salmonAfter.isChecked, "Tick must survive a regenerate")
    }

    func testRegenerate_preservesManualItem() throws {
        let plan = makePlan(foods: [("Rice", 200)])
        _ = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        _ = try grocery.addItem(name: "Olive Oil", quantity: 1, unit: .bottles, category: "oils")

        let regenerated = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)

        let manual = regenerated.orderedItems.first { $0.canonicalFoodName == "olive oil" }
        XCTAssertNotNil(manual, "Manually-added item must survive a regenerate")
        XCTAssertTrue(manual?.isManual == true)
    }

    func testRegenerate_manualItemSurvivesEvenWhenPlanBecomesEmptyOfNewItems() throws {
        // Edge case: a plan whose aggregation is entirely covered by pantry
        // (aggregated == []) must still keep manual items instead of
        // throwing "no meals to shop" and wiping the list.
        let plan = makePlan(foods: [("Rice", 200)])
        _ = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        _ = try grocery.addItem(name: "Paper Towels", quantity: 1, unit: .packs, category: "pantry")

        _ = try pantry.mergeOrCreate(
            rawName: "Rice", quantity: 1000, unit: .grams, storageLocation: .pantry,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil
        )

        let regenerated = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        XCTAssertTrue(regenerated.orderedItems.contains { $0.canonicalFoodName == "paper towels" })
    }

    func testAddItem_marksItemManual() throws {
        let plan = makePlan(foods: [("Rice", 200)])
        _ = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let item = try grocery.addItem(name: "Napkins", quantity: 1, unit: .packs, category: "pantry")
        XCTAssertTrue(item.isManual)
    }

    func testGeneratedItem_isNotManual() throws {
        let plan = makePlan(foods: [("Rice", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let rice = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "rice" })
        XCTAssertFalse(rice.isManual)
    }

    func testRegenerate_preservesBoughtStateAndReminderIdentifier() throws {
        let plan = makePlan(foods: [("Rice", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let rice = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "rice" })
        rice.reminderIdentifier = "fake-identifier-123"
        try grocery.markBought([rice], boughtAt: Date())

        let regenerated = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let riceAfter = try XCTUnwrap(regenerated.orderedItems.first { $0.canonicalFoodName == "rice" })
        XCTAssertTrue(riceAfter.isBought)
        XCTAssertEqual(riceAfter.reminderIdentifier, "fake-identifier-123")
    }
}
