//
// PantryGroceryBridgeTests.swift
// Tempo
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PantryGroceryBridgeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: GroceryList.self, GroceryListItem.self, configurations: config)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testAddToCurrentGroceryList_createsListWhenNoneExistsForCurrentWeek() throws {
        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryList>()).isEmpty)

        let item = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .pieces, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.count, 1)
        // A brand-new fallback list is dated to TODAY — matching exactly the
        // convention `NutritionTabViewModel+Phase7.generateGroceryList` uses
        // (`Calendar.startOfDay(for: Date())`), NOT the Monday-of-week key.
        // Using a different convention here would mean a list the pantry
        // creates today never gets found/reused by a later real generation.
        XCTAssertEqual(lists.first?.weekStartDate, Calendar.current.startOfDay(for: Date()))
        XCTAssertEqual(item.canonicalFoodName, "rice")
        XCTAssertEqual(item.category, PantryGroceryBridge.category)
    }

    /// Regression test: `LocalGroceryListService.generate(weekStartDate:)`
    /// keys a list by whatever day the user tapped "Generate" — which is
    /// almost never a Monday. `PantryGroceryBridge` must find and reuse
    /// THAT list (the one the Grocery tab actually shows via `fetchLatest()`
    /// — most recent `weekStartDate`), not independently derive a
    /// Monday-of-week key and silently create a second, orphaned list.
    func testAddToCurrentGroceryList_reusesExistingListDatedToAnArbitraryDay() throws {
        // Simulate a list generated on, say, a Wednesday — exactly how
        // `generateGroceryList` creates one (today's start-of-day, not the
        // Monday of the week).
        let wednesday = Calendar.current.startOfDay(for: Date())
        let existingList = GroceryList(weekStartDate: wednesday, sourceMealPlanID: nil)
        context.insert(existingList)
        try context.save()

        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .pieces, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.count, 1, "Must land on the existing list, not create a second Monday-dated one")
        XCTAssertEqual(lists.first?.items?.count, 1)
    }

    /// When multiple lists exist (e.g. an older, previous week's list still
    /// around), the pantry add must land on the MOST RECENT one — the same
    /// list `fetchLatest()` (and therefore the Grocery tab) surfaces.
    func testAddToCurrentGroceryList_picksMostRecentListWhenSeveralExist() throws {
        let older = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -10, to: Date()))
        let oldList = GroceryList(weekStartDate: older, sourceMealPlanID: nil)
        context.insert(oldList)
        let newer = Calendar.current.startOfDay(for: Date())
        let newList = GroceryList(weekStartDate: newer, sourceMealPlanID: nil)
        context.insert(newList)
        try context.save()

        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .pieces, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.count, 2, "No new list should be created — an existing one was found")
        XCTAssertEqual(newList.items?.count, 1, "The item must land on the MOST RECENT list")
        XCTAssertEqual(oldList.items?.count ?? 0, 0)
    }

    func testAddToCurrentGroceryList_reusesExistingListForCurrentWeek() throws {
        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .pieces, modelContext: context
        )
        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "olive oil", displayName: "Olive oil", quantity: 1, unit: .pieces, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.count, 1, "Both adds should land in the same week's list")
        XCTAssertEqual(lists.first?.items?.count, 2)
    }

    func testAddToCurrentGroceryList_bumpsQuantityForExistingMatchingItem() throws {
        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 2, unit: .pieces, modelContext: context
        )
        let bumped = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 3, unit: .pieces, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.first?.items?.count, 1, "Same canonical name + unit bumps rather than duplicates")
        XCTAssertEqual(bumped.quantity, 5)
    }

    func testAddToCurrentGroceryList_sameNameDifferentUnit_createsSeparateRow() throws {
        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 2, unit: .pieces, modelContext: context
        )
        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 500, unit: .grams, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.first?.items?.count, 2)
    }

    func testCurrentWeekMonday_isStableWithinTheSameWeek() {
        let monday = PantryGroceryBridge.currentWeekMonday()
        let weekday = Calendar.current.component(.weekday, from: monday)
        XCTAssertEqual(weekday, 2, "Monday is weekday 2 in the Gregorian calendar (Sunday = 1)")
    }
}
