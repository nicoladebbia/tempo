//
// FoodCheckRound2Tests.swift
// Tempo
//
// Round 2 (Lane S): Food check product actions (log / pantry / list /
// inventory line), allergen rules (traces warn, missing data can't verify,
// ingredient text), and swap suggestions that respect the user's profile.
//

import SwiftData
@testable import Tempo
import XCTest

private extension FoodProduct {
    static func r2(
        id: String = "5000000000001",
        name: String = "Crunchy Bar",
        source: Source = .openFoodFacts,
        allergens: [String] = [],
        traces: [String]? = nil,
        labels: [String] = [],
        analysis: [String] = [],
        ingredients: String? = nil,
        grade: String? = "b"
    ) -> FoodProduct {
        FoodProduct(
            id: id, barcode: source == .openFoodFacts ? id : nil, name: name, brand: "Acme", source: source,
            quantityLabel: "250 g",
            per100g: Nutrients(kcal: 400, protein: 10, carbs: 50, sugars: 5, fat: 15, saturatedFat: 3, fiber: 3, salt: 0.2),
            nutriScoreGrade: grade, nutriScorePoints: 2,
            allergens: allergens, traces: traces, labels: labels, categories: ["snacks"],
            ingredientsAnalysis: analysis, ingredientsText: ingredients
        )
    }
}

// MARK: - Allergen rules

final class FoodFitAllergenTests: XCTestCase {
    private func kinds(_ product: FoodProduct, _ context: FoodFitContext) -> [FoodFitCheck.Kind: [String]] {
        Dictionary(grouping: FoodFit.checks(for: product, grams: 100, context: context), by: \.kind)
            .mapValues { $0.map(\.text) }
    }

    func testTraceOfUsersAllergenIsAWarningNotAConflict() {
        var context = FoodFitContext()
        context.nutFree = true
        let result = kinds(.r2(traces: ["en:nuts"], ingredients: "oats, sugar"), context)
        XCTAssertNil(result[.conflict])
        XCTAssertTrue(result[.warning]?.contains { $0.contains("May contain traces of nuts") } == true)
    }

    func testTraceInIngredientTextStatementIsAWarning() {
        var context = FoodFitContext()
        context.glutenFree = true
        let result = kinds(.r2(ingredients: "rice, sugar. May contain traces of wheat."), context)
        XCTAssertNil(result[.conflict])
        XCTAssertTrue(result[.warning]?.contains { $0.contains("gluten") } == true)
    }

    func testConfirmedAllergenStillConflicts() {
        var context = FoodFitContext()
        context.nutFree = true
        XCTAssertNotNil(kinds(.r2(allergens: ["peanuts"], ingredients: "peanuts"), context)[.conflict])
    }

    func testMissingAllergenAndIngredientDataCantVerify() {
        var context = FoodFitContext()
        context.glutenFree = true
        let result = kinds(.r2(), context)
        XCTAssertTrue(result[.warning]?.contains { $0.hasPrefix("Can't verify allergens") } == true)
        XCTAssertNil(result[.good], "Never reads as safe")
    }

    func testNoCantVerifyWhenTheUserHasNoAllergyRuleOrDataExists() {
        XCTAssertNil(kinds(.r2(), FoodFitContext())[.warning]?.first { $0.hasPrefix("Can't verify") })
        var context = FoodFitContext()
        context.nutFree = true
        XCTAssertNil(kinds(.r2(ingredients: "oats, honey"), context)[.warning]?.first { $0.hasPrefix("Can't verify") })
        // Generic table foods were never asked, so no noisy "can't verify".
        XCTAssertNil(kinds(.r2(source: .builtIn), context)[.warning]?.first { $0.hasPrefix("Can't verify") })
    }

    func testGlutenFromIngredientTextWithoutTag() {
        var context = FoodFitContext()
        context.glutenFree = true
        XCTAssertNotNil(kinds(.r2(ingredients: "Wheat flour, sugar, salt"), context)[.conflict])
        XCTAssertNil(kinds(.r2(ingredients: "Buckwheat flour, sugar"), context)[.conflict], "Buckwheat is not wheat")
        XCTAssertNil(kinds(.r2(name: "Gluten free bread", ingredients: "rice flour"), context)[.conflict])
    }

    func testNutAndShellfishFromIngredientText() {
        var nut = FoodFitContext()
        nut.nutFree = true
        XCTAssertNotNil(kinds(.r2(ingredients: "sugar, hazelnut paste, cocoa"), nut)[.conflict])
        XCTAssertNil(kinds(.r2(ingredients: "coconut milk, nutmeg"), nut)[.conflict])
        var shell = FoodFitContext()
        shell.shellfishAllergy = true
        XCTAssertNotNil(kinds(.r2(ingredients: "rice, shrimp, soy sauce"), shell)[.conflict])
    }

    func testNamedAllergyTraceWarnsAndIngredientConflicts() {
        var context = FoodFitContext()
        context.allergies = ["sesame"]
        XCTAssertNil(kinds(.r2(traces: ["sesame"], ingredients: "oats"), context)[.conflict])
        XCTAssertNotNil(kinds(.r2(traces: ["sesame"], ingredients: "oats"), context)[.warning])
        XCTAssertNotNil(kinds(.r2(ingredients: "oats, sesame seeds"), context)[.conflict])
    }

    func testEnrichedDataIsMergedIntoTheChecks() {
        let bare = FoodProduct.r2()
        let enriched = FoodProduct.r2(allergens: ["gluten"], ingredients: "wheat flour")
        var context = FoodFitContext()
        context.glutenFree = true
        XCTAssertNil(kinds(bare, context)[.conflict])
        XCTAssertNotNil(kinds(bare.mergingAllergenData(from: enriched), context)[.conflict])
    }
}

// MARK: - Swaps respect the profile

@MainActor
final class FoodSwapContextTests: XCTestCase {
    private final class Fake: FoodProductProviding, @unchecked Sendable {
        var peers: [FoodProduct] = []
        var peersCalls = 0
        func product(barcode _: String) async throws -> FoodProduct? { nil }
        func search(_: String, limit _: Int) async throws -> [FoodProduct] { [] }
        func alternatives(for _: FoodProduct, limit _: Int) async throws -> [FoodProduct] { [] }
        func peers(for _: FoodProduct, limit _: Int) async throws -> [FoodProduct] {
            peersCalls += 1
            return peers
        }
    }

    func testConflictingCandidatesAreDropped() async {
        let fake = Fake()
        fake.peers = [
            .r2(id: "2", name: "Peanut Crunch", allergens: ["peanuts"], ingredients: "peanuts", grade: "a"),
            .r2(id: "3", name: "Seed Crunch", ingredients: "oats, seeds", grade: "a"),
            .r2(id: "4", name: "Meat Snack", analysis: ["non-vegan"], ingredients: "beef", grade: "a"),
        ]
        let catalog = FoodCatalog(products: fake, generic: nil)
        var context = FoodFitContext()
        context.nutFree = true
        context.vegan = true
        let result = await catalog.suggestions(for: .r2(id: "1", grade: "c"), context: context)
        XCTAssertEqual(result.items.map(\.id), ["3"])
    }

    func testContextIsPartOfTheCacheKey() async {
        let fake = Fake()
        fake.peers = [
            .r2(id: "2", name: "Peanut Crunch", allergens: ["peanuts"], ingredients: "peanuts", grade: "a"),
            .r2(id: "3", name: "Seed Crunch", ingredients: "oats, seeds", grade: "a"),
        ]
        let catalog = FoodCatalog(products: fake, generic: nil)
        let product = FoodProduct.r2(id: "1", grade: "c")
        let open = await catalog.suggestions(for: product)
        XCTAssertEqual(Set(open.items.map(\.id)), ["2", "3"])
        var context = FoodFitContext()
        context.nutFree = true
        let strict = await catalog.suggestions(for: product, context: context)
        XCTAssertEqual(strict.items.map(\.id), ["3"], "A profile change must not serve the unfiltered cached list")
        XCTAssertEqual(fake.peersCalls, 2)
    }
}

// MARK: - Product actions

@MainActor
final class FoodProductActionsTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext {
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

    func testLogAddsToTodaysEatenTotals() throws {
        let product = FoodProduct.r2()
        let logged = try FoodProductActions.log(product, grams: 50, type: .snack, modelContext: ctx)
        XCTAssertEqual(logged.calories, 200, accuracy: 0.5)
        let totals = CanonicalMeals.totals(of: CanonicalMeals.eatenMeals(on: Date(), in: ctx))
        XCTAssertEqual(totals.calories, 200, accuracy: 0.5)
        XCTAssertEqual(totals.protein, 5, accuracy: 0.1)
    }

    func testAddToPantryCreatesARowAndInventoryLineSaysSo() throws {
        let product = FoodProduct.r2()
        XCTAssertEqual(FoodProductActions.inventory(for: product, modelContext: ctx).line, "Not at home · not on your list")
        let item = try FoodProductActions.addToPantry(product, modelContext: ctx)
        XCTAssertEqual(item.canonicalName, FoodCanonicalizer.canonicalize(product.name))
        let inventory = FoodProductActions.inventory(for: product, modelContext: ctx)
        XCTAssertNotNil(inventory.atHome)
        XCTAssertTrue(inventory.line.contains("at home"))
    }

    func testAddToListNeedsAListThenAddsOnceAndShowsOnTheInventoryLine() throws {
        let product = FoodProduct.r2()
        XCTAssertEqual(try FoodProductActions.addToList(product, modelContext: ctx), .noList)
        ctx.insert(GroceryList(weekStartDate: Date()))
        try ctx.save()
        XCTAssertEqual(try FoodProductActions.addToList(product, modelContext: ctx), .added)
        XCTAssertEqual(try FoodProductActions.addToList(product, modelContext: ctx), .alreadyOnList)
        XCTAssertTrue(FoodProductActions.inventory(for: product, modelContext: ctx).onList)
        XCTAssertTrue(FoodProductActions.inventory(for: product, modelContext: ctx).line.hasSuffix("· on your list"))
    }
}
