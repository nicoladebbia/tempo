//
// FoodPortionLabelTests.swift
// Tempo
//
// Phase 4 — whole-unit ingredient display. Countable foods (eggs, bananas)
// must read as whole units ("5 eggs"), never grams ("250 g eggs"), even when
// an AI-provided household label tried to use grams. Non-countable foods
// (rice, mince) keep their AI label / gram fallback.
//

@testable import Tempo
import XCTest

final class FoodPortionLabelTests: XCTestCase {

    // MARK: - isCountable

    func testCountableFoods() {
        XCTAssertTrue(FoodMacroDatabase.isCountable(food: "eggs"))
        XCTAssertTrue(FoodMacroDatabase.isCountable(food: "banana"))
        XCTAssertTrue(FoodMacroDatabase.isCountable(food: "apple"))
        XCTAssertTrue(FoodMacroDatabase.isCountable(food: "carrot"))
    }

    func testNonCountableFoods() {
        // Rice is measured in cups (volume), not whole units.
        XCTAssertFalse(FoodMacroDatabase.isCountable(food: "rice"))
        XCTAssertFalse(FoodMacroDatabase.isCountable(food: "rolled oats"))
        // Unknown foods are never countable.
        XCTAssertFalse(FoodMacroDatabase.isCountable(food: "zzz mystery food"))
    }

    // MARK: - Whole-unit wins for countable foods

    func testEggsRenderAsWholeUnits() {
        // 250 g / 50 g per egg = 5 eggs.
        XCTAssertEqual(
            FoodMacroDatabase.bestPortionLabel(food: "eggs", grams: 250, aiLabel: nil),
            "5 eggs"
        )
    }

    func testCountableOverridesGramyAILabel() {
        // The AI emitted a gram string; the whole-unit form must win.
        let label = FoodMacroDatabase.bestPortionLabel(
            food: "eggs", grams: 150, aiLabel: "150 g eggs"
        )
        XCTAssertEqual(label, "3 eggs", "Countable foods ignore a gram-y AI label")
    }

    func testSingleUnitIsSingular() {
        XCTAssertEqual(
            FoodMacroDatabase.bestPortionLabel(food: "banana", grams: 120, aiLabel: nil),
            "1 banana"
        )
    }

    // MARK: - Non-countable foods keep the AI label, else grams

    func testNonCountableKeepsAILabel() {
        let label = FoodMacroDatabase.bestPortionLabel(
            food: "rice", grams: 185, aiLabel: "1 cup"
        )
        XCTAssertEqual(label, "1 cup", "Non-countable foods keep the household AI label")
    }

    func testNonCountableFallsBackToGrams() {
        let label = FoodMacroDatabase.bestPortionLabel(
            food: "ground beef", grams: 200, aiLabel: nil
        )
        XCTAssertTrue(label.contains("200") || label.lowercased().contains("g"),
                      "With no AI label, a mass food falls back to grams: \(label)")
    }
}
