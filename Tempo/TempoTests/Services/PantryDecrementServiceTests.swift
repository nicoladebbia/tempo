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

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class PantryDecrementServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PantryItem.self, configurations: config)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private var context: ModelContext { container.mainContext }

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

    // MARK: - Happy path

    func testDecrement_gramUnit_subtractsGrams() throws {
        insert("rice", quantity: 1000)

        let results = PantryDecrementService.decrement(
            foods: [food("rice", grams: 153)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(try XCTUnwrap(quantity(of: "rice")), 847, accuracy: 0.001,
                       "1000g − 153g should leave 847g")
        XCTAssertEqual(results.count, 1)
        if case .decremented(let remaining) = results.first?.outcome {
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

        XCTAssertEqual(quantity(of: "olive oil"), 500,
                       "Staples must never be decremented — you bought a bottle months ago")
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
        XCTAssertEqual(try XCTUnwrap(quantity(of: "rice")), 847, accuracy: 0.001,
                       "Idempotency: the guard must prevent a second decrement")
    }

    // MARK: - Imperial + servings units

    func testDecrement_poundUnit_convertsGramsToPounds() throws {
        insert("rice", quantity: 2, unit: .pounds)

        PantryDecrementService.decrement(
            foods: [food("rice", grams: 453.59237)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(try XCTUnwrap(quantity(of: "rice")), 1, accuracy: 0.0001,
                       "2 lb − 453.6 g (1 lb) should leave 1 lb")
    }

    func testDecrement_ounceUnit_convertsGramsToOunces() throws {
        insert("rice", quantity: 16, unit: .ounces)

        PantryDecrementService.decrement(
            foods: [food("rice", grams: 56.69904625)], label: "Lunch", modelContext: context
        )

        XCTAssertEqual(try XCTUnwrap(quantity(of: "rice")), 14, accuracy: 0.0001,
                       "16 oz − 56.7 g (2 oz) should leave 14 oz")
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
}

// MARK: - Outcome test helpers

private extension PantryDecrementResult.Outcome {
    var isSkippedStaple: Bool {
        if case .skippedStaple = self { return true }
        return false
    }
    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }
    var isSkippedNoUnitMatch: Bool {
        if case .skippedNoUnitMatch = self { return true }
        return false
    }
}
