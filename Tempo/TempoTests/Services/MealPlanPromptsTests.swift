//
// MealPlanPromptsTests.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

@testable import Tempo
import XCTest

final class MealPlanPromptsTests: XCTestCase {
    // MARK: - weeklyIntakeBlock

    func testWeeklyIntakeBlock_nilIntake_returnsEmptyString() {
        let block = MealPlanPrompts.weeklyIntakeBlock(nil)
        XCTAssertTrue(block.isEmpty)
    }

    func testWeeklyIntakeBlock_minimalIntake_includesCoreFields() {
        let intake = MealPlanIntake(
            cookableDaysThisWeek: 3,
            leftoverTolerance: .twoToThreeDayBatches,
            eatingWindow: EatingWindow(firstMealHour: 8, lastMealHour: 20),
            groceryIntent: nil,
            recoveryAdjusted: false,
            temporaryExclusions: []
        )
        let block = MealPlanPrompts.weeklyIntakeBlock(intake)
        XCTAssertTrue(block.contains("<weekly_intake>"))
        XCTAssertTrue(block.contains("</weekly_intake>"))
        XCTAssertTrue(block.contains("Cookable days this week: 3"))
        XCTAssertTrue(block.contains("2-3 consecutive days"))
        XCTAssertTrue(block.contains("First meal anchored at 08:00"))
        XCTAssertTrue(block.contains("Last meal anchored at 20:00"))
    }

    func testWeeklyIntakeBlock_omitsOptionalFieldsWhenAbsent() {
        let intake = MealPlanIntake(
            cookableDaysThisWeek: 5,
            leftoverTolerance: .fullWeekPrep,
            eatingWindow: .default,
            groceryIntent: nil,
            recoveryAdjusted: false,
            temporaryExclusions: []
        )
        let block = MealPlanPrompts.weeklyIntakeBlock(intake)
        XCTAssertFalse(block.contains("Grocery context"))
        XCTAssertFalse(block.contains("Off-limits this week"))
        XCTAssertFalse(block.contains("Adjust calorie distribution"))
    }

    func testWeeklyIntakeBlock_includesGroceryWhenPresent() {
        let intake = MealPlanIntake(
            cookableDaysThisWeek: 4,
            leftoverTolerance: .freshDaily,
            eatingWindow: .default,
            groceryIntent: GroceryIntent(
                willShopThisWeek: true,
                budgetCapUSD: 80,
                preferredStores: ["Publix"]
            ),
            recoveryAdjusted: false,
            temporaryExclusions: []
        )
        let block = MealPlanPrompts.weeklyIntakeBlock(intake)
        XCTAssertTrue(block.contains("Grocery context"))
        XCTAssertTrue(block.contains("$80"))
        XCTAssertTrue(block.contains("Publix"))
    }

    func testWeeklyIntakeBlock_pantryOnlyContext() {
        let intake = MealPlanIntake(
            cookableDaysThisWeek: 4,
            leftoverTolerance: .twoToThreeDayBatches,
            eatingWindow: .default,
            groceryIntent: GroceryIntent(willShopThisWeek: false, budgetCapUSD: nil, preferredStores: []),
            recoveryAdjusted: false,
            temporaryExclusions: []
        )
        let block = MealPlanPrompts.weeklyIntakeBlock(intake)
        XCTAssertTrue(block.contains("NOT shopping"))
        XCTAssertTrue(block.contains("current pantry"))
    }

    func testWeeklyIntakeBlock_includesRecoveryWhenAdjusted() {
        var intake = MealPlanIntake.default
        intake.recoveryAdjusted = true
        let block = MealPlanPrompts.weeklyIntakeBlock(intake)
        XCTAssertTrue(block.contains("Adjust calorie distribution"))
    }

    func testWeeklyIntakeBlock_includesTemporaryExclusions() {
        var intake = MealPlanIntake.default
        intake.temporaryExclusions = ["broccoli", "salmon"]
        let block = MealPlanPrompts.weeklyIntakeBlock(intake)
        XCTAssertTrue(block.contains("Off-limits this week"))
        XCTAssertTrue(block.contains("broccoli"))
        XCTAssertTrue(block.contains("salmon"))
    }

    // MARK: - weeklyPlanPrompt integration

    func testWeeklyPlanPrompt_withNilIntake_emitsEmptyIntakeBlock() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(
            isLactoseFree: false,
            noCoffee: false,
            isGlutenFree: false,
            isVegetarian: false,
            isVegan: false,
            isHalal: false,
            isNutFree: false,
            isShellFishAllergy: false,
            allergies: [],
            dislikedFoods: []
        )
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:],
            restrictions: restrictions,
            preferences: "",
            intake: nil
        )
        XCTAssertFalse(userPrompt.contains("<weekly_intake>"))
        XCTAssertTrue(userPrompt.contains("<meal_structure>"))
    }

    func testWeeklyPlanPrompt_withIntake_placesBlockBeforeMealStructure() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(
            isLactoseFree: false, noCoffee: false, isGlutenFree: false,
            isVegetarian: false, isVegan: false, isHalal: false,
            isNutFree: false, isShellFishAllergy: false,
            allergies: [], dislikedFoods: []
        )
        let intake = MealPlanIntake.default
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:],
            restrictions: restrictions,
            preferences: "",
            intake: intake
        )
        guard let intakeIdx = userPrompt.range(of: "<weekly_intake>")?.lowerBound,
              let structureIdx = userPrompt.range(of: "<meal_structure>")?.lowerBound
        else {
            XCTFail("Expected both <weekly_intake> and <meal_structure> in user prompt")
            return
        }
        XCTAssertLessThan(intakeIdx, structureIdx, "intake block must precede meal_structure")
    }
}
