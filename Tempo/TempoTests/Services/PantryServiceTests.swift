//
// PantryServiceTests.swift
// Tempo
//
// Verifies the LocalPantryService CRUD + merge behavior against an in-memory
// SwiftData container. Round-trip merge semantics (canonical match → quantity
// increment) are the critical contract for Phase 3 receipt ingestion.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class PantryServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: LocalPantryService!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PantryItem.self, configurations: config)
        service = LocalPantryService(modelContext: container.mainContext)
    }

    override func tearDown() async throws {
        service = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Add + Fetch

    func testAddAndFetchAll() throws {
        let chicken = PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 500,
            unit: .grams,
            storageLocation: .fridge
        )
        try service.add(chicken)

        let all = try service.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.canonicalName, "chicken breast")
        XCTAssertEqual(all.first?.quantity, 500)
    }

    func testFetchInLocation_filtersByStorageLocation() throws {
        let salmon = PantryItem(
            canonicalName: "salmon",
            displayName: "Salmon",
            quantity: 200,
            unit: .grams,
            storageLocation: .freezer
        )
        let rice = PantryItem(
            canonicalName: "rice",
            displayName: "Rice",
            quantity: 1000,
            unit: .grams,
            storageLocation: .pantry
        )
        try service.add(salmon)
        try service.add(rice)

        let frozen = try service.fetch(in: .freezer)
        XCTAssertEqual(frozen.count, 1)
        XCTAssertEqual(frozen.first?.canonicalName, "salmon")

        let pantry = try service.fetch(in: .pantry)
        XCTAssertEqual(pantry.count, 1)
        XCTAssertEqual(pantry.first?.canonicalName, "rice")
    }

    func testFind_byCanonicalName() throws {
        let item = PantryItem(
            canonicalName: "oats",
            displayName: "Oats",
            quantity: 500,
            unit: .grams
        )
        try service.add(item)

        let found = try service.find(canonicalName: "oats")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, item.id)

        let missing = try service.find(canonicalName: "quinoa")
        XCTAssertNil(missing)
    }

    // MARK: - mergeOrCreate

    func testMergeOrCreate_createsWhenAbsent() throws {
        let item = try service.mergeOrCreate(
            rawName: "Atlantic Salmon Fillet",
            quantity: 400,
            unit: .grams,
            storageLocation: .freezer,
            purchaseDate: Date(),
            purchaseSource: .receiptScan,
            sourceReceiptLineItemID: UUID()
        )
        XCTAssertEqual(item.canonicalName, "salmon")
        XCTAssertEqual(item.quantity, 400)
        XCTAssertEqual(item.purchaseSource, .receiptScan)
        XCTAssertEqual(try service.fetchAll().count, 1)
    }

    func testMergeOrCreate_mergesByCanonicalName() throws {
        // First receipt: 400g salmon (Atlantic Salmon Fillet → canonical "salmon").
        _ = try service.mergeOrCreate(
            rawName: "Atlantic Salmon Fillet",
            quantity: 400,
            unit: .grams,
            storageLocation: .freezer,
            purchaseDate: nil,
            purchaseSource: .receiptScan,
            sourceReceiptLineItemID: nil
        )
        // Second receipt a week later: 250g "Salmon" → must merge, not duplicate.
        let merged = try service.mergeOrCreate(
            rawName: "Salmon",
            quantity: 250,
            unit: .grams,
            storageLocation: .freezer,
            purchaseDate: nil,
            purchaseSource: .receiptScan,
            sourceReceiptLineItemID: nil
        )

        XCTAssertEqual(merged.quantity, 650)
        XCTAssertEqual(try service.fetchAll().count, 1)
    }

    func testMergeOrCreate_doesNotMergeAcrossUnits() throws {
        _ = try service.mergeOrCreate(
            rawName: "Olive Oil",
            quantity: 500,
            unit: .milliliters,
            storageLocation: .pantry,
            purchaseDate: nil,
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil
        )
        // Same canonical "olive oil" but liters — must NOT merge, different unit.
        _ = try service.mergeOrCreate(
            rawName: "Extra Virgin Olive Oil",
            quantity: 1,
            unit: .liters,
            storageLocation: .pantry,
            purchaseDate: nil,
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil
        )

        XCTAssertEqual(try service.fetchAll().count, 2)
    }

    func testMergeOrCreate_upgradesManualToReceiptScan() throws {
        let manual = try service.mergeOrCreate(
            rawName: "Greek Yogurt",
            quantity: 500,
            unit: .grams,
            storageLocation: .fridge,
            purchaseDate: nil,
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil
        )
        XCTAssertEqual(manual.purchaseSource, .manual)

        _ = try service.mergeOrCreate(
            rawName: "Yogurt Greco",
            quantity: 300,
            unit: .grams,
            storageLocation: .fridge,
            purchaseDate: nil,
            purchaseSource: .receiptScan,
            sourceReceiptLineItemID: UUID()
        )

        let all = try service.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.purchaseSource, .receiptScan)
        XCTAssertEqual(all.first?.quantity, 800)
    }

    // MARK: - setOrCreate (voice stock-take SET path)

    func testSetOrCreate_createsWhenAbsent() throws {
        let item = try service.setOrCreate(
            rawName: "Spaghetti",
            quantity: 750,
            unit: .grams,
            storageLocation: .pantry,
            purchaseDate: Date(),
            purchaseSource: .manual
        )
        XCTAssertEqual(item.quantity, 750)
        XCTAssertEqual(try service.fetchAll().count, 1)
    }

    func testSetOrCreate_replacesQuantityNotIncrements() throws {
        // Existing tracked stock: 1000 g of spaghetti.
        _ = try service.mergeOrCreate(
            rawName: "Spaghetti",
            quantity: 1000,
            unit: .grams,
            storageLocation: .pantry,
            purchaseDate: nil,
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil
        )
        // Voice stock-take: "I have 750 g of spaghetti" → REPLACE, not +750.
        let set = try service.setOrCreate(
            rawName: "Spaghetti",
            quantity: 750,
            unit: .grams,
            storageLocation: .pantry,
            purchaseDate: nil,
            purchaseSource: .manual
        )
        XCTAssertEqual(set.quantity, 750, "SET must REPLACE the quantity, not add to it")
        XCTAssertEqual(try service.fetchAll().count, 1, "Same canonical+unit → one row, not a duplicate")
    }

    func testSetOrCreate_doesNotTouchAcrossUnits() throws {
        // 2 packs of spaghetti tracked.
        _ = try service.mergeOrCreate(
            rawName: "Spaghetti",
            quantity: 2,
            unit: .packs,
            storageLocation: .pantry,
            purchaseDate: nil,
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil
        )
        // Voice SET in grams must NOT overwrite the packs row — different unit,
        // different dimension. Creates a separate grams row instead.
        let set = try service.setOrCreate(
            rawName: "Spaghetti",
            quantity: 750,
            unit: .grams,
            storageLocation: .pantry,
            purchaseDate: nil,
            purchaseSource: .manual
        )
        let all = try service.fetchAll()
        XCTAssertEqual(all.count, 2, "grams SET must not collapse into the packs row")
        XCTAssertEqual(set.unit, .grams)
        // The original packs row is untouched.
        let packsRow = all.first { $0.unit == .packs }
        XCTAssertEqual(packsRow?.quantity, 2)
    }

    func testSetOrCreate_floorsNegativeAtZero() throws {
        let item = try service.setOrCreate(
            rawName: "Rice",
            quantity: -50,
            unit: .grams,
            storageLocation: .pantry,
            purchaseDate: nil,
            purchaseSource: .manual
        )
        XCTAssertEqual(item.quantity, 0, "A negative SET quantity floors at zero")
    }

    // MARK: - Quantity adjustments

    func testAdjustQuantity_floorsAtZero() throws {
        let item = try service.mergeOrCreate(
            rawName: "Eggs",
            quantity: 6,
            unit: .pieces,
            storageLocation: .fridge,
            purchaseDate: nil,
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil
        )
        try service.adjustQuantity(of: item, by: -10)
        XCTAssertEqual(item.quantity, 0)
    }

    // MARK: - Archive + Delete

    func testArchive_excludesFromFetchAll() throws {
        let item = PantryItem(
            canonicalName: "honey",
            displayName: "Honey",
            quantity: 250,
            unit: .grams
        )
        try service.add(item)
        XCTAssertEqual(try service.fetchAll().count, 1)

        try service.archive(item)
        XCTAssertEqual(try service.fetchAll().count, 0)
        XCTAssertTrue(item.isArchived)
    }

    func testDelete_removesFromStore() throws {
        let item = PantryItem(
            canonicalName: "berries",
            displayName: "Berries",
            quantity: 300,
            unit: .grams,
            storageLocation: .freezer
        )
        try service.add(item)
        XCTAssertEqual(try service.fetchAll().count, 1)

        try service.delete(item)
        XCTAssertEqual(try service.fetchAll().count, 0)
    }

    // MARK: - Expiry computed properties

    func testIsExpired_pastDate() {
        let item = PantryItem(
            canonicalName: "milk",
            displayName: "Milk",
            quantity: 1,
            unit: .liters,
            useBy: Date().addingTimeInterval(-86_400) // yesterday
        )
        XCTAssertTrue(item.isExpired)
    }

    func testIsExpiringSoon_within3Days() {
        let item = PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams,
            useBy: Date().addingTimeInterval(2 * 86_400) // 2 days out
        )
        XCTAssertTrue(item.isExpiringSoon)
        XCTAssertFalse(item.isExpired)
    }

    func testIsExpiringSoon_outsideWindow() {
        let item = PantryItem(
            canonicalName: "rice",
            displayName: "Rice",
            quantity: 1000,
            unit: .grams,
            useBy: Date().addingTimeInterval(10 * 86_400)
        )
        XCTAssertFalse(item.isExpiringSoon)
    }
}
