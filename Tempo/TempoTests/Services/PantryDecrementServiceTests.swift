//
// PantryDecrementServiceTests.swift
// Tempo
//
// Verifies the foods-based decrement path used when a meal is SUBSTITUTED
// (recipe cleared, real foods in `meal.foods`) and the user confirms they
// pulled the substitute from pantry stock. The critical contract is
// idempotency: a meal must decrement the pantry AT MOST ONCE, even if the
// user re-resolves the substitute. Without that guard the pantry silently
// double-subtracts and drifts toward zero.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - PantryDecrementServiceTests

@MainActor
final class PantryDecrementServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PantryItem.self, PantryStaple.self, configurations: config)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private var context: ModelContext {
        container.mainContext
    }

    private func insert(
        _ name: String,
        quantity: Double,
        unit: PantryUnit = .grams
    ) {
        context.insert(PantryItem(
            canonicalName: name,
            displayName: name.capitalized,
            quantity: quantity,
            unit: unit,
            storageLocation: .pantry
        ))
        try? context.save()
    }

    private func quantity(of canonical: String) -> Double? {
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        return rows.first { $0.canonicalName.lowercased() == canonical.lowercased() }?.quantity
    }

    private func food(_ name: String, grams: Double) -> PlannedFood {
        PlannedFood(name: name, quantityGrams: grams, calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }

    @discardableResult
    private func insertBranded(
        _ name: String,
        quantity: Double,
        unit: PantryUnit = .grams,
        brand: String,
        useBy: Date?
    ) -> PantryItem {
        let item = PantryItem(
            canonicalName: name,
            displayName: name.capitalized,
            brand: brand,
            quantity: quantity,
            unit: unit,
            storageLocation: .pantry,
            useBy: useBy
        )
        context.insert(item)
        try? context.save()
        return item
    }

    private func row(brand: String) -> PantryItem? {
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        return rows.first { $0.brand == brand }
    }

    // MARK: - Happy path

    func testDecrement_gramUnit_subtractsGrams() throws {
        insert("rice", quantity: 1000)

        let results = PantryDecrementService.decrement(
            foods: [food("rice", grams: 153)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(
            try XCTUnwrap(quantity(of: "rice")),
            847,
            accuracy: 0.001,
            "1000g − 153g should leave 847g"
        )
        XCTAssertEqual(results.count, 1)
        if case let .decremented(remaining) = results.first?.outcome {
            XCTAssertEqual(remaining, 847, accuracy: 0.001)
        } else {
            XCTFail("Expected .decremented, got \(String(describing: results.first?.outcome))")
        }
    }

    // MARK: - Staple skip

    func testDecrement_staple_isSkipped() {
        insert("olive oil", quantity: 500, unit: .milliliters)

        let results = PantryDecrementService.decrement(
            foods: [food("olive oil", grams: 14)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(
            quantity(of: "olive oil"),
            500,
            "Staples must never be decremented — you bought a bottle months ago"
        )
        XCTAssertEqual(results.first?.outcome.isSkippedStaple, true)
    }

    // MARK: - No match no-ops

    func testDecrement_unknownFood_noOps() {
        insert("rice", quantity: 1000)

        let results = PantryDecrementService.decrement(
            foods: [food("dragonfruit", grams: 200)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(quantity(of: "rice"), 1000, "Unrelated pantry rows are untouched")
        XCTAssertEqual(results.first?.outcome.isNotFound, true)
    }

    // MARK: - Idempotency (the ship-blocker)

    func testDecrement_secondCallAfterGuard_doesNotDoubleSubtract() throws {
        // Simulates the real call site: the view guards with
        // `meal.didDecrementPantry`. The first resolve decrements; the
        // second must be skipped by the guard so the pantry holds steady.
        insert("rice", quantity: 1000)
        let meal = PlannedMeal(dayDate: .now, mealName: "Lunch")
        meal.foods = [food("rice", grams: 153)]

        // First resolve.
        if !meal.didDecrementPantry {
            PantryDecrementService.decrement(
                foods: meal.foods, label: meal.mealName, modelContext: context
            )
            meal.didDecrementPantry = true
        }
        XCTAssertEqual(try XCTUnwrap(quantity(of: "rice")), 847, accuracy: 0.001)

        // Second resolve (user re-corrects the substitute). Guard blocks it.
        if !meal.didDecrementPantry {
            PantryDecrementService.decrement(
                foods: meal.foods, label: meal.mealName, modelContext: context
            )
            meal.didDecrementPantry = true
        }
        XCTAssertEqual(
            try XCTUnwrap(quantity(of: "rice")),
            847,
            accuracy: 0.001,
            "Idempotency: the guard must prevent a second decrement"
        )
    }

    // MARK: - Imperial + servings units

    func testDecrement_poundUnit_convertsGramsToPounds() throws {
        insert("rice", quantity: 2, unit: .pounds)

        PantryDecrementService.decrement(
            foods: [food("rice", grams: 453.59237)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(
            try XCTUnwrap(quantity(of: "rice")),
            1,
            accuracy: 0.0001,
            "2 lb − 453.6 g (1 lb) should leave 1 lb"
        )
    }

    func testDecrement_ounceUnit_convertsGramsToOunces() throws {
        insert("rice", quantity: 16, unit: .ounces)

        PantryDecrementService.decrement(
            foods: [food("rice", grams: 56.69904625)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(
            try XCTUnwrap(quantity(of: "rice")),
            14,
            accuracy: 0.0001,
            "16 oz − 56.7 g (2 oz) should leave 14 oz"
        )
    }

    func testDecrement_servingsUnit_usesNaturalPortion() throws {
        // egg natural portion = 50 g → 100 g is 2 servings.
        insert("egg", quantity: 12, unit: .servings)

        PantryDecrementService.decrement(
            foods: [food("egg", grams: 100)], label: "Breakfast", modelContext: context
        )

        XCTAssertEqual(try XCTUnwrap(quantity(of: "egg")), 10, accuracy: 0.0001)
    }

    func testDecrement_servingsUnit_withoutNaturalPortion_isSkipped() {
        insert("dragonfruit", quantity: 3, unit: .servings)

        let results = PantryDecrementService.decrement(
            foods: [food("dragonfruit", grams: 200)], label: "Snack", modelContext: context
        )

        XCTAssertEqual(quantity(of: "dragonfruit"), 3, "No portion size → can't convert → untouched")
        XCTAssertEqual(results.first?.outcome.isSkippedNoUnitMatch, true)
    }

    func testCredit_poundUnit_isInverseOfDecrement() throws {
        insert("rice", quantity: 1, unit: .pounds)

        PantryDecrementService.credit(
            foods: [food("rice", grams: 226.796185)], label: "Undo", modelContext: context
        )

        XCTAssertEqual(try XCTUnwrap(quantity(of: "rice")), 1.5, accuracy: 0.0001)
    }

    // MARK: - FIFO across brand duplicates

    func testDecrementFIFO_acrossBrandDuplicates_consumesEarliestUseByFirst() throws {
        let soon = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let later = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 30, to: .now))
        // Insert the LATER-expiring row first to prove sort order (not insertion
        // order) drives consumption.
        insertBranded("butter", quantity: 100, brand: "BrandLate", useBy: later)
        insertBranded("butter", quantity: 50, brand: "BrandSoon", useBy: soon)

        let results = PantryDecrementService.decrement(
            foods: [food("butter", grams: 80)], label: "Baking", modelContext: context
        )

        // The earlier-useBy row (50g) is consumed FULLY first, then the
        // remaining 30g comes from the later-useBy row.
        let soonRow = try XCTUnwrap(row(brand: "BrandSoon"))
        let lateRow = try XCTUnwrap(row(brand: "BrandLate"))
        XCTAssertEqual(soonRow.quantity, 0, accuracy: 0.001)
        XCTAssertEqual(lateRow.quantity, 70, accuracy: 0.001)

        let details = try XCTUnwrap(results.first?.details)
        XCTAssertEqual(details.count, 2, "Both rows were touched — the exact-undo record must cover each")
        let firstAmount = try XCTUnwrap(details.first?.amount)
        let lastAmount = try XCTUnwrap(details.last?.amount)
        XCTAssertEqual(firstAmount, 50, accuracy: 0.001)
        XCTAssertEqual(lastAmount, 30, accuracy: 0.001)
    }

    func testDecrementFIFO_fullyDrainsOldestRowThenDepletes() throws {
        let soon = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        insertBranded("butter", quantity: 50, brand: "OnlyBrand", useBy: soon)

        let results = PantryDecrementService.decrement(
            foods: [food("butter", grams: 50)], label: "Baking", modelContext: context
        )

        let onlyRow = try XCTUnwrap(row(brand: "OnlyBrand"))
        XCTAssertEqual(onlyRow.quantity, 0, accuracy: 0.001)
        guard case .depleted = results.first?.outcome else {
            return XCTFail("Expected .depleted, got \(String(describing: results.first?.outcome))")
        }
    }

    // MARK: - Exact undo (creditExact)

    func testCreditExact_reversesRecordedDetailsPrecisely() throws {
        let soon = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let later = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 30, to: .now))
        insertBranded("butter", quantity: 100, brand: "BrandLate", useBy: later)
        insertBranded("butter", quantity: 50, brand: "BrandSoon", useBy: soon)

        let results = PantryDecrementService.decrement(
            foods: [food("butter", grams: 80)], label: "Baking", modelContext: context
        )
        let details = try XCTUnwrap(results.first?.details)

        let credited = PantryDecrementService.creditExact(details: details, modelContext: context)

        XCTAssertEqual(credited, 2)
        let soonRow = try XCTUnwrap(row(brand: "BrandSoon"))
        let lateRow = try XCTUnwrap(row(brand: "BrandLate"))
        XCTAssertEqual(
            soonRow.quantity,
            50,
            accuracy: 0.001,
            "Exact undo restores precisely what was taken from THIS row"
        )
        XCTAssertEqual(lateRow.quantity, 100, accuracy: 0.001)
    }

    func testCreditExact_convertsWhenRowUnitChangedBeforeUndo() throws {
        // Row starts in grams; the decrement records its detail in grams.
        // (Not a staple — staples are never decremented by meals.)
        let item = insertBranded("chicken breast", quantity: 1000, unit: .grams, brand: "OnlyBrand", useBy: nil)

        let results = PantryDecrementService.decrement(
            foods: [food("chicken breast", grams: 200)], label: "Dinner", modelContext: context
        )
        let details = try XCTUnwrap(results.first?.details)
        XCTAssertEqual(details.first?.unitRaw, PantryUnit.grams.rawValue)

        // The user re-units the row (e.g. via the tap-edit sheet) BEFORE
        // undoing — quantity now reads 0.8 kg (== the 800g left after the
        // 200g decrement, just re-expressed).
        item.unitRaw = PantryUnit.kilograms.rawValue
        item.quantity = 0.8
        try context.save()

        let credited = PantryDecrementService.creditExact(details: details, modelContext: context)

        XCTAssertEqual(credited, 1)
        // Must credit back the GRAM-equivalent of 200g (0.2 kg), not the
        // raw "200" straight into a kilograms row (which would wrongly
        // yield 200.8 kg).
        XCTAssertEqual(item.quantity, 1.0, accuracy: 0.001)
    }

    func testCreditExact_archivedRowCreditsALiveRowInstead() throws {
        let archived = insertBranded("chicken breast", quantity: 1000, unit: .grams, brand: "Old", useBy: nil)
        let results = PantryDecrementService.decrement(
            foods: [food("chicken breast", grams: 200)], label: "Dinner", modelContext: context
        )
        let details = try XCTUnwrap(results.first?.details)
        archived.isArchived = true
        try context.save()

        PantryDecrementService.creditExact(details: details, modelContext: context)

        XCTAssertEqual(archived.quantity, 800, accuracy: 0.001, "archived row untouched")
        let live = try context.fetch(FetchDescriptor<PantryItem>()).filter { !$0.isArchived && $0.canonicalName == "chicken breast" }
        XCTAssertEqual(live.count, 1, "a live row is recreated")
        XCTAssertEqual(try XCTUnwrap(live.first).quantity, 200, accuracy: 0.001)
    }

    // MARK: - Meal without a recipe (uses meal.foods)

    func testDecrementForMeal_withNoRecipe_usesMealFoods() throws {
        insert("rice", quantity: 1000)
        let meal = PlannedMeal(dayDate: .now, mealName: "Ad-hoc lunch")
        meal.foods = [food("rice", grams: 200)]
        XCTAssertNil(meal.recipe, "Sanity: this meal has no recipe")

        let results = PantryDecrementService.decrement(for: meal, modelContext: context)

        XCTAssertEqual(
            try XCTUnwrap(quantity(of: "rice")),
            800,
            accuracy: 0.001,
            "A meal with no recipe must fall back to meal.foods, not decrement nothing"
        )
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - PantryStaple-tracked staples are also skipped

    func testDecrement_userTrackedStaple_isSkipped() throws {
        insert("truffle salt", quantity: 200)
        context.insert(PantryStaple(canonicalName: "truffle salt", displayName: "Truffle salt"))
        try context.save()

        let results = PantryDecrementService.decrement(
            foods: [food("truffle salt", grams: 5)], label: "Dinner", modelContext: context
        )

        XCTAssertEqual(
            quantity(of: "truffle salt"),
            200,
            "A user-tracked staple (not in FoodMacroDatabase) must also be skipped"
        )
        XCTAssertEqual(results.first?.outcome.isSkippedStaple, true)
    }
}

// MARK: - Outcome test helpers

private extension PantryDecrementResult.Outcome {
    var isSkippedStaple: Bool {
        if case .skippedStaple = self {
            return true
        }
        return false
    }

    var isNotFound: Bool {
        if case .notFound = self {
            return true
        }
        return false
    }

    var isSkippedNoUnitMatch: Bool {
        if case .skippedNoUnitMatch = self {
            return true
        }
        return false
    }
}
