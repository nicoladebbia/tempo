//
// LabelFactsTests.swift
// Tempo
//
// Label page logic: UK FSA traffic-light thresholds, per-serving maths and
// the allergen-vs-profile match.
//

@testable import Tempo
import XCTest

final class LabelFactsTests: XCTestCase {
    private func product(
        serving: Double? = 30,
        beverage: Bool = false,
        nutrients: FoodProduct.Nutrients = .init(kcal: 500, protein: 10, carbs: 50, sugars: 20, fat: 20, saturatedFat: 6, fiber: 4, salt: 1)
    ) -> FoodProduct {
        FoodProduct(
            id: "1", barcode: "1", name: "Test", brand: nil, source: .openFoodFacts,
            servingGrams: serving, isBeverage: beverage, per100g: nutrients
        )
    }

    // MARK: Traffic lights

    func testSolidFatBands() {
        XCTAssertEqual(LabelFacts.level(of: .fat, per100: 3, isBeverage: false), .low)
        XCTAssertEqual(LabelFacts.level(of: .fat, per100: 3.1, isBeverage: false), .medium)
        XCTAssertEqual(LabelFacts.level(of: .fat, per100: 17.5, isBeverage: false), .medium)
        XCTAssertEqual(LabelFacts.level(of: .fat, per100: 17.6, isBeverage: false), .high)
    }

    func testSaturatesSugarsSaltBands() {
        XCTAssertEqual(LabelFacts.level(of: .saturatedFat, per100: 1.5, isBeverage: false), .low)
        XCTAssertEqual(LabelFacts.level(of: .saturatedFat, per100: 5, isBeverage: false), .medium)
        XCTAssertEqual(LabelFacts.level(of: .saturatedFat, per100: 5.1, isBeverage: false), .high)
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 5, isBeverage: false), .low)
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 22.5, isBeverage: false), .medium)
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 22.6, isBeverage: false), .high)
        XCTAssertEqual(LabelFacts.level(of: .salt, per100: 0.3, isBeverage: false), .low)
        XCTAssertEqual(LabelFacts.level(of: .salt, per100: 1.5, isBeverage: false), .medium)
        XCTAssertEqual(LabelFacts.level(of: .salt, per100: 1.51, isBeverage: false), .high)
    }

    func testDrinksUseTheLowerTable() {
        // 6 g sugar per 100 ml is medium for a drink but low for a solid.
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 6, isBeverage: true), .medium)
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 6, isBeverage: false), .medium)
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 4, isBeverage: true), .medium)
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 4, isBeverage: false), .low)
        XCTAssertEqual(LabelFacts.level(of: .sugars, per100: 11.3, isBeverage: true), .high)
    }

    func testUnknownValueHasNoLevel() {
        XCTAssertNil(LabelFacts.level(of: .salt, per100: nil, isBeverage: false))
    }

    func testProductLevelsReadPer100gNotThePortion() {
        let p = product(nutrients: .init(kcal: 500, protein: 5, carbs: 50, sugars: 30, fat: 2, saturatedFat: 1, fiber: 1, salt: 0.1))
        XCTAssertEqual(LabelFacts.level(of: .sugars, in: p), .high)
        XCTAssertEqual(LabelFacts.level(of: .fat, in: p), .low)
        XCTAssertEqual(LabelFacts.level(of: .salt, in: p), .low)
    }

    // MARK: Per serving

    func testServingMathScalesEveryNutrient() {
        let p = product(serving: 30)
        let serving = LabelFacts.nutrients(for: .perServing, product: p)
        XCTAssertEqual(serving.kcal ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(serving.protein ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(serving.fat ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(serving.saturatedFat ?? 0, 1.8, accuracy: 0.001)
        XCTAssertEqual(serving.salt ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(LabelFacts.grams(for: .perServing, product: p), 30)
    }

    func testPer100IsUntouched() {
        let p = product(serving: 30)
        XCTAssertEqual(LabelFacts.nutrients(for: .per100, product: p), p.per100g)
        XCTAssertEqual(LabelFacts.grams(for: .per100, product: p), 100)
    }

    func testNoUsableServingFallsBackTo100() {
        for serving in [nil, 0, 100] as [Double?] {
            let p = product(serving: serving)
            XCTAssertNil(LabelFacts.servingGrams(of: p))
            XCTAssertEqual(LabelFacts.nutrients(for: .perServing, product: p), p.per100g)
            XCTAssertEqual(LabelFacts.grams(for: .perServing, product: p), 100)
        }
    }

    func testMissingNutrientStaysMissingPerServing() {
        var n = FoodProduct.Nutrients(kcal: 100, protein: 1, carbs: 1, fat: 1)
        n.salt = nil
        let p = product(serving: 50, nutrients: n)
        XCTAssertNil(LabelFacts.nutrients(for: .perServing, product: p).salt)
        XCTAssertEqual(LabelFacts.nutrients(for: .perServing, product: p).kcal ?? 0, 50, accuracy: 0.001)
    }

    // MARK: Allergens

    func testDietFlagsMarkTheMatchingAllergens() {
        var context = FoodFitContext.none
        XCTAssertFalse(LabelFacts.isFlagged(displayAllergen: "Gluten", context: context))
        context.glutenFree = true
        context.nutFree = true
        XCTAssertTrue(LabelFacts.isFlagged(displayAllergen: "Gluten", context: context))
        XCTAssertTrue(LabelFacts.isFlagged(displayAllergen: "Peanuts", context: context))
        XCTAssertTrue(LabelFacts.isFlagged(displayAllergen: "Tree nuts", context: context))
        XCTAssertFalse(LabelFacts.isFlagged(displayAllergen: "Milk", context: context))
    }

    func testFreeTextAllergyMatches() {
        var context = FoodFitContext.none
        context.allergies = ["  Sesame ", "eg"]
        XCTAssertTrue(LabelFacts.isFlagged(displayAllergen: "Sesame", context: context))
        // Two-letter entries are too short to match anything.
        XCTAssertFalse(LabelFacts.isFlagged(displayAllergen: "Eggs", context: context))
    }
}
