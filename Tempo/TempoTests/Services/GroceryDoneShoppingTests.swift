//
// GroceryDoneShoppingTests.swift
// Tempo
//
// BUILD item 3: "Done shopping" pushes checked items into the pantry (via
// the EXISTING pantry service — so Lane B's expiry estimation on the add
// path runs same as any other add), writes a PantryPriceEntry when a price
// was given, and marks the grocery item bought (kept as a record, not
// deleted) rather than removed. This exercises the same service calls
// NutritionTabViewModel+GroceryAdvanced.confirmGroceryBought makes, at the
// service level (no APIClient/ServiceContainer needed).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GroceryDoneShoppingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var grocery: LocalGroceryListService!
    private var pantry: LocalPantryService!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: GroceryList.self, GroceryListItem.self, WeeklyMealPlan.self,
            PlannedMeal.self, PantryItem.self, PantryPriceEntry.self,
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

    private func makePlan(foods: [(String, Double)]) -> WeeklyMealPlan {
        let start = Calendar.current.startOfDay(for: Date())
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

    /// Mirrors `NutritionTabViewModel.confirmGroceryBought`'s core sequence
    /// without needing the full ViewModel/APIClient stack.
    private func confirm(
        item: GroceryListItem,
        quantity: Double,
        unit: PantryUnit,
        storage: PantryStorageLocation,
        paidUSD: Double?,
        store: String? = "Publix"
    ) throws {
        // Mirrors the production fix in NutritionTabViewModel+GroceryAdvanced:
        // pass the CANONICAL name, not the friendly grocery-list displayName
        // ("2 fillets salmon"), which FoodCanonicalizer can't reduce back down.
        let pantryItem = try pantry.mergeOrCreate(
            rawName: item.canonicalFoodName, quantity: quantity, unit: unit, storageLocation: storage,
            purchaseDate: Date(), purchaseSource: .groceryConfirm, sourceReceiptLineItemID: nil, brand: ""
        )
        if let paidUSD, paidUSD > 0 {
            let entry = PantryPriceEntry(
                canonicalFoodName: pantryItem.canonicalName, displayName: pantryItem.displayName,
                purchaseDate: Date(), totalPaidUSD: paidUSD, quantity: quantity, unit: unit,
                source: .groceryConfirm, store: store
            )
            context.insert(entry)
        }
        try context.save()
        try grocery.markBought([item], boughtAt: Date())
    }

    func testConfirm_addsPantryItemWithGroceryConfirmSource() throws {
        let plan = makePlan(foods: [("Salmon", 300)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let salmon = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "salmon" })
        // Regression guard: salmon has a naturalPortions purchase-unit entry,
        // so its grocery-list displayName is a friendly "N fillets salmon"
        // string — NOT just "Salmon". Confirming must resolve back to the
        // canonical pantry name regardless.
        XCTAssertTrue(
            salmon.displayName.lowercased().contains("fillet"),
            "test assumption: salmon's display should embed the purchase unit"
        )

        try confirm(item: salmon, quantity: salmon.quantity, unit: salmon.unit, storage: .fridge, paidUSD: nil)

        let pantryItems = try pantry.fetchAll()
        let added = try XCTUnwrap(pantryItems.first { $0.canonicalName == "salmon" })
        XCTAssertEqual(added.purchaseSource, .groceryConfirm)
        XCTAssertEqual(added.storageLocation, .fridge)
    }

    func testConfirm_writesPriceEntryWhenPriceGiven() throws {
        let plan = makePlan(foods: [("Rice", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let rice = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "rice" })

        try confirm(item: rice, quantity: rice.quantity, unit: rice.unit, storage: .pantry, paidUSD: 4.5, store: "Publix")

        let entries = try context.fetch(FetchDescriptor<PantryPriceEntry>())
        let entry = try XCTUnwrap(entries.first { $0.canonicalFoodName == "rice" })
        XCTAssertEqual(entry.totalPaidUSD, 4.5)
        XCTAssertEqual(entry.store, "Publix")
        XCTAssertEqual(entry.source, .groceryConfirm)
    }

    func testConfirm_noPriceGiven_writesNoPriceEntry() throws {
        let plan = makePlan(foods: [("Rice", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let rice = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "rice" })

        try confirm(item: rice, quantity: rice.quantity, unit: rice.unit, storage: .pantry, paidUSD: nil)

        let entries = try context.fetch(FetchDescriptor<PantryPriceEntry>())
        XCTAssertTrue(entries.isEmpty)
    }

    func testConfirm_marksGroceryItemBoughtButKeepsItAsRecord() throws {
        let plan = makePlan(foods: [("Rice", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let rice = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "rice" })

        try confirm(item: rice, quantity: rice.quantity, unit: rice.unit, storage: .pantry, paidUSD: nil)

        XCTAssertTrue(rice.isBought)
        XCTAssertNotNil(rice.boughtAt)
        // Kept as a record — NOT deleted — but excluded from the active list.
        XCTAssertTrue(list.orderedItems.contains { $0.id == rice.id })
        XCTAssertFalse(list.activeItems.contains { $0.id == rice.id })
        XCTAssertTrue(list.boughtItems.contains { $0.id == rice.id })
    }

    func testConfirm_thenRegenerate_boughtItemDropsOffNaturallyViaPantryDeduction() throws {
        // Once bought → in the pantry, a regenerate should no longer ask to
        // buy it again (the normal pantry-subtraction path handles this).
        // A second, untouched food ("Chicken Breast") keeps the aggregated
        // list non-empty after rice drops off, so this exercises "one item
        // covered, one still needed" rather than tripping the unrelated
        // "nothing left to shop for at all" empty-plan error.
        let plan = makePlan(foods: [("Rice", 200), ("Chicken Breast", 200)])
        let list = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        let rice = try XCTUnwrap(list.orderedItems.first { $0.canonicalFoodName == "rice" })
        try confirm(item: rice, quantity: rice.quantity, unit: rice.unit, storage: .pantry, paidUSD: nil)

        let regenerated = try grocery.generate(from: plan, pantry: pantry, weekStartDate: plan.startDate)
        XCTAssertFalse(
            regenerated.activeItems.contains { $0.canonicalFoodName == "rice" },
            "Rice is now in the pantry — pantry subtraction should cover the need"
        )
    }
}
