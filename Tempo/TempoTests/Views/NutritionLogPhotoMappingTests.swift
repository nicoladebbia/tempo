//
// NutritionLogPhotoMappingTests.swift
// Tempo
//
// Locks the lossy hop where a photo-analysis FoodItem's serving-size string
// is reduced to grams for ParsedFoodItem. Vision portions ("1 cup", "diced")
// aren't reliably grams, so the contract is: parse grams only when the unit
// IS grams, else 0 (quantityGrams is cosmetic — calories/macros carry through
// regardless). A regression here would silently feed wrong serving sizes into
// the logged meal.
//

@testable import Tempo
import XCTest

final class NutritionLogPhotoMappingTests: XCTestCase {

    func testGramsFromServingSize_plainGrams() {
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("250g"), 250)
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("250 g"), 250)
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("100G"), 100)
    }

    func testGramsFromServingSize_decimalGrams() {
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("12.5 g"), 12.5, accuracy: 0.001)
    }

    func testGramsFromServingSize_nonGramUnits_returnZero() {
        // These are real vision outputs — none are reliably gram-convertible,
        // so they must yield 0 rather than a fabricated weight.
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("1 cup"), 0)
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("diced"), 0)
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("1 medium"), 0)
        XCTAssertEqual(NutritionLogView.gramsFromServingSize(""), 0)
    }

    func testGramsFromServingSize_gramsInGranolaWord_doesNotFalseMatchNumberlessString() {
        // "granola" contains 'g' but no number → 0, not a crash.
        XCTAssertEqual(NutritionLogView.gramsFromServingSize("granola"), 0)
    }
}
