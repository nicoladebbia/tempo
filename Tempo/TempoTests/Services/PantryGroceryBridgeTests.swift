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
        // Keyed by this week's Monday — the same key the plan-driven
        // generate uses (plan.startDate), so a later regenerate merges into
        // this list instead of creating a second one.
        XCTAssertEqual(lists.first?.weekStartDate, PantryGroceryBridge.currentWeekMonday())
        XCTAssertEqual(item.canonicalFoodName, "rice")
        XCTAssertEqual(item.category, PantryGroceryBridge.category)
        XCTAssertTrue(item.isManual, "Pantry-driven needs must survive a plan regenerate")
    }

    func testAddToCurrentGroceryList_reusesThisWeeksList() throws {
        let existingList = GroceryList(weekStartDate: PantryGroceryBridge.currentWeekMonday(), sourceMealPlanID: nil)
        context.insert(existingList)
        try context.save()

        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .pieces, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.count, 1, "Must land on this week's list, not create a second one")
        XCTAssertEqual(lists.first?.items?.count, 1)
    }

    func testAddToCurrentGroceryList_startsThisWeeksListWhenOnlyAnOldOneExists() throws {
        let lastWeek = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -7, to: PantryGroceryBridge.currentWeekMonday()))
        let oldList = GroceryList(weekStartDate: lastWeek, sourceMealPlanID: nil)
        context.insert(oldList)
        try context.save()

        _ = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .pieces, modelContext: context
        )

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(oldList.items?.count ?? 0, 0, "Last week's list stays as it was")
        let current = try XCTUnwrap(lists.first { $0.weekStartDate == PantryGroceryBridge.currentWeekMonday() })
        XCTAssertEqual(current.items?.count, 1)
    }

    func testAddToCurrentGroceryList_reopensAnItemBoughtOnAnEarlierTrip() throws {
        let first = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 2, unit: .pieces, modelContext: context
        )
        first.isChecked = true
        first.isBought = true
        first.boughtAt = Date()

        let again = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .pieces, modelContext: context
        )

        XCTAssertTrue(again === first)
        XCTAssertFalse(again.isBought)
        XCTAssertFalse(again.isChecked)
        XCTAssertNil(again.boughtAt)
        XCTAssertEqual(again.quantity, 1, "A fresh need, not added to what was already bought")
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
