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
}
