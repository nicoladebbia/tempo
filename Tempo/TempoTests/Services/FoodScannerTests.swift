//
// FoodScannerTests.swift
// Tempo
//
// The Yuka-style scanner core: Tempo score (Nutri-Score part, additive
// risk + high-risk cap, organic bonus), Nutri-Score estimate, Open Food
// Facts decoding (string-vs-array fields, "unknown" grades), "For you"
// checks, label-reader parsing, and FoodCatalog search/lookup/history.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - Fixtures

private extension FoodProduct {
    static func sample(
        id: String = "8000500310427",
        grade: String? = "a",
        points: Int? = -3,
        additives: [String] = [],
        labels: [String] = [],
        allergens: [String] = [],
        analysis: [String] = [],
        nova: Int? = 3,
        per100g: Nutrients = Nutrients(kcal: 62, protein: 11, carbs: 4, sugars: 4, fat: 0.2, saturatedFat: 0.1, fiber: 0, salt: 0.13),
        categories: [String] = ["dairies", "yogurts", "skyrs"]
    ) -> FoodProduct {
        FoodProduct(
            id: id, barcode: id, name: "Skyr", brand: "Arla", source: .openFoodFacts,
            servingLabel: "150 g", servingGrams: 150, per100g: per100g,
            nutriScoreGrade: grade, nutriScorePoints: points, novaGroup: nova,
            additives: additives, allergens: allergens, labels: labels, categories: categories,
            ingredientsAnalysis: analysis
        )
    }
}

private let additiveTable = FoodAdditiveTable(entries: [
    "e250": .init(n: "Sodium nitrite", r: "high"),
    "e433": .init(n: "Polysorbate 80", r: "moderate"),
    "e322": .init(n: "Lecithins", r: nil),
    "e330": .init(n: "Citric acid", r: "no"),
])

// MARK: - FoodScoreTests

final class FoodScoreTests: XCTestCase {
    func testCleanGradeAScoresExcellent() throws {
        let score = try XCTUnwrap(FoodScore.evaluate(.sample(), additiveTable: additiveTable))
        XCTAssertEqual(score.additivePoints, 30)
        XCTAssertEqual(score.organicPoints, 0)
        XCTAssertGreaterThanOrEqual(score.nutritionPoints, 45)
        XCTAssertEqual(score.rating, .excellent)
        XCTAssertFalse(score.nutriScoreEstimated)
    }

    func testHighRiskAdditiveCapsAt49() throws {
        let score = try XCTUnwrap(FoodScore.evaluate(.sample(additives: ["e250"], labels: ["eu-organic"]), additiveTable: additiveTable))
        XCTAssertTrue(score.cappedByAdditive)
        XCTAssertLessThanOrEqual(score.total, 49)
        XCTAssertEqual(score.rating, .poor)
        XCTAssertEqual(score.additives.first?.risk, .high)
    }

    func testModerateAdditiveCostsTenAndOrganicAddsTen() throws {
        let plain = try XCTUnwrap(FoodScore.evaluate(.sample(), additiveTable: additiveTable))
        let score = try XCTUnwrap(FoodScore.evaluate(
            .sample(additives: ["e433", "e322", "e330"], labels: ["organic"]),
            additiveTable: additiveTable
        ))
        XCTAssertEqual(score.additivePoints, 20)
        XCTAssertEqual(score.organicPoints, 10)
        XCTAssertEqual(score.total, plain.total)
    }

    func testGradeEScoresBad() throws {
        let score = try XCTUnwrap(FoodScore.evaluate(.sample(grade: "e", points: 26), additiveTable: additiveTable))
        XCTAssertLessThan(score.total, 50)
        XCTAssertLessThanOrEqual(score.nutritionPoints, 9)
    }

    func testMissingGradeIsEstimatedFromNutrients() throws {
        // Nutella-like: 539 kcal, 56.3 g sugar, 10.6 g sat fat, 0.107 g salt → E.
        let product = FoodProduct.sample(
            grade: nil, points: nil,
            per100g: .init(kcal: 539, protein: 6.3, carbs: 57.5, sugars: 56.3, fat: 30.9, saturatedFat: 10.6, fiber: 0, salt: 0.107)
        )
        let score = try XCTUnwrap(FoodScore.evaluate(product, additiveTable: additiveTable))
        XCTAssertTrue(score.nutriScoreEstimated)
        XCTAssertEqual(score.nutriScoreGrade, "e")
    }

    func testNotEnoughDataHasNoScore() {
        let product = FoodProduct.sample(grade: nil, points: nil, per100g: .init(kcal: 100))
        XCTAssertNil(FoodScore.evaluate(product, additiveTable: additiveTable))
    }

    func testNutriScoreEstimateMatchesOfficialForSkyr() throws {
        let estimate = try XCTUnwrap(NutriScore.estimate(FoodProduct.sample().per100g, isBeverage: false))
        XCTAssertEqual(estimate.grade, "a")
    }

    func testAdditiveSubVariantUsesParentAndOverrides() {
        let table = FoodAdditiveTable(entries: ["e322": .init(n: "Lecithins", r: nil), "e171": .init(n: "Titanium dioxide", r: nil)])
        XCTAssertEqual(table.additive(for: "en:e322i").name, "Lecithins")
        XCTAssertEqual(table.additive(for: "E171").risk, .high, "EU-banned additive is overridden to high")
    }

    func testBundledAdditiveTableLoads() {
        let table = FoodAdditiveTable(bundle: Bundle(for: TempoAppBundleMarker.self))
        XCTAssertFalse(table.isEmpty)
        XCTAssertEqual(table.additive(for: "e250").risk, .high)
    }
}

/// Any class from the app target, to find its bundle.
private typealias TempoAppBundleMarker = ScannedFood

// MARK: - OpenFoodFactsDecodingTests

final class OpenFoodFactsDecodingTests: XCTestCase {
    func testProductEndpointDecodes() throws {
        let json = """
        {"code":"20692285","status":1,"product":{"code":"20692285","product_name":"SKYR Ricetta Islandese",
        "product_name_it":"Skyr Naturale","brands":"Milbona, Lidl","quantity":"350 g","serving_size":"175 g",
        "serving_quantity":"175","nutriscore_grade":"a","nutriscore_score":-3,"nova_group":3,
        "additives_tags":["en:e322i"],"allergens_tags":["en:milk"],"labels_tags":["en:no-added-sugar"],
        "categories_hierarchy":["en:dairies","en:skyrs"],"ingredients_analysis_tags":["en:non-vegan"],
        "nutriments":{"energy-kcal_100g":62,"proteins_100g":11,"carbohydrates_100g":"4","sugars_100g":4,
        "fat_100g":0.2,"saturated-fat_100g":0.1,"salt_100g":0.13}}}
        """
        let envelope = try JSONDecoder().decode(OFFProductEnvelope.self, from: Data(json.utf8))
        let product = try XCTUnwrap(envelope.product?.toProduct(fallbackCode: nil, language: "it"))
        XCTAssertEqual(product.name, "Skyr Naturale", "Prefers the user's language")
        XCTAssertEqual(product.brand, "Milbona")
        XCTAssertEqual(product.servingGrams, 175)
        XCTAssertEqual(product.per100g.carbs, 4, "Numeric strings decode")
        XCTAssertEqual(product.additives, ["e322i"])
        XCTAssertEqual(product.allergens, ["milk"])
        XCTAssertEqual(product.categories.last, "skyrs")
        XCTAssertEqual(product.nutriScoreGrade, "a")
    }

    func testSearchHitArraysAndUnknownGrade() throws {
        let json = """
        {"hits":[{"code":"1","product_name":"Cola","brands":["ColaCo"],"nutriscore_grade":"unknown",
        "categories_tags":["en:beverages","en:sodas"],"nutriments":{"energy-kcal_100g":42,"proteins_100g":0,
        "carbohydrates_100g":10.6,"fat_100g":0}}]}
        """
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: Data(json.utf8))
        let product = try XCTUnwrap(response.hits.first?.toProduct(fallbackCode: nil, language: "en"))
        XCTAssertEqual(product.brand, "ColaCo")
        XCTAssertNil(product.nutriScoreGrade, "\"unknown\" is not a grade")
        XCTAssertTrue(product.isBeverage)
    }

    func testGramsFromServingLabel() {
        XCTAssertEqual(FoodProduct.grams(fromLabel: "1 pot (125 g)"), 125)
        XCTAssertEqual(FoodProduct.grams(fromLabel: "33 cl"), 330)
        XCTAssertEqual(FoodProduct.grams(fromLabel: "2,5 g"), 2.5)
        XCTAssertNil(FoodProduct.grams(fromLabel: "1 slice"))
    }
}

// MARK: - FoodFitTests

final class FoodFitTests: XCTestCase {
    func testFitsTodayAndHighProtein() {
        let checks = FoodFit.checks(for: .sample(), grams: 150, context: .init(remainingCalories: 640, remainingProtein: 60))
        XCTAssertTrue(checks.contains(.init(kind: .good, text: "Fits today: 93 kcal of 640 left")))
        XCTAssertTrue(checks.contains { $0.kind == .good && $0.text.hasPrefix("High protein") })
    }

    func testOverRemainingCaloriesWarns() {
        let checks = FoodFit.checks(for: .sample(), grams: 1000, context: .init(remainingCalories: 200))
        XCTAssertTrue(checks.contains(.init(kind: .warning, text: "620 kcal — only 200 left today")))
    }

    func testClearSkinDairyAndAllergyConflictsComeFirst() {
        var context = FoodFitContext(remainingCalories: 500)
        context.clearSkinFocus = true
        context.allergies = ["Milk"]
        let checks = FoodFit.checks(for: .sample(allergens: ["milk"]), grams: 150, context: context)
        XCTAssertEqual(checks.first, .init(kind: .conflict, text: "Contains Milk (your allergy)"))
        XCTAssertTrue(checks.contains(.init(kind: .warning, text: "Dairy — you're in clear-skin mode")))
    }

    func testVeganConflictAndUltraProcessed() {
        var context = FoodFitContext()
        context.vegan = true
        let checks = FoodFit.checks(for: .sample(analysis: ["non-vegan"], nova: 4), grams: 100, context: context)
        XCTAssertTrue(checks.contains(.init(kind: .conflict, text: "Not vegan")))
        XCTAssertTrue(checks.contains(.init(kind: .warning, text: "Ultra-processed (NOVA 4)")))
    }
}

// MARK: - NutritionLabelReaderTests

final class NutritionLabelReaderTests: XCTestCase {
    func testParsesLabelJSONAndAdditives() throws {
        let raw = """
        ```json
        {"name":"Crackers","brand":"Mulino","serving_g":30,"is_beverage":false,
         "per_100g":{"kcal":430,"protein":10,"carbs":68,"sugars":3,"fat":12,"saturated_fat":1.5,"fiber":4,"salt":1.8},
         "ingredients":"Farina di frumento, olio di girasole, agente lievitante E500ii, emulsionante: E 471, E-322",
         "allergens":["Gluten"]}
        ```
        """
        let reading = try NutritionLabelReader.parse(raw)
        XCTAssertEqual(reading.name, "Crackers")
        XCTAssertEqual(reading.servingGrams, 30)
        XCTAssertEqual(reading.per100g.kcal, 430)
        XCTAssertEqual(reading.allergens, ["gluten"])
        XCTAssertEqual(reading.additives, ["e500ii", "e471", "e322"])
    }

    func testUnreadableThrows() {
        XCTAssertThrowsError(try NutritionLabelReader.parse("I can't see a label")) { error in
            XCTAssertEqual(error as? NutritionLabelReader.ParseError, .unreadable)
        }
    }
}

// MARK: - FoodCatalogTests

@MainActor
final class FoodCatalogTests: XCTestCase {
    private final class FakeProducts: FoodProductProviding, @unchecked Sendable {
        var byBarcode: [String: FoodProduct] = [:]
        var searchResults: [FoodProduct] = []
        var alternatives: [FoodProduct] = []
        var error: Error?
        var lookups = 0

        func product(barcode: String) async throws -> FoodProduct? {
            lookups += 1
            if let error {
                throw error
            }
            return byBarcode[barcode]
        }

        func search(_: String, limit _: Int) async throws -> [FoodProduct] {
            if let error {
                throw error
            }
            return searchResults
        }

        func alternatives(for _: FoodProduct, limit _: Int) async throws -> [FoodProduct] {
            alternatives
        }
    }

    private struct FakeGeneric: GenericFoodSearching {
        var result: Result<[FoodProduct], Error>

        func search(_: String, limit _: Int) async throws -> [FoodProduct] {
            try result.get()
        }
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: ScannedFood.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testBarcodeFoundIsRecordedInHistory() async throws {
        let context = try makeContext()
        let fake = FakeProducts()
        fake.byBarcode["8000500310427"] = .sample()
        let catalog = FoodCatalog(products: fake, generic: nil)

        let result = await catalog.lookUp(barcode: "8000500310427", in: context)
        XCTAssertEqual(result, .found(.sample()))
        XCTAssertEqual(catalog.history(in: context).map(\.productID), ["8000500310427"])
    }

    func testBarcodeNotFound() async throws {
        let catalog = FoodCatalog(products: FakeProducts(), generic: nil)
        let result = try await catalog.lookUp(barcode: "123", in: makeContext())
        XCTAssertEqual(result, .notFound(barcode: "123"))
    }

    func testOfflineFallsBackToHistoryThenFails() async throws {
        let context = try makeContext()
        let fake = FakeProducts()
        let catalog = FoodCatalog(products: fake, generic: nil)
        catalog.recordView(.sample(), in: context)
        fake.error = FoodLookupError.offline

        let cached = await catalog.lookUp(barcode: "8000500310427", in: context)
        XCTAssertEqual(cached, .found(.sample()))
        let unknown = await catalog.lookUp(barcode: "999", in: context)
        XCTAssertEqual(unknown, .failed("You're offline. Connect to look up products."))
    }

    func testUserAddedProductWinsWithoutNetwork() async throws {
        let context = try makeContext()
        let fake = FakeProducts()
        let catalog = FoodCatalog(products: fake, generic: nil)
        catalog.saveUserAdded(.sample(id: "555"), photo: Data([1, 2, 3]), in: context)

        let result = await catalog.lookUp(barcode: "555", in: context)
        XCTAssertEqual(result, .found(.sample(id: "555")))
        XCTAssertEqual(fake.lookups, 0)
        XCTAssertEqual(catalog.photo(for: .sample(id: "555"), in: context), Data([1, 2, 3]))
    }

    func testSearchMergesSourcesAndSurvivesFailures() async throws {
        let context = try makeContext()
        let fake = FakeProducts()
        fake.error = FoodLookupError.offline
        let catalog = FoodCatalog(products: fake, generic: FakeGeneric(result: .failure(APIError.unauthorized)))
        catalog.recordView(.sample(), in: context)
        _ = catalog.toggleFavorite(.sample(), in: context)

        let results = await catalog.search("sky", in: context)
        XCTAssertEqual(results.yours.map(\.id), ["8000500310427"])
        XCTAssertEqual(results.notices, ["Packaged products unavailable — you're offline."], "Signed-out USDA is silent")

        let basics = await catalog.search("chicken breast", in: context)
        XCTAssertEqual(basics.basics.first?.source, .builtIn)
    }

    func testAlternativesOnlyBetterScores() async {
        let fake = FakeProducts()
        let worse = FoodProduct.sample(id: "2", grade: "d", points: 15)
        let better = FoodProduct.sample(id: "3", grade: "a", points: -5)
        fake.alternatives = [worse, better]
        let catalog = FoodCatalog(products: fake, generic: nil)

        let current = FoodProduct.sample(id: "1", grade: "c", points: 8)
        let found = await catalog.alternatives(for: current)
        XCTAssertEqual(found.map(\.id), ["3"])
    }

    func testAlternativesWithAPhotoComeFirst() async {
        let fake = FakeProducts()
        let bestNoPhoto = FoodProduct.sample(id: "2", grade: "a", points: -8)
        var goodWithPhoto = FoodProduct.sample(id: "3", grade: "b", points: 1)
        goodWithPhoto.imageURL = URL(string: "https://images.openfoodfacts.org/x.jpg")
        fake.alternatives = [bestNoPhoto, goodWithPhoto]
        let catalog = FoodCatalog(products: fake, generic: nil)

        let found = await catalog.alternatives(for: .sample(id: "1", grade: "d", points: 15))
        XCTAssertEqual(found.map(\.id), ["3", "2"])
    }

    func testUserPhotoIsSavedForAnyProduct() throws {
        let context = try makeContext()
        let catalog = FoodCatalog(products: FakeProducts(), generic: nil)
        let photo = Data([1, 2, 3])
        catalog.setPhoto(photo, for: .sample(), in: context)
        XCTAssertEqual(catalog.photo(for: .sample(), in: context), photo)

        catalog.recordView(.sample(), in: context)
        XCTAssertEqual(catalog.photo(for: .sample(), in: context), photo, "Viewing again keeps the photo")
        XCTAssertEqual(catalog.history(in: context).count, 1)
    }

    func testFavoriteToggle() throws {
        let context = try makeContext()
        let catalog = FoodCatalog(products: FakeProducts(), generic: nil)
        XCTAssertTrue(catalog.toggleFavorite(.sample(), in: context))
        XCTAssertTrue(catalog.isFavorite(.sample(), in: context))
        XCTAssertEqual(catalog.favorites(in: context).count, 1)
        XCTAssertFalse(catalog.toggleFavorite(.sample(), in: context))
    }
}

// MARK: - FoodLoggingTests

/// A scanned product logged into a meal keeps its portion maths, its source
/// and its barcode all the way to the stored MealFoodItem.
@MainActor
final class FoodLoggingTests: XCTestCase {
    func testFoodItemScalesToPortionAndKeepsBarcode() {
        let item = FoodProduct.sample().foodItem(grams: 150)
        XCTAssertEqual(item.calories, 93)
        XCTAssertEqual(item.protein, 16.5, accuracy: 0.01)
        XCTAssertEqual(item.servingSize, "150 g")
        XCTAssertEqual(item.source, .openFoodFacts)
        XCTAssertEqual(item.barcode, "8000500310427")

        let input = item.mealFoodInput
        XCTAssertEqual(input.servingSize, 150, accuracy: 0.01)
        XCTAssertEqual(input.source, .openFoodFacts)

        let stored = MealFoodItem(from: input)
        XCTAssertEqual(stored.barcode, "8000500310427")
        XCTAssertEqual(stored.offProductCode, "8000500310427")
        XCTAssertEqual(stored.dataSourceRaw, FoodDataSource.openFoodFacts.rawValue)
    }

    func testDrinkKeepsItsServingSize() {
        var cola = FoodProduct.sample(per100g: FoodProduct.Nutrients(kcal: 42, protein: 0, carbs: 10.6, sugars: 10.6, fat: 0, saturatedFat: 0, fiber: 0, salt: 0))
        cola.isBeverage = true
        let item = cola.foodItem(grams: 330)
        XCTAssertEqual(item.servingSize, "330 ml")
        XCTAssertEqual(item.mealFoodInput.servingSize, 330, accuracy: 0.01)
        XCTAssertEqual(MealFoodItem(from: item.mealFoodInput).servingSizeGrams, 330, accuracy: 0.01)
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("1 small"), 0)
    }

    func testBuiltInFoodLogsAsCachedWithoutBarcode() {
        let product = FoodCatalog.builtInProduct(name: "chicken breast", macros: FoodMacros(calories: 165, protein: 31, carbs: 0, fat: 3.6, fiber: 0))
        let stored = MealFoodItem(from: product.foodItem(grams: 200).mealFoodInput)
        XCTAssertNil(stored.barcode)
        XCTAssertNil(stored.offProductCode)
        XCTAssertEqual(stored.dataSourceRaw, FoodDataSource.cached.rawValue)
        XCTAssertEqual(stored.caloriesPerServing, 330, accuracy: 0.5)
    }

    /// Presets saved before `barcode` existed still decode.
    func testMealFoodItemInputDecodesWithoutBarcode() throws {
        let json = """
        [{"foodId":"x","name":"Oats","servings":1,"servingSize":80,"servingUnit":"g","calories":300,\
        "proteinGrams":10,"carbsGrams":54,"fatGrams":5,"source":"manual"}]
        """
        let decoded = try JSONDecoder().decode([MealFoodItemInput].self, from: Data(json.utf8))
        XCTAssertNil(decoded.first?.barcode)
    }
}

// MARK: - FoodScannerCleanupTests

final class FoodScannerCleanupTests: XCTestCase {
    func testAdditiveFamilyAndVariantCountOnce() {
        XCTAssertEqual(FoodScore.distinctAdditiveCodes(["en:e322", "en:e322i", "e330", "e330"]), ["e322i", "e330"])

        let product = FoodProduct.sample(additives: ["e433", "e433"])
        XCTAssertEqual(FoodScore.evaluate(product, additiveTable: additiveTable)?.additivePoints, 20, "One moderate additive, not two")
    }

    func testQuantityDropsEstimatedMark() {
        XCTAssertEqual(OFFRawProduct.cleanQuantity("400 g e"), "400 g")
        XCTAssertEqual(OFFRawProduct.cleanQuantity("1 l ℮"), "1 l")
        XCTAssertEqual(OFFRawProduct.cleanQuantity("6 x 125 g"), "6 x 125 g")
    }

    func testImageFolderSplitsLikeOpenFoodFacts() {
        XCTAssertEqual(OFFRawProduct.imageFolder("0076515508478"), "007/651/550/8478")
        XCTAssertEqual(OFFRawProduct.imageFolder("3017620422003"), "301/762/042/2003")
        XCTAssertEqual(OFFRawProduct.imageFolder("76515508478"), "007/651/550/8478", "Padded to 13 digits")
        XCTAssertEqual(OFFRawProduct.imageFolder("20692285"), "20692285", "Short codes stay whole")
    }

    func testFallbackImagePrefersAnyFrontThenRawUpload() throws {
        let base = "https://images.openfoodfacts.org/images/products/007/651/550/8478"
        let front = try XCTUnwrap(OFFRawProduct.fallbackImage(
            code: "0076515508478",
            images: ["front_fr": "5", "front_en": "12", "1": nil],
            language: "it"
        ))
        XCTAssertEqual(front.full.absoluteString, "\(base)/front_en.12.400.jpg")
        XCTAssertEqual(front.small.absoluteString, "\(base)/front_en.12.200.jpg")

        let raw = try XCTUnwrap(OFFRawProduct.fallbackImage(code: "0076515508478", images: ["3": nil, "1": nil], language: "en"))
        XCTAssertEqual(raw.full.absoluteString, "\(base)/1.400.jpg")
        XCTAssertEqual(raw.small.absoluteString, "\(base)/1.100.jpg")

        XCTAssertNil(OFFRawProduct.fallbackImage(code: "0076515508478", images: [:], language: "en"))
    }

    func testProductWithoutSelectedFrontGetsAFallbackPicture() throws {
        let json = """
        {"code":"0076515508478","product_name":"Peanut Butter Crunch","nutriscore_grade":"c",
        "images":{"front_de":{"rev":7},"1":{"uploaded_t":1}},
        "nutriments":{"energy-kcal_100g":500,"proteins_100g":10,"carbohydrates_100g":60,"fat_100g":25,"salt_100g":1}}
        """
        let raw = try JSONDecoder().decode(OFFRawProduct.self, from: Data(json.utf8))
        let product = try XCTUnwrap(raw.toProduct(fallbackCode: nil, language: "en"))
        XCTAssertEqual(
            product.imageURL?.absoluteString,
            "https://images.openfoodfacts.org/images/products/007/651/550/8478/front_de.7.400.jpg",
            "Numeric rev decodes too"
        )
    }

    func testPlaceholderSymbolFollowsMostSpecificCategory() {
        let peanut = FoodProduct.sample(categories: ["plant-based-foods-and-beverages", "spreads", "peanut-butters"])
        XCTAssertEqual(peanut.placeholderSymbol, "leaf.fill", "Not a drink just because of the root category")
        XCTAssertEqual(FoodProduct.sample(categories: ["beverages", "coffees"]).placeholderSymbol, "cup.and.saucer.fill")
        XCTAssertEqual(FoodProduct.sample(categories: ["unknown-thing"]).placeholderSymbol, "barcode")
    }

    func testFreeTextCategoriesAreDropped() {
        let nutella = ["en:breakfasts", "en:spreads", "en:sweet-spreads", "en:confectionary-based-spreads",
                       "en:Pâtes à tartiner", "fr:Nutella", "fr:Nuttela"]
        XCTAssertEqual(
            OFFRawProduct.taxonomyCategories(nutella),
            ["breakfasts", "spreads", "sweet-spreads", "confectionary-based-spreads"],
            "The last category drives alternatives — it must be a real one"
        )
    }

    func testAlternativesAcceptGradeCOnlyForPoorProducts() {
        XCTAssertEqual(OpenFoodFactsClient.betterGrades(than: "e"), "a OR b OR c")
        XCTAssertEqual(OpenFoodFactsClient.betterGrades(than: "D"), "a OR b OR c")
        XCTAssertEqual(OpenFoodFactsClient.betterGrades(than: "c"), "a OR b")
        XCTAssertEqual(OpenFoodFactsClient.betterGrades(than: nil), "a OR b")
    }
}
