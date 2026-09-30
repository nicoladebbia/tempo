//
// FoodProductViewLogicTests.swift
// Tempo
//
// Pure logic behind the food-check v2 product page: the macro kcal split
// feeding the donut chart, the FoodGroup → placeholder-art symbol mapping,
// and the suggestions section title per FoodSuggestions.Kind.
//

@testable import Tempo
import XCTest

// MARK: - FoodMacroSplitTests

final class FoodMacroSplitTests: XCTestCase {
    func testComputeReturnsNilWhenAnyMacroMissing() {
        XCTAssertNil(FoodMacroSplit.compute(proteinGrams: nil, carbsGrams: 10, fatGrams: 5))
        XCTAssertNil(FoodMacroSplit.compute(proteinGrams: 10, carbsGrams: nil, fatGrams: 5))
        XCTAssertNil(FoodMacroSplit.compute(proteinGrams: 10, carbsGrams: 10, fatGrams: nil))
    }

    func testComputeReturnsNilWhenAllZero() {
        XCTAssertNil(FoodMacroSplit.compute(proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
    }

    func testComputeAppliesFourNineFourKcalPerGram() throws {
        let split = try XCTUnwrap(FoodMacroSplit.compute(proteinGrams: 10, carbsGrams: 20, fatGrams: 5))
        XCTAssertEqual(split.proteinKcal, 40, accuracy: 0.001)
        XCTAssertEqual(split.carbsKcal, 80, accuracy: 0.001)
        XCTAssertEqual(split.fatKcal, 45, accuracy: 0.001)
        XCTAssertEqual(split.totalKcal, 165, accuracy: 0.001)
    }

    func testSlicesPercentagesSumToOne() throws {
        let split = try XCTUnwrap(FoodMacroSplit.compute(proteinGrams: 9.4, carbsGrams: 3.5, fatGrams: 0.1))
        let percentSum = split.slices.reduce(0) { $0 + $1.percent }
        XCTAssertEqual(percentSum, 1, accuracy: 0.0001)
        XCTAssertEqual(split.slices.count, 3)
    }

    func testSlicesRoundTripGramsFromKcal() throws {
        let split = try XCTUnwrap(FoodMacroSplit.compute(proteinGrams: 20, carbsGrams: 30, fatGrams: 10))
        let protein = try XCTUnwrap(split.slices.first { $0.macro == .protein })
        let carbs = try XCTUnwrap(split.slices.first { $0.macro == .carbs })
        let fat = try XCTUnwrap(split.slices.first { $0.macro == .fat })
        XCTAssertEqual(protein.grams, 20, accuracy: 0.001)
        XCTAssertEqual(carbs.grams, 30, accuracy: 0.001)
        XCTAssertEqual(fat.grams, 10, accuracy: 0.001)
    }

    func testNegativeMacroTreatedAsNoData() {
        XCTAssertNil(FoodMacroSplit.compute(proteinGrams: -1, carbsGrams: 10, fatGrams: 5))
    }
}

// MARK: - FoodGroupArtTests

final class FoodGroupArtTests: XCTestCase {
    func testEverySymbolIsNonEmpty() {
        for group in FoodGroup.allCases {
            XCTAssertFalse(group.artSymbol.isEmpty, "\(group) has no art symbol")
        }
    }

    func testKeyGroupMappings() {
        XCTAssertEqual(FoodGroup.dairy.artSymbol, "cup.and.saucer.fill")
        XCTAssertEqual(FoodGroup.meat.artSymbol, "fork.knife")
        XCTAssertEqual(FoodGroup.fish.artSymbol, "fish.fill")
        XCTAssertEqual(FoodGroup.vegetables.artSymbol, "carrot.fill")
        XCTAssertEqual(FoodGroup.sweets.artSymbol, "birthday.cake.fill")
        XCTAssertEqual(FoodGroup.drinks.artSymbol, "mug.fill")
    }

    func testEveryGroupHasATint() {
        // Just confirms the switch is exhaustive and doesn't crash / fall through.
        for group in FoodGroup.allCases {
            _ = group.artTint
        }
    }
}

// MARK: - FoodSuggestionsKindTests

final class FoodSuggestionsKindTests: XCTestCase {
    func testHealthierTitle() {
        XCTAssertEqual(FoodSuggestions.Kind.healthier.sectionTitle, "Healthier swaps")
    }

    func testSimilarTitle() {
        XCTAssertEqual(FoodSuggestions.Kind.similar.sectionTitle, "Also great")
    }
}
