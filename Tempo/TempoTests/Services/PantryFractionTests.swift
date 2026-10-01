//
// PantryFractionTests.swift
// Tempo
//
// Round 1 (Lane C): container/count pantry rows are tracked in FRACTIONS.
// 1 pack of 500 g minus 100 g eaten = 0.8 pack, never an emptied pack.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PantryFractionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    @discardableResult
    private func insert(_ name: String, _ quantity: Double, _ unit: PantryUnit) -> PantryItem {
        let item = PantryItem(canonicalName: name, displayName: name.capitalized, quantity: quantity, unit: unit)
        context.insert(item)
        try? context.save()
        return item
    }

    private func food(_ name: String, _ grams: Double) -> PlannedFood {
        PlannedFood(name: name, quantityGrams: grams, calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }

    func testPackDecrementIsFractional() {
        let pasta = insert("pasta", 1, .packs) // 500 g box
        let results = PantryDecrementService.decrement(foods: [food("pasta", 100)], label: "t", modelContext: context)
        XCTAssertEqual(pasta.quantity, 0.8, accuracy: 0.0001)
        XCTAssertFalse(pasta.isDepleted)
        if case let .decremented(remaining) = results.first?.outcome {
            XCTAssertEqual(remaining, 0.8, accuracy: 0.0001)
        } else {
            XCTFail("Expected .decremented, got \(String(describing: results.first?.outcome))")
        }
    }

    func testCanDecrementIsFractionalAndUsesPurchaseWeight() {
        let juice = insert("tart cherry juice", 2, .bottles) // 1000 g per bottle
        PantryDecrementService.decrement(foods: [food("tart cherry juice", 100)], label: "t", modelContext: context)
        XCTAssertEqual(juice.quantity, 1.9, accuracy: 0.0001)
    }

    func testDecrementDetailRoundTripsExactly() throws {
        let pasta = insert("pasta", 1, .packs)
        let results = PantryDecrementService.decrement(foods: [food("pasta", 130)], label: "t", modelContext: context)
        let details = results.flatMap(\.details)
        XCTAssertEqual(details.count, 1)
        XCTAssertEqual(pasta.quantity, 0.74, accuracy: 0.000001)
        PantryDecrementService.creditExact(details: details, modelContext: context)
        XCTAssertEqual(pasta.quantity, 1.0, accuracy: 0.000001, "Undo must restore exactly what was taken")
    }

    func testDustIsConsumedWithLastBiteAndRoundTrips() {
        // 480 g of a 500 g pack leaves 0.04 pack — under the depletion
        // threshold, so the row is finished and the detail records the whole
        // pack so undo restores it exactly.
        let pasta = insert("pasta", 1, .packs)
        let results = PantryDecrementService.decrement(foods: [food("pasta", 480)], label: "t", modelContext: context)
        XCTAssertEqual(pasta.quantity, 0, accuracy: 0.000001)
        XCTAssertTrue(pasta.isDepleted)
        if case .depleted = results.first?.outcome {} else { XCTFail("Expected depleted") }
        PantryDecrementService.creditExact(details: results.flatMap(\.details), modelContext: context)
        XCTAssertEqual(pasta.quantity, 1, accuracy: 0.000001)
    }

    func testBelowThresholdIsDepletedButAboveIsNot() {
        let nearly = insert("pasta", 0.04, .packs)
        XCTAssertTrue(nearly.isDepleted)
        XCTAssertFalse(nearly.isInStock)
        let some = insert("rice", 0.2, .packs)
        XCTAssertFalse(some.isDepleted)
        XCTAssertTrue(some.isInStock)
        let grams = insert("oats", 0.04, .grams)
        XCTAssertFalse(grams.isDepleted, "Mass rows only deplete at exactly zero")
    }

    func testMultiPieceRowIsNotWipedByOneMeal() {
        let carrots = insert("carrot", 6, .pieces) // 65 g per piece
        PantryDecrementService.decrement(foods: [food("carrot", 130)], label: "t", modelContext: context)
        XCTAssertEqual(carrots.quantity, 4, accuracy: 0.0001)
    }

    func testPiecesWithoutKnownWeightAreLeftAlone() {
        let thing = insert("dragonfruit custard", 3, .pieces)
        let results = PantryDecrementService.decrement(foods: [food("dragonfruit custard", 100)], label: "t", modelContext: context)
        XCTAssertEqual(thing.quantity, 3, "No per-unit weight → untouched")
        if case .skippedNoUnitMatch? = results.first.map(\.outcome) {} else if case .notFound? = results.first.map(\.outcome) {} else {
            XCTFail("Expected skipped/notFound")
        }
    }

    func testGramsApproxContainersUseSamePerUnitWeightAsDecrement() {
        // A can/jar/bottle row is weighed by its purchase weight everywhere
        // (it used to be `grams` in gramsApprox but `purchaseGrams` in the
        // decrement, so list and pantry disagreed).
        XCTAssertEqual(PantryUnit.cans.gramsApprox(quantity: 1, foodName: "black beans canned") ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(PantryUnit.jars.gramsApprox(quantity: 0.5, foodName: "peanut butter") ?? 0, 250, accuracy: 0.001)
        XCTAssertEqual(PantryUnit.pieces.gramsApprox(quantity: 2, foodName: "carrot") ?? 0, 130, accuracy: 0.001)
    }

    func testFormatterShowsFractionAndApproxWeight() {
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 0.8, unit: .packs, canonicalName: "pasta"), "0.8 pack (~400 g)")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 1, unit: .packs, canonicalName: "pasta"), "1 pack (~500 g)")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 3, unit: .pieces, canonicalName: "carrot"), "3 pcs")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 0.5, unit: .pieces, canonicalName: "carrot"), "0.5 pc (~33 g)")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 250, unit: .grams, canonicalName: "oats"), "250g")
        XCTAssertEqual(PantryQuantityFormatter.number(0.30000000000000004), "0.3")
        XCTAssertEqual(PantryQuantityFormatter.editText(2), "2")
    }

    func testVoiceUseSomeDoesNotMixUnitsAcrossRows() throws {
        let grams = insert("pasta", 500, .grams)
        let packs = insert("pasta", 2, .packs)
        let pantry = LocalPantryService(modelContext: context)
        let intent = PantryEditIntent.decrement(rawName: "pasta", fraction: 0.5)
        VoicePantryEditApplier.apply([intent], pantryService: pantry, modelContext: context)
        XCTAssertEqual(grams.quantity, 250, accuracy: 0.001)
        XCTAssertEqual(packs.quantity, 1, accuracy: 0.001)
    }

    func testRestockMergeResetsExpiredUseBy() throws {
        let pantry = LocalPantryService(modelContext: context)
        let old = insert("milk", 0, .liters)
        old.useBy = Calendar.current.date(byAdding: .day, value: -5, to: Date())
        try context.save()
        let merged = try pantry.mergeOrCreate(
            rawName: "milk", quantity: 1, unit: .liters, storageLocation: .fridge,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        XCTAssertEqual(merged.id, old.id)
        let useBy = try XCTUnwrap(merged.useBy)
        XCTAssertGreaterThan(useBy, Date(), "A fresh restock must not inherit the expired batch's use-by")
    }

    func testRestockMergeStillKeepsEarlierFreshUseBy() throws {
        let pantry = LocalPantryService(modelContext: context)
        let old = insert("milk", 1, .liters)
        let soon = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        old.useBy = soon
        try context.save()
        let merged = try pantry.mergeOrCreate(
            rawName: "milk", quantity: 1, unit: .liters, storageLocation: .fridge,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        XCTAssertEqual(merged.useBy, soon)
    }

    func testStapleReturnsToHaveAfterRestock() throws {
        let pantry = LocalPantryService(modelContext: context)
        let staple = PantryStaple(canonicalName: "olive oil", displayName: "Olive oil", status: .out)
        context.insert(staple)
        try context.save()
        _ = try pantry.mergeOrCreate(
            rawName: "olive oil", quantity: 1, unit: .bottles, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .groceryConfirm, sourceReceiptLineItemID: nil
        )
        XCTAssertEqual(staple.status, .have)
    }

    func testDepletionRestockUsesPurchaseUnitNotPieces() {
        let rice = PantryGroceryBridge.restockDefault(canonicalName: "rice")
        XCTAssertEqual(rice.unit, .packs)
        XCTAssertEqual(PantryGroceryBridge.restockDefault(canonicalName: "mystery goo").unit, .pieces)
    }
}
