//
// VoicePantryEditApplierTests.swift
// Tempo
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class VoicePantryEditApplierTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    private var pantryService: LocalPantryService!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PantryItem.self, GroceryList.self, GroceryListItem.self,
            configurations: config
        )
        pantryService = LocalPantryService(modelContext: context)
    }

    override func tearDown() async throws {
        pantryService = nil
        container = nil
        try await super.tearDown()
    }

    @discardableResult
    private func insert(
        _ canonicalName: String, quantity: Double, brand: String = "",
        useBy: Date? = nil, unit: PantryUnit = .grams
    ) -> PantryItem {
        let item = PantryItem(
            canonicalName: canonicalName, displayName: canonicalName.capitalized,
            brand: brand, quantity: quantity, unit: unit, useBy: useBy
        )
        context.insert(item)
        try? context.save()
        return item
    }

    // MARK: - markDepleted

    func testMarkDepleted_zeroesMatchingRowAndAddsToGroceryList() throws {
        insert("rice", quantity: 500)

        let results = VoicePantryEditApplier.apply(
            [.markDepleted(rawName: "rice")], pantryService: pantryService, modelContext: context
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].succeeded)
        XCTAssertTrue(results[0].summary.contains("added to grocery list"))

        let remaining = try pantryService.fetchAll()
        XCTAssertEqual(remaining.first?.quantity, 0)

        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        let items = lists.first?.items ?? []
        XCTAssertTrue(items.contains { $0.canonicalFoodName == "rice" })
    }

    func testMarkDepleted_zeroesAllBrandDuplicateRows() throws {
        insert("butter", quantity: 100, brand: "brandA")
        insert("butter", quantity: 50, brand: "brandB")

        let results = VoicePantryEditApplier.apply(
            [.markDepleted(rawName: "butter")], pantryService: pantryService, modelContext: context
        )

        XCTAssertTrue(results[0].succeeded)
        let remaining = try pantryService.fetchAll()
        XCTAssertTrue(remaining.allSatisfy { $0.quantity == 0 })
    }

    func testMarkDepleted_noExistingRow_stillSucceedsAndAddsToList() throws {
        let results = VoicePantryEditApplier.apply(
            [.markDepleted(rawName: "eggs")], pantryService: pantryService, modelContext: context
        )

        XCTAssertTrue(results[0].succeeded)
        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertTrue((lists.first?.items ?? []).contains { $0.canonicalFoodName == "eggs" })
    }

    // MARK: - decrement

    func testDecrement_fullFraction_zeroesRow() throws {
        insert("chicken breast", quantity: 400)

        let results = VoicePantryEditApplier.apply(
            [.decrement(rawName: "chicken breast", fraction: 1.0)], pantryService: pantryService, modelContext: context
        )

        XCTAssertTrue(results[0].succeeded)
        XCTAssertTrue(results[0].summary.contains("Used up"))
        XCTAssertEqual(try pantryService.fetchAll().first?.quantity, 0)
    }

    func testDecrement_halfFraction_removesHalfOfTotalFIFO() {
        let soon = insert("rice", quantity: 200, useBy: Date().addingTimeInterval(1 * 86400))
        let later = insert("rice", quantity: 200, useBy: Date().addingTimeInterval(30 * 86400))

        // Total 400g, half = 200g removed, FIFO drains the soon-expiring row first.
        let results = VoicePantryEditApplier.apply(
            [.decrement(rawName: "rice", fraction: 0.5)], pantryService: pantryService, modelContext: context
        )

        XCTAssertTrue(results[0].succeeded)
        XCTAssertTrue(results[0].summary.contains("Used some"))
        XCTAssertEqual(soon.quantity, 0)
        XCTAssertEqual(later.quantity, 200)
    }

    func testDecrement_notFound_fails() {
        let results = VoicePantryEditApplier.apply(
            [.decrement(rawName: "quinoa", fraction: 1.0)], pantryService: pantryService, modelContext: context
        )

        XCTAssertFalse(results[0].succeeded)
        XCTAssertTrue(results[0].summary.contains("Couldn't find"))
    }

    // MARK: - move

    func testMove_changesLocationForAllMatchingRows() throws {
        insert("chicken breast", quantity: 300, brand: "brandA")
        insert("chicken breast", quantity: 100, brand: "brandB")

        let results = VoicePantryEditApplier.apply(
            [.move(rawName: "chicken breast", location: .freezer)], pantryService: pantryService, modelContext: context
        )

        XCTAssertTrue(results[0].succeeded)
        let rows = try pantryService.fetchAll()
        XCTAssertTrue(rows.allSatisfy { $0.storageLocation == .freezer })
    }

    func testMove_notFound_fails() {
        let results = VoicePantryEditApplier.apply(
            [.move(rawName: "quinoa", location: .freezer)], pantryService: pantryService, modelContext: context
        )
        XCTAssertFalse(results[0].succeeded)
    }

    // MARK: - discard

    func testDiscard_archivesMatchingRows() throws {
        insert("spinach", quantity: 100)

        let results = VoicePantryEditApplier.apply(
            [.discard(rawName: "spinach")], pantryService: pantryService, modelContext: context
        )

        XCTAssertTrue(results[0].succeeded)
        XCTAssertTrue(results[0].summary.contains("Threw out"))
        XCTAssertTrue(try pantryService.fetchAll().isEmpty, "Archived rows are excluded from fetchAll")
    }

    func testDiscard_notFound_fails() {
        let results = VoicePantryEditApplier.apply(
            [.discard(rawName: "quinoa")], pantryService: pantryService, modelContext: context
        )
        XCTAssertFalse(results[0].succeeded)
    }

    // MARK: - Multiple intents

    func testApply_multipleIntents_returnsOneResultPerIntent() {
        insert("rice", quantity: 200)
        insert("chicken breast", quantity: 300)

        let results = VoicePantryEditApplier.apply(
            [.markDepleted(rawName: "rice"), .move(rawName: "chicken breast", location: .freezer)],
            pantryService: pantryService, modelContext: context
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy(\.succeeded))
    }
}
