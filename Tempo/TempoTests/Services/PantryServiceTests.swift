//
// PantryServiceTests.swift
// Tempo
//
// Verifies the LocalPantryService CRUD + merge behavior against an in-memory
// SwiftData container. Round-trip merge semantics (canonical match → quantity
// increment) are the critical contract for Phase 3 receipt ingestion.
//

import SwiftData
@testable import Tempo
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

    // MARK: - Brand merge key (keep two same-foods of different brands separate)

    func testBrand_differentBrandsStaySeparateRows() throws {
        _ = try service.mergeOrCreate(
            rawName: "Butter", quantity: 100, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil,
            brand: "Land O'Lakes"
        )
        _ = try service.mergeOrCreate(
            rawName: "Butter", quantity: 100, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil,
            brand: "Kerrygold"
        )
        XCTAssertEqual(
            try service.fetchAll().count,
            2,
            "Same food + unit but different brand → two separate rows"
        )
    }

    func testBrand_sameBrandMerges() throws {
        _ = try service.mergeOrCreate(
            rawName: "Butter", quantity: 100, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil,
            brand: "Land O'Lakes"
        )
        let merged = try service.mergeOrCreate(
            rawName: "Butter", quantity: 50, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil,
            brand: "Land O'Lakes"
        )
        XCTAssertEqual(try service.fetchAll().count, 1)
        XCTAssertEqual(merged.quantity, 150, "Same brand → merge")
    }

    func testBrand_spellingVarianceMergesViaNormalization() throws {
        // "Galbani", "galbani", "Galbani " all normalize to the same key.
        _ = try service.mergeOrCreate(
            rawName: "Ricotta", quantity: 425, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil,
            brand: "Galbani"
        )
        _ = try service.mergeOrCreate(
            rawName: "Ricotta", quantity: 400, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil,
            brand: "galbani "
        )
        let all = try service.fetchAll()
        XCTAssertEqual(all.count, 1, "Brand spelling variance must merge, not duplicate")
        XCTAssertEqual(all.first?.quantity, 825)
    }

    func testBrand_emptyBrandPreservesScanManualMerge() throws {
        // Scan / manual flows pass no brand. An empty-brand add must still merge
        // into a pre-existing empty-brand row — backward compatibility.
        _ = try service.mergeOrCreate(
            rawName: "Pasta", quantity: 500, unit: .grams, storageLocation: .pantry,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        let merged = try service.mergeOrCreate(
            rawName: "Pasta", quantity: 250, unit: .grams, storageLocation: .pantry,
            purchaseDate: nil, purchaseSource: .receiptScan, sourceReceiptLineItemID: nil
        )
        XCTAssertEqual(
            try service.fetchAll().count,
            1,
            "Empty-brand adds merge exactly as before the brand field existed"
        )
        XCTAssertEqual(merged.quantity, 750)
    }

    func testBrand_brandedDoesNotMergeIntoUnbranded() throws {
        // A generic (empty-brand) row and a branded one of the same food are
        // distinct products → separate rows.
        _ = try service.mergeOrCreate(
            rawName: "Butter", quantity: 100, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        _ = try service.mergeOrCreate(
            rawName: "Butter", quantity: 100, unit: .grams, storageLocation: .fridge,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil,
            brand: "Land O'Lakes"
        )
        XCTAssertEqual(try service.fetchAll().count, 2)
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
            useBy: Date().addingTimeInterval(-86400) // yesterday
        )
        XCTAssertTrue(item.isExpired)
    }

    func testIsExpiringSoon_within3Days() {
        let item = PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams,
            useBy: Date().addingTimeInterval(2 * 86400) // 2 days out
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
            useBy: Date().addingTimeInterval(10 * 86400)
        )
        XCTAssertFalse(item.isExpiringSoon)
    }

    // MARK: - isDepleted

    func testIsDepleted_zeroQuantityNotArchived() {
        let item = PantryItem(canonicalName: "milk", displayName: "Milk", quantity: 0, unit: .liters)
        XCTAssertTrue(item.isDepleted)
    }

    func testIsDepleted_falseWhenArchived() {
        let item = PantryItem(canonicalName: "milk", displayName: "Milk", quantity: 0, unit: .liters, isArchived: true)
        XCTAssertFalse(item.isDepleted, "An archived row is gone, not 'used up' — no chip to show")
    }

    func testIsDepleted_falseWhenStillStocked() {
        let item = PantryItem(canonicalName: "milk", displayName: "Milk", quantity: 1, unit: .liters)
        XCTAssertFalse(item.isDepleted)
    }

    // MARK: - Auto-expiry: add/merge/set paths all populate useBy

    func testAdd_setsUseByFromShelfLifeEstimator() throws {
        let item = PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams,
            storageLocation: .fridge
        )
        try service.add(item)
        XCTAssertNotNil(item.useBy, "add() must populate useBy when the caller didn't set one")
        let days = try Calendar.current.dateComponents([.day], from: Date(), to: XCTUnwrap(item.useBy)).day ?? -1
        XCTAssertEqual(Double(days), 2, accuracy: 1)
    }

    func testMergeOrCreate_setsUseByOnNewRow() throws {
        let item = try service.mergeOrCreate(
            rawName: "rice", quantity: 500, unit: .grams, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        XCTAssertNotNil(item.useBy)
    }

    func testMergeOrCreate_keepsEarliestUseBy() throws {
        // First batch, purchased today → far-future useBy (rice keeps ~2 years).
        let first = try service.mergeOrCreate(
            rawName: "rice", quantity: 500, unit: .grams, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        let earlierUseBy = Date().addingTimeInterval(3 * 86400) // 3 days out — deliberately earlier
        first.useBy = earlierUseBy

        // Second batch merges into the same row (same canonical + unit + brand).
        let merged = try service.mergeOrCreate(
            rawName: "rice", quantity: 200, unit: .grams, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )

        XCTAssertEqual(merged.id, first.id, "Sanity: same row")
        XCTAssertEqual(
            try XCTUnwrap(merged.useBy).timeIntervalSince1970,
            earlierUseBy.timeIntervalSince1970,
            accuracy: 2,
            "Merging must keep the EARLIER of the two use-by dates — the stack spoils as fast as its oldest portion"
        )
    }

    func testSetOrCreate_setsUseByOnNewRow() throws {
        let item = try service.setOrCreate(
            rawName: "pasta", quantity: 500, unit: .grams, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual
        )
        XCTAssertNotNil(item.useBy)
    }

    func testSetOrCreate_doesNotResetExistingUseBy() throws {
        let first = try service.setOrCreate(
            rawName: "pasta", quantity: 500, unit: .grams, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual
        )
        let customUseBy = Date().addingTimeInterval(999 * 86400)
        first.useBy = customUseBy

        let updated = try service.setOrCreate(
            rawName: "pasta", quantity: 300, unit: .grams, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual
        )

        XCTAssertEqual(updated.useBy, customUseBy, "A stock-take on a row with an existing useBy must not reset it")
    }

    // MARK: - updateItem (tap-edit / voice-edit)

    func testUpdateItem_quantityAndUnitChange() throws {
        let item = PantryItem(canonicalName: "flour", displayName: "Flour", quantity: 500, unit: .grams, storageLocation: .pantry)
        try service.add(item)

        _ = try service.updateItem(item, quantity: 1, unit: .kilograms, storageLocation: nil, useBy: nil, brand: nil)

        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.unit, .kilograms)
    }

    func testUpdateItem_locationChangeRecomputesUseBy() throws {
        let item = PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams,
            storageLocation: .fridge
        )
        try service.add(item)
        let fridgeUseBy = try XCTUnwrap(item.useBy)

        _ = try service.updateItem(item, quantity: nil, unit: nil, storageLocation: .freezer, useBy: nil, brand: nil)

        XCTAssertEqual(item.storageLocation, .freezer)
        XCTAssertNotEqual(item.useBy, fridgeUseBy, "Moving to the freezer must recompute useBy from the new location")
        let daysOut = try Calendar.current.dateComponents([.day], from: Date(), to: XCTUnwrap(item.useBy)).day ?? 0
        XCTAssertGreaterThan(daysOut, 30, "Freezer chicken keeps far longer than fridge chicken")
    }

    func testUpdateItem_explicitUseByAlwaysWins() throws {
        let item = PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams,
            storageLocation: .fridge
        )
        try service.add(item)
        let explicitDate = Date().addingTimeInterval(5 * 86400)

        _ = try service.updateItem(item, quantity: nil, unit: nil, storageLocation: .freezer, useBy: explicitDate, brand: nil)

        let useBy = try XCTUnwrap(item.useBy)
        XCTAssertEqual(useBy.timeIntervalSince1970, explicitDate.timeIntervalSince1970, accuracy: 1)
    }

    func testUpdateItem_noLocationChange_leavesUseByAlone() throws {
        let item = PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams,
            storageLocation: .fridge
        )
        try service.add(item)
        let original = try XCTUnwrap(item.useBy)

        _ = try service.updateItem(item, quantity: 300, unit: nil, storageLocation: nil, useBy: nil, brand: nil)

        XCTAssertEqual(item.useBy, original, "No location change + no explicit useBy → useBy must be untouched")
        XCTAssertEqual(item.quantity, 300)
    }
}
