//
// PantryShelfLifeBackfillServiceTests.swift
// Tempo
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PantryShelfLifeBackfillServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PantryItem.self, configurations: config)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testBackfill_setsUseByFromPurchaseDate() throws {
        let purchaseDate = Date().addingTimeInterval(-2 * 86400) // bought 2 days ago
        let item = PantryItem(
            canonicalName: "chicken breast", displayName: "Chicken Breast",
            quantity: 400, unit: .grams, storageLocation: .fridge,
            purchaseDate: purchaseDate, useBy: nil
        )
        context.insert(item)
        try context.save()

        let updated = PantryShelfLifeBackfillService.run(modelContext: context)

        XCTAssertEqual(updated, 1)
        let expected = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: purchaseDate))
        XCTAssertEqual(try XCTUnwrap(item.useBy).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testBackfill_fallsBackToCreatedAtWhenNoPurchaseDate() throws {
        let item = PantryItem(
            canonicalName: "rice", displayName: "Rice", quantity: 500, unit: .grams,
            storageLocation: .pantry, purchaseDate: nil, useBy: nil
        )
        context.insert(item)
        try context.save()

        _ = PantryShelfLifeBackfillService.run(modelContext: context)

        XCTAssertNotNil(item.useBy)
    }

    func testBackfill_skipsRowsThatAlreadyHaveUseBy() throws {
        let customDate = Date().addingTimeInterval(999 * 86400)
        let item = PantryItem(
            canonicalName: "rice", displayName: "Rice", quantity: 500, unit: .grams,
            storageLocation: .pantry, useBy: customDate
        )
        context.insert(item)
        try context.save()

        let updated = PantryShelfLifeBackfillService.run(modelContext: context)

        XCTAssertEqual(updated, 0, "Idempotent: rows with a useBy already set must be untouched")
        XCTAssertEqual(item.useBy, customDate)
    }

    func testBackfill_skipsArchivedRows() throws {
        let item = PantryItem(
            canonicalName: "rice", displayName: "Rice", quantity: 0, unit: .grams,
            storageLocation: .pantry, useBy: nil, isArchived: true
        )
        context.insert(item)
        try context.save()

        let updated = PantryShelfLifeBackfillService.run(modelContext: context)

        XCTAssertEqual(updated, 0)
        XCTAssertNil(item.useBy)
    }

    func testBackfill_returnsZeroWhenNothingToDo() {
        XCTAssertEqual(PantryShelfLifeBackfillService.run(modelContext: context), 0)
    }
}
