//
// FoodSuggestionsTests.swift
// Tempo
//
// FoodGroup classification, EU-14/US-major allergen display, FoodCatalog's
// always-there suggestions (Open Food Facts peers, ranked healthier/similar,
// falling back to Tempo's built-in table), and the halal/goal-aware FoodFit
// checks.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - Fixtures

private extension FoodProduct {
    static func sample(
        id: String = "8000500310427",
        name: String = "Skyr",
        brand: String? = "Arla",
        source: Source = .openFoodFacts,
        grade: String? = "a",
        points: Int? = -3,
        allergens: [String] = [],
        labels: [String] = [],
        categories: [String] = ["dairies", "yogurts", "skyrs"],
        ingredientsText: String? = nil,
        per100g: Nutrients = Nutrients(kcal: 62, protein: 11, carbs: 4, sugars: 4, fat: 0.2, saturatedFat: 0.1, fiber: 0, salt: 0.13),
        imageURL: URL? = nil
    ) -> FoodProduct {
        FoodProduct(
            id: id, barcode: source == .openFoodFacts ? id : nil, name: name, brand: brand, source: source,
            per100g: per100g, nutriScoreGrade: grade, nutriScorePoints: points,
            allergens: allergens, labels: labels, categories: categories,
            ingredientsText: ingredientsText, imageURL: imageURL
        )
    }
}

// MARK: - FoodGroupTests

final class FoodGroupTests: XCTestCase {
    func testNameKeywordsCoverTheBuiltInTable() {
        let cases: [(String, FoodGroup)] = [
            ("Chicken breast", .meat), ("Beef sirloin", .meat), ("Salmon", .fish), ("Tuna", .fish),
            ("White rice", .grains), ("Oats", .grains), ("White bread", .bread), ("Pasta", .pasta),
            ("Lentils", .legumes), ("Black beans", .legumes), ("Almonds", .nuts), ("Apple", .fruit),
            ("Banana", .fruit), ("Broccoli", .vegetables), ("Spinach", .vegetables),
            ("Pretzels", .snacks), ("Dark chocolate 70%", .sweets), ("Coke", .drinks),
            ("Olive oil", .oils), ("Ketchup", .sauces), ("Pizza margherita", .meals),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(FoodProduct.foodGroup(fromName: name), expected, name)
        }
    }

    func testComposedDishBeatsIngredientKeyword() {
        XCTAssertEqual(FoodProduct.foodGroup(fromName: "Cheeseburger"), .meals, "Not dairy just because of \"cheese\"")
        XCTAssertEqual(FoodProduct.foodGroup(fromName: "Chicken sandwich"), .meals, "Not meat just because of \"chicken\"")
    }

    func testNutButterBeatsGenericButter() {
        XCTAssertEqual(FoodProduct.foodGroup(fromName: "Peanut butter"), .nuts)
        XCTAssertEqual(FoodProduct.foodGroup(fromName: "Butter"), .dairy)
    }

    func testCategoryTagsAreCheckedFirst() {
        let product = FoodProduct.sample(name: "Random Product Name", categories: ["dairies", "yogurts"])
        XCTAssertEqual(product.foodGroup, .dairy)
    }

    func testUnknownFoodFallsBackToOther() {
        XCTAssertEqual(FoodProduct.sample(name: "Unidentifiable goo", categories: []).foodGroup, .other)
    }
}

// MARK: - DisplayAllergensTests

final class DisplayAllergensTests: XCTestCase {
    func testChobaniStyleJunkTagsCollapseToMilk() {
        // Chobani-style Open Food Facts entries carry both the canonical tag
        // and a junk ingredient-derived one for the same allergen.
        let product = FoodProduct.sample(allergens: ["milk", "cultured-nonfat-milk"])
        XCTAssertEqual(product.displayAllergens, ["Milk"])
    }

    func testMixedCaseAndPrefixedTagsMatch() {
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "en:Milk"), "Milk")
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "Cultured Nonfat Milk"), "Milk")
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "en:gluten"), "Gluten")
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "wheat"), "Gluten")
    }

    func testPeanutsAndTreeNutsStayDistinct() {
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "peanuts"), "Peanuts")
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "nuts"), "Tree nuts")
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "almonds"), "Tree nuts")
    }

    func testSulphitesFromTheLongOFFTagName() {
        XCTAssertEqual(FoodProduct.displayAllergenName(for: "en:sulphur-dioxide-and-sulphites"), "Sulphites")
    }

    func testUnmatchedTagIsDropped() {
        XCTAssertNil(FoodProduct.displayAllergenName(for: "en:some-random-tag"))
        let product = FoodProduct.sample(allergens: ["milk", "some-random-tag"])
        XCTAssertEqual(product.displayAllergens, ["Milk"])
    }

    func testOrderIsStable() {
        let product = FoodProduct.sample(allergens: ["gluten", "milk", "eggs"])
        XCTAssertEqual(product.displayAllergens, ["Milk", "Eggs", "Gluten"])
    }
}

// MARK: - FoodSuggestionsTests

@MainActor
final class FoodSuggestionsTests: XCTestCase {
    private final class FakeProducts: FoodProductProviding, @unchecked Sendable {
        var peersResult: [FoodProduct] = []
        var searchResult: [FoodProduct] = []
        var peersError: Error?
        var peersCallCount = 0

        func product(barcode _: String) async throws -> FoodProduct? {
            nil
        }

        func search(_: String, limit _: Int) async throws -> [FoodProduct] {
            searchResult
        }

        func alternatives(for _: FoodProduct, limit _: Int) async throws -> [FoodProduct] {
            []
        }

        func peers(for _: FoodProduct, limit _: Int) async throws -> [FoodProduct] {
            peersCallCount += 1
            if let peersError {
                throw peersError
            }
            return peersResult
        }
    }

    func testHealthierPeerWinsOverSimilarOnes() async {
        let fake = FakeProducts()
        let worse = FoodProduct.sample(id: "2", name: "Regular skyr", grade: "c", points: 8)
        let better = FoodProduct.sample(id: "3", name: "Light skyr", grade: "a", points: -8)
        fake.peersResult = [worse, better]
        let catalog = FoodCatalog(products: fake, generic: nil)

        let result = await catalog.suggestions(for: .sample(id: "1", grade: "c", points: 8))
        XCTAssertEqual(result.kind, .healthier)
        XCTAssertEqual(result.items.map(\.id), ["3"])
    }

    func testExcellentProductStillGetsSimilarSuggestions() async {
        // Previously `alternatives(for:)` returned [] once the product was
        // already excellent — suggestions must never go empty just because
        // there's nothing "better".
        let fake = FakeProducts()
        let peer = FoodProduct.sample(id: "2", name: "Another great skyr", grade: "a", points: -5)
        fake.peersResult = [peer]
        let catalog = FoodCatalog(products: fake, generic: nil)

        let result = await catalog.suggestions(for: .sample(id: "1", grade: "a", points: -8))
        XCTAssertEqual(result.kind, .similar)
        XCTAssertEqual(result.items.map(\.id), ["2"])
    }

    func testSelfAndDuplicatesAreExcluded() async {
        let fake = FakeProducts()
        let itself = FoodProduct.sample(id: "1", grade: "a", points: -8)
        let duplicateName = FoodProduct.sample(id: "9", name: "Skyr", brand: "Arla", grade: "a", points: -8)
        let genuine = FoodProduct.sample(id: "2", name: "Different skyr", grade: "a", points: -8)
        fake.peersResult = [itself, duplicateName, genuine]
        let catalog = FoodCatalog(products: fake, generic: nil)

        let result = await catalog.suggestions(for: .sample(id: "1", grade: "a", points: -8))
        XCTAssertEqual(result.items.map(\.id), ["2"])
    }

    func testCokeByCokeIsExcludedAsASelfSuggestion() async {
        // picky-QA item 5: "Coca-Cola by Coke" showed up as a swap for
        // "Coca-Cola" — same drink, cosmetically different brand string, so
        // the old exact name+brand dedup key missed it.
        let fake = FakeProducts()
        let cocaCola = FoodProduct.sample(id: "1", name: "Coca-Cola", brand: "coca cola", grade: "e", points: 20)
        let sameDrinkOtherBrandString = FoodProduct.sample(id: "2", name: "Coca-Cola", brand: "Coke", grade: "e", points: 20)
        let genuineAlternative = FoodProduct.sample(id: "3", name: "Coca-Cola Zero", brand: "Coke", grade: "c", points: 2)
        fake.peersResult = [sameDrinkOtherBrandString, genuineAlternative]
        let catalog = FoodCatalog(products: fake, generic: nil)

        let result = await catalog.suggestions(for: cocaCola)
        XCTAssertFalse(result.items.map(\.id).contains("2"), "Coca-Cola by Coke is the same product as Coca-Cola, not a swap for it")
        XCTAssertTrue(result.items.map(\.id).contains("3"))
    }

    func testExcellentProductNeedsAnEightPointGainNotFiveToCountAsHealthier() async {
        // picky-QA item 6: once a product is already .excellent, a
        // marginally-better peer (+3) must stay a "similar" suggestion, not
        // get promoted to "healthier" — only a real (+8) gap does.
        let fake = FakeProducts()
        let current = FoodProduct.sample(id: "1", grade: "a", points: -8)
        guard let currentTotal = FoodScore.evaluate(current)?.total else {
            XCTFail("Fixture must score")
            return
        }
        XCTAssertEqual(FoodScore.Rating(score: currentTotal), .excellent)

        let marginallyBetter = FoodProduct.sample(id: "2", name: "Marginally better skyr", grade: "a", points: -9)
        fake.peersResult = [marginallyBetter]
        let similarCatalog = FoodCatalog(products: fake, generic: nil)
        let similarResult = await similarCatalog.suggestions(for: current)
        XCTAssertEqual(similarResult.kind, .similar, "A tiny edge over an already-excellent product isn't a real swap")
    }

    func testNonOpenFoodFactsProductFallsBackToNameSearchThenBuiltIn() async {
        let fake = FakeProducts()
        // No network peers and no search hits: must still fall back to the
        // built-in table for the same food group ("meat").
        let catalog = FoodCatalog(products: fake, generic: nil)
        let builtIn = FoodCatalog.builtInProduct(
            name: "chicken breast",
            macros: FoodMacros(calories: 165, protein: 31, carbs: 0, fat: 3.6, fiber: 0)
        )

        let result = await catalog.suggestions(for: builtIn)
        XCTAssertFalse(result.items.isEmpty, "A built-in peer of the same food group must always be found")
        XCTAssertTrue(result.items.allSatisfy { $0.foodGroup == .meat })
    }

    func testNetworkFailureFallsBackToBuiltIn() async {
        let fake = FakeProducts()
        fake.peersError = FoodLookupError.offline
        let catalog = FoodCatalog(products: fake, generic: nil)
        let builtIn = FoodCatalog.builtInProduct(
            name: "salmon",
            macros: FoodMacros(calories: 208, protein: 20.4, carbs: 0, fat: 13.4, fiber: 0)
        )

        let result = await catalog.suggestions(for: builtIn)
        XCTAssertFalse(result.items.isEmpty)
    }

    func testSuggestionsAreCachedPerProduct() async {
        let fake = FakeProducts()
        fake.peersResult = [.sample(id: "2", name: "Other skyr", grade: "a", points: -8)]
        let catalog = FoodCatalog(products: fake, generic: nil)
        let product = FoodProduct.sample(id: "1", grade: "a", points: -8)

        _ = await catalog.suggestions(for: product)
        _ = await catalog.suggestions(for: product)
        XCTAssertEqual(fake.peersCallCount, 1, "Second call should hit the in-memory cache")
    }

    func testItemsWithAPhotoSortFirstWithinATier() async {
        let fake = FakeProducts()
        // Both peers score better than the current product and tie with
        // each other, so only the photo should decide the order. The current
        // product (points -3) already scores as .excellent, so the peers
        // need a real (+8) gap, not just any improvement — points -15 is the
        // best of the "a" band.
        var withPhoto = FoodProduct.sample(id: "2", name: "Skyr with photo", grade: "a", points: -15)
        withPhoto.imageURL = URL(string: "https://images.openfoodfacts.org/x.jpg")
        let withoutPhoto = FoodProduct.sample(id: "3", name: "Skyr without photo", grade: "a", points: -15)
        fake.peersResult = [withoutPhoto, withPhoto]
        let catalog = FoodCatalog(products: fake, generic: nil)

        let result = await catalog.suggestions(for: .sample(id: "1", grade: "a", points: -3))
        XCTAssertEqual(result.kind, .healthier)
        XCTAssertEqual(Set(result.items.map(\.id)), ["2", "3"])
        XCTAssertEqual(result.items.first?.id, "2")
    }
}

// MARK: - FoodFitHalalAndGoalTests

final class FoodFitHalalAndGoalTests: XCTestCase {
    func testPorkConflict() {
        let product = FoodProduct.sample(ingredientsText: "Pork, salt, spices")
        let check = FoodFit.halalCheck(for: product)
        XCTAssertEqual(check?.kind, .conflict)
        XCTAssertTrue(check?.text.contains("pork") ?? false)
    }

    func testUnspecifiedGelatinConflicts() {
        let product = FoodProduct.sample(ingredientsText: "Sugar, gelatin, citric acid")
        XCTAssertEqual(FoodFit.halalCheck(for: product)?.kind, .conflict)
    }

    func testSourcedGelatinDoesNotConflict() {
        let product = FoodProduct.sample(ingredientsText: "Sugar, beef gelatin, citric acid")
        XCTAssertNil(FoodFit.halalCheck(for: product))
    }

    @MainActor
    func testPluralListingCountsAsTheSameFood() {
        let banana = FoodProduct(id: "builtin:banana", name: "Banana", source: .builtIn, per100g: .init(kcal: 89))
        let bananas = FoodProduct(id: "usda:1", name: "Bananas", source: .usda, per100g: .init(kcal: 89))
        XCTAssertEqual(FoodCatalog.jaccard(FoodCatalog.nameTokens(banana), FoodCatalog.nameTokens(bananas)), 1)
        XCTAssertEqual(FoodCatalog.singular("tomatoes"), "tomato")
        XCTAssertEqual(FoodCatalog.singular("peaches"), "peach")
        XCTAssertEqual(FoodCatalog.singular("hummus"), "hummu")
        XCTAssertEqual(FoodCatalog.singular("glass"), "glass")
    }

    func testWordsContainingPorkTermsDoNotConflict() {
        let product = FoodProduct.sample(ingredientsText: "Chamomile, collard greens, serum whey, graham flour")
        XCTAssertNil(FoodFit.halalCheck(for: product))
    }

    func testHamAsAWordStillConflicts() {
        let product = FoodProduct.sample(ingredientsText: "Cooked ham (pork), water")
        XCTAssertEqual(FoodFit.halalCheck(for: product)?.kind, .conflict)
    }

    func testSugarAlcoholAndWineVinegarDoNotConflict() {
        let product = FoodProduct.sample(ingredientsText: "Erythritol (sugar alcohol), red wine vinegar, salt")
        XCTAssertNil(FoodFit.halalCheck(for: product))
    }

    func testHalalLabelIsGood() {
        let product = FoodProduct.sample(labels: ["halal", "certified-halal"])
        XCTAssertEqual(FoodFit.halalCheck(for: product)?.kind, .good)
    }

    func testNoSignalIsSilent() {
        let product = FoodProduct.sample()
        XCTAssertNil(FoodFit.halalCheck(for: product))
    }

    func testHalalCheckSurfacesInFullChecksOnlyWhenContextIsHalal() {
        let product = FoodProduct.sample(ingredientsText: "Pork, salt")
        var context = FoodFitContext(remainingCalories: 500)
        context.halal = true
        XCTAssertTrue(FoodFit.checks(for: product, grams: 100, context: context)
            .contains { $0.kind == .conflict && $0.text.contains("halal") })

        context.halal = false
        XCTAssertFalse(FoodFit.checks(for: product, grams: 100, context: context).contains { $0.text.contains("halal") })
    }

    func testCutFlagsCalorieDenseAndPraisesProtein() {
        var context = FoodFitContext()
        context.goal = .cut
        let dense = FoodProduct.sample(per100g: .init(kcal: 500, protein: 5, carbs: 40, fat: 30))
        XCTAssertEqual(FoodFit.goalCheck(for: dense, context: context)?.kind, .warning)

        let proteinDense = FoodProduct.sample(per100g: .init(kcal: 120, protein: 25, carbs: 2, fat: 2))
        XCTAssertEqual(FoodFit.goalCheck(for: proteinDense, context: context)?.kind, .good)
    }

    func testCutDoesNotFlagNutsForCalorieDensity() {
        var context = FoodFitContext()
        context.goal = .cut
        let almonds = FoodProduct.sample(name: "Almonds", categories: [], per100g: .init(kcal: 579, protein: 21, carbs: 22, fat: 50))
        XCTAssertNil(FoodFit.goalCheck(for: almonds, context: context))
    }

    func testLeanGainPraisesEnergyDensity() {
        var context = FoodFitContext()
        context.goal = .leanGain
        let dense = FoodProduct.sample(per100g: .init(kcal: 500, protein: 10, carbs: 40, fat: 30))
        XCTAssertEqual(FoodFit.goalCheck(for: dense, context: context)?.kind, .good)
    }

    func testMaintainHasNoGoalFraming() {
        var context = FoodFitContext()
        context.goal = .maintain
        let dense = FoodProduct.sample(per100g: .init(kcal: 500, protein: 10, carbs: 40, fat: 30))
        XCTAssertNil(FoodFit.goalCheck(for: dense, context: context))
    }

    func testNoGoalSetIsSilent() {
        let dense = FoodProduct.sample(per100g: .init(kcal: 500, protein: 10, carbs: 40, fat: 30))
        XCTAssertNil(FoodFit.goalCheck(for: dense, context: .none))
    }
}
