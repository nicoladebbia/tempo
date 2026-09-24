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
        // Eating window is now expressed as OUTER BOUNDS, not a per-meal
        // anchor (so it doesn't fight the wake-derived observed_meal_times).
        XCTAssertTrue(block.contains("no meal before 08:00"))
        XCTAssertTrue(block.contains("or after 20:00"))
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

    // MARK: - Pantry stock block (§3 pantry-first)

    func testPantryStockBlock_emptyReturnsEmptyString() {
        XCTAssertEqual(MealPlanPrompts.pantryStockBlock([]), "")
    }

    func testPantryStockBlock_listsItemsAndQuantityRespect() {
        let block = MealPlanPrompts.pantryStockBlock([
            "eggs — 9 pieces [Fridge]",
            "rolled oats — 500 g [Pantry]",
        ])
        XCTAssertTrue(block.contains("<pantry_on_hand>"))
        XCTAssertTrue(block.contains("eggs — 9 pieces [Fridge]"))
        XCTAssertTrue(block.contains("rolled oats — 500 g [Pantry]"))
        // Still lists what the user ALREADY HAS and respects quantities…
        XCTAssertTrue(block.uppercased().contains("ALREADY HAS"))
        XCTAssertTrue(block.lowercased().contains("do not plan to use more"))
        // …but pantry is now a TIEBREAKER, not the primary constraint (the
        // chicken-pasta-monotony fix). The detailed tiebreaker/variety
        // assertions live in testPantryBlock_isTiebreakerNotPrimaryConstraint.
    }

    func testWeeklyPlanPrompt_includesPantryStockWhenProvided() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(
            isLactoseFree: false, noCoffee: false, isGlutenFree: false,
            isVegetarian: false, isVegan: false, isHalal: false,
            isNutFree: false, isShellFishAllergy: false,
            allergies: [], dislikedFoods: []
        )
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:],
            restrictions: restrictions,
            preferences: "",
            pantryStock: ["chicken breast — 3 pieces [Freezer]"]
        )
        XCTAssertTrue(userPrompt.contains("<pantry_on_hand>"))
        XCTAssertTrue(userPrompt.contains("chicken breast — 3 pieces [Freezer]"))
        // Pantry stock must precede meal_structure (it's input, not output).
        guard let pantryIdx = userPrompt.range(of: "<pantry_on_hand>")?.lowerBound,
              let structureIdx = userPrompt.range(of: "<meal_structure>")?.lowerBound
        else {
            XCTFail("Expected both <pantry_on_hand> and <meal_structure>")
            return
        }
        XCTAssertLessThan(pantryIdx, structureIdx)
    }

    func testWeeklyPlanPrompt_omitsPantryStockWhenEmpty() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(
            isLactoseFree: false, noCoffee: false, isGlutenFree: false,
            isVegetarian: false, isVegan: false, isHalal: false,
            isNutFree: false, isShellFishAllergy: false,
            allergies: [], dislikedFoods: []
        )
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:],
            restrictions: restrictions,
            preferences: ""
        )
        XCTAssertFalse(userPrompt.contains("<pantry_on_hand>"),
                       "No pantry block when stock is empty")
    }

    // MARK: - Functional nutrition layer (v2)

    func testFunctionalNutritionBlock_leadsWithLowGLAndSkin() {
        let block = MealPlanPrompts.functionalNutritionBlock(clearSkinFocus: true)
        XCTAssertTrue(block.contains("<functional_nutrition>"))
        XCTAssertTrue(block.contains("</functional_nutrition>"))
        // Low-GL is the headline lever, and must be tied to skin.
        XCTAssertTrue(block.uppercased().contains("LOW GLYCEMIC LOAD"))
        XCTAssertTrue(block.lowercased().contains("skin"))
    }

    func testFunctionalNutritionBlock_minimizesDairyForAcne() {
        let block = MealPlanPrompts.functionalNutritionBlock(clearSkinFocus: true)
        XCTAssertTrue(block.uppercased().contains("MINIMIZE DAIRY"))
        // Must offer non-dairy protein routes so it can actually comply.
        XCTAssertTrue(block.lowercased().contains("non-dairy"))
    }

    func testFunctionalNutritionBlock_carriesAbsorptionRules() {
        let block = MealPlanPrompts.functionalNutritionBlock()
        // Fat pairing for fat-soluble nutrients, and cooked tomato for lycopene.
        XCTAssertTrue(block.lowercased().contains("fat-soluble"))
        XCTAssertTrue(block.lowercased().contains("lycopene"))
        XCTAssertTrue(block.lowercased().contains("cooked"))
    }

    func testFunctionalNutritionBlock_periodizesAntioxidantsByDayType() {
        let block = MealPlanPrompts.functionalNutritionBlock()
        // The anti-blunting rule: don't load antioxidants on hard strength days.
        XCTAssertTrue(block.lowercased().contains("strength"))
        XCTAssertTrue(block.lowercased().contains("adaptation"))
    }

    func testPantryBlock_isTiebreakerNotPrimaryConstraint() {
        // Regression guard for the chicken-pasta monotony: pantry must NOT say
        // "build primarily around stock" (that drained variety). It's a
        // tiebreaker, and the grocery list should carry real items.
        let block = MealPlanPrompts.pantryStockBlock(["chicken breast — 3 pieces [Freezer]"])
        XCTAssertTrue(block.lowercased().contains("tiebreaker"))
        XCTAssertTrue(block.uppercased().contains("VARIETY AND NUTRITION COME FIRST"))
        XCTAssertFalse(block.lowercased().contains("primarily around this stock"),
                       "The pantry-drain directive must be gone")
    }

    func testFunctionalNutritionBlock_enforcesVarietyAndProteinRotation() {
        let block = MealPlanPrompts.functionalNutritionBlock()
        XCTAssertTrue(block.uppercased().contains("VARIETY IS MANDATORY"))
        XCTAssertTrue(block.lowercased().contains("rotate proteins"))
        // Functional foods must be a floor (actually appear), not just allowed.
        XCTAssertTrue(block.lowercased().contains("must actually appear"))
    }

    func testFunctionalNutritionBlock_bansAddedSweeteners() {
        let block = MealPlanPrompts.functionalNutritionBlock(clearSkinFocus: true)
        XCTAssertTrue(block.uppercased().contains("NO ADDED SUGARS"))
        XCTAssertTrue(block.lowercased().contains("honey"))
        // Applies even if the sweetener is in the pantry.
        XCTAssertTrue(block.lowercased().contains("even if such an item is in the pantry"))
    }

    func testFunctionalNutritionBlock_doesNotPromiseToCureSkin() {
        let block = MealPlanPrompts.functionalNutritionBlock(clearSkinFocus: true)
        // Must NOT over-promise — no "cure" / "fix" claims about the condition.
        XCTAssertTrue(block.lowercased().contains("never claim to cure"))
    }

    func testWeeklyPlanPrompt_includesFunctionalBlockBeforeMealStructure() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(
            isLactoseFree: false, noCoffee: false, isGlutenFree: false,
            isVegetarian: false, isVegan: false, isHalal: false,
            isNutFree: false, isShellFishAllergy: false,
            allergies: [], dislikedFoods: []
        )
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:],
            restrictions: restrictions,
            preferences: ""
        )
        guard let funcIdx = userPrompt.range(of: "<functional_nutrition>")?.lowerBound,
              let structureIdx = userPrompt.range(of: "<meal_structure>")?.lowerBound
        else {
            XCTFail("Expected both <functional_nutrition> and <meal_structure>")
            return
        }
        XCTAssertLessThan(funcIdx, structureIdx,
                          "functional block is input, must precede meal_structure")
    }

    // MARK: - Satiety signal in feedback block (Piece 4)

    func testFeedbackBlock_rendersFullnessAndScaleDownRule() {
        let digest = MealPlanPrompts.FeedbackDigest(
            recipes: [
                .init(
                    recipeName: "Chicken & Rice Bowl",
                    averageRating: 4,
                    mentionCount: 3,
                    notes: [],
                    portionNotes: [],
                    suggestedChanges: [],
                    feelCounts: [:],
                    satietyCounts: ["too_much": 3, "just_right": 1],
                    substituteNotes: []
                ),
            ],
            ingredients: []
        )
        let block = MealPlanPrompts.feedbackBlock(digest)
        // The counts surface…
        XCTAssertTrue(block.contains("fullness:"))
        XCTAssertTrue(block.contains("too_much 3×"))
        // …and the PRIMARY scale-DOWN rule is present.
        XCTAssertTrue(block.uppercased().contains("SCALE DOWN"))
        XCTAssertTrue(block.lowercased().contains("too_much"))
        // …never starving the day to honor fullness.
        XCTAssertTrue(block.lowercased().contains("never push a day below"))
    }

    // MARK: - Meal-timing windows + ordering

    func testWeeklyPlanPrompt_definesMealWindowsAndHardOrdering() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(
            isLactoseFree: false, noCoffee: false, isGlutenFree: false,
            isVegetarian: false, isVegan: false, isHalal: false,
            isNutFree: false, isShellFishAllergy: false,
            allergies: [], dislikedFoods: []
        )
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: ""
        )
        // Dinner has an evening window and a floor (the bug: dinner was moved to
        // the afternoon to fit a snack).
        XCTAssertTrue(userPrompt.contains("19:30–21:00"))
        XCTAssertTrue(userPrompt.lowercased().contains("never earlier than 19:00"))
        // The hard chronological-ordering rule + the after-dinner snack rule.
        XCTAssertTrue(userPrompt.uppercased().contains("HARD ORDERING RULE"))
        XCTAssertTrue(userPrompt.lowercased().contains("always after dinner, never before"))
    }

    // MARK: - Taste preferences (favorites + bored-of) — Phase 2

    func testTastePreferencesBlock_emptyWhenNeitherSet() {
        let r = MealPlanPrompts.DietaryRestrictions()
        XCTAssertEqual(r.tastePreferencesBlock, "")
    }

    func testTastePreferencesBlock_rendersFavoritesAndBoredOf() {
        let r = MealPlanPrompts.DietaryRestrictions(
            favoriteFoods: ["salmon", "Mediterranean"],
            boredOfFoods: ["chicken"]
        )
        let block = r.tastePreferencesBlock
        XCTAssertTrue(block.contains("<taste_preferences>"))
        XCTAssertTrue(block.uppercased().contains("LOVES"))
        XCTAssertTrue(block.contains("salmon"))
        XCTAssertTrue(block.contains("Mediterranean"))
        XCTAssertTrue(block.uppercased().contains("BORED OF"))
        XCTAssertTrue(block.contains("chicken"))
        XCTAssertTrue(block.lowercased().contains("do not overuse"))
    }

    func testTastePreferencesBlock_favoritesOnly() {
        let r = MealPlanPrompts.DietaryRestrictions(favoriteFoods: ["eggs"])
        let block = r.tastePreferencesBlock
        XCTAssertTrue(block.contains("eggs"))
        XCTAssertFalse(block.uppercased().contains("BORED OF"))
    }

    func testWeeklyPlanPrompt_includesTasteBlockWhenSet() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(favoriteFoods: ["tofu"])
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: ""
        )
        XCTAssertTrue(userPrompt.contains("<taste_preferences>"))
        XCTAssertTrue(userPrompt.contains("tofu"))
    }

    func testWeeklyPlanPrompt_omitsTasteBlockWhenUnset() {
        let restrictions = MealPlanPrompts.DietaryRestrictions()
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: ""
        )
        XCTAssertFalse(userPrompt.contains("<taste_preferences>"))
    }

    // MARK: - Meal count + cook-time directives — Phase 3

    func testMealCountDirective_emptyWhenNil() {
        XCTAssertEqual(MealPlanPrompts.mealCountDirective(nil), "")
    }

    func testMealCountDirective_emptyWhenOutOfRange() {
        XCTAssertEqual(MealPlanPrompts.mealCountDirective(2), "")
        XCTAssertEqual(MealPlanPrompts.mealCountDirective(9), "")
    }

    func testMealCountDirective_setsExactCount() {
        let d = MealPlanPrompts.mealCountDirective(3)
        XCTAssertTrue(d.uppercased().contains("MEAL COUNT"))
        XCTAssertTrue(d.contains("EXACTLY 3"))
        XCTAssertTrue(d.lowercased().contains("overrides"))
    }

    func testCookTimeDirective_emptyWhenBothNil() {
        XCTAssertEqual(MealPlanPrompts.cookTimeDirective(weekday: nil, weekend: nil), "")
    }

    func testCookTimeDirective_weekdayOnly() {
        let d = MealPlanPrompts.cookTimeDirective(weekday: 15, weekend: nil)
        XCTAssertTrue(d.uppercased().contains("COOK-TIME BUDGET"))
        XCTAssertTrue(d.contains("weekdays ≤ 15 min"))
        XCTAssertFalse(d.contains("weekend"))
    }

    func testCookTimeDirective_both() {
        let d = MealPlanPrompts.cookTimeDirective(weekday: 15, weekend: 45)
        XCTAssertTrue(d.contains("weekdays ≤ 15 min"))
        XCTAssertTrue(d.contains("weekends ≤ 45 min"))
    }

    func testWeeklyPlanPrompt_includesMealCountAndCookTimeWhenSet() {
        let restrictions = MealPlanPrompts.DietaryRestrictions()
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: "",
            mealsPerDay: 3, cookTimeWeekdayMins: 15, cookTimeWeekendMins: 45
        )
        XCTAssertTrue(userPrompt.contains("EXACTLY 3"))
        XCTAssertTrue(userPrompt.contains("weekdays ≤ 15 min"))
    }

    func testWeeklyPlanPrompt_omitsMealPrefsWhenUnset() {
        let restrictions = MealPlanPrompts.DietaryRestrictions()
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: ""
        )
        XCTAssertFalse(userPrompt.contains("MEAL COUNT"))
        XCTAssertFalse(userPrompt.contains("COOK-TIME BUDGET"))
    }

    func testWeeklyPlanPrompt_safetyAllowsOwnedSupplementsButNotBuying() {
        let restrictions = MealPlanPrompts.DietaryRestrictions(
            isLactoseFree: false, noCoffee: false, isGlutenFree: false,
            isVegetarian: false, isVegan: false, isHalal: false,
            isNutFree: false, isShellFishAllergy: false,
            allergies: [], dislikedFoods: []
        )
        let (system, _) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:],
            restrictions: restrictions,
            preferences: ""
        )
        // Still forbids recommending products the user doesn't own…
        XCTAssertTrue(system.lowercased().contains("does not own"))
        // …but no longer a blanket "NEVER recommend supplements" (Piece 2 needs
        // the shelf path open).
        XCTAssertFalse(system.contains("NEVER recommend specific supplements, brands, or products."))
    }

    // MARK: - Kitchen equipment (Phase 4)

    func testEquipmentBlock_emptyWhenNoAppliances() {
        XCTAssertEqual(MealPlanPrompts.equipmentBlock([]), "")
    }

    func testEquipmentBlock_emptyWhenAllBlank() {
        // Whitespace-only entries sanitize away → still empty.
        XCTAssertEqual(MealPlanPrompts.equipmentBlock(["", "   "]), "")
    }

    func testEquipmentBlock_listsAppliancesAndConstrains() {
        let block = MealPlanPrompts.equipmentBlock(["Stovetop", "Air fryer"])
        XCTAssertTrue(block.contains("<equipment>"))
        XCTAssertTrue(block.contains("Stovetop, Air fryer"))
        XCTAssertTrue(block.contains("ONLY these appliances"))
    }

    func testWeeklyPlanPrompt_includesEquipmentWhenSet() {
        let restrictions = MealPlanPrompts.DietaryRestrictions()
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: "",
            equipment: ["Stovetop", "Rice cooker"]
        )
        XCTAssertTrue(userPrompt.contains("<equipment>"))
        XCTAssertTrue(userPrompt.contains("Stovetop, Rice cooker"))
    }

    func testWeeklyPlanPrompt_omitsEquipmentWhenUnset() {
        let restrictions = MealPlanPrompts.DietaryRestrictions()
        let (_, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: ""
        )
        XCTAssertFalse(userPrompt.contains("<equipment>"))
    }
}
