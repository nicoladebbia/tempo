//
// RecipeSuggestionEngineTests.swift
// Tempo
//
// Covers coverage scoring, missing-ingredient limits, substitute resolution,
// meal-type filtering, and macro alignment ranking.
//

@testable import Tempo
import XCTest

@MainActor
final class RecipeSuggestionEngineTests: XCTestCase {
    // MARK: - Fixture helpers

    private func makeRecipe(
        name: String,
        ingredients: [(canonical: String, isOptional: Bool, substitutes: [String])],
        mealType: RecipeMealType = .any,
        totalCalories: Double = 500,
        totalProtein: Double = 35,
        totalCarbs: Double = 50,
        totalFat: Double = 15
    ) -> Recipe {
        let recipe = Recipe(
            name: name,
            mealType: mealType,
            totalCalories: totalCalories,
            totalProteinGrams: totalProtein,
            totalCarbsGrams: totalCarbs,
            totalFatGrams: totalFat
        )
        recipe.ingredients = ingredients.enumerated().map { idx, item in
            let ing = RecipeIngredient(
                recipe: recipe,
                orderIndex: idx,
                canonicalFoodName: item.canonical,
                displayName: item.canonical.capitalized,
                quantityGrams: 100,
                isOptional: item.isOptional,
                substitutes: item.substitutes
            )
            return ing
        }
        return recipe
    }

    // MARK: - Coverage

    func testRank_completeCoverage_ranksAboveIncomplete() {
        let chicken = makeRecipe(
            name: "Chicken & Rice",
            ingredients: [
                ("chicken breast", false, []),
                ("rice", false, []),
            ]
        )
        let salmon = makeRecipe(
            name: "Salmon Bowl",
            ingredients: [
                ("salmon", false, []),
                ("rice", false, []),
                ("avocado", false, []),
            ]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["chicken breast", "rice"],
            requireCompletePantry: false,
            maxMissingIngredients: 1
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [salmon, chicken], inputs: inputs)
        XCTAssertEqual(ranked.first?.recipeName, "Chicken & Rice")
    }

    func testRank_filtersExceedingMaxMissing() {
        let recipe = makeRecipe(
            name: "Complex",
            ingredients: [
                ("a", false, []),
                ("b", false, []),
                ("c", false, []),
                ("d", false, []),
            ]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["a"], // 3 missing
            requireCompletePantry: false,
            maxMissingIngredients: 2
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [recipe], inputs: inputs)
        XCTAssertTrue(ranked.isEmpty)
    }

    func testRank_requireCompletePantry_excludesAnyMissing() {
        let recipe = makeRecipe(
            name: "Two-Ingredient",
            ingredients: [("a", false, []), ("b", false, [])]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["a"],
            requireCompletePantry: true
        )
        XCTAssertTrue(RecipeSuggestionEngine.rank(candidates: [recipe], inputs: inputs).isEmpty)
    }

    func testRank_optionalIngredientsDoNotBlock() {
        let recipe = makeRecipe(
            name: "Optional Garnish",
            ingredients: [
                ("chicken breast", false, []),
                ("parsley", true, []),
            ]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["chicken breast"],
            requireCompletePantry: true
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [recipe], inputs: inputs)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.missingIngredients.count, 0)
    }

    func testRank_substituteResolves() {
        let recipe = makeRecipe(
            name: "Turkey Meatballs",
            ingredients: [
                ("turkey breast", false, ["chicken breast"]), // pantry has chicken; substitute matches
                ("rice", false, []),
            ]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["chicken breast", "rice"],
            requireCompletePantry: true
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [recipe], inputs: inputs)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.missingIngredients.count, 0)
    }

    // MARK: - Meal type filter

    func testRank_mealTypeFilter() {
        let breakfast = makeRecipe(
            name: "Oats",
            ingredients: [("oats", false, [])],
            mealType: .breakfast
        )
        let dinner = makeRecipe(
            name: "Steak",
            ingredients: [("ground beef", false, [])],
            mealType: .dinner
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["oats", "ground beef"],
            mealTypeFilter: .breakfast
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [breakfast, dinner], inputs: inputs)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.recipeName, "Oats")
    }

    func testRank_anyMealTypeBypassesFilter() {
        let snack = makeRecipe(
            name: "Yogurt Bowl",
            ingredients: [("greek yogurt", false, [])],
            mealType: .any
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["greek yogurt"],
            mealTypeFilter: .breakfast
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [snack], inputs: inputs)
        XCTAssertEqual(ranked.count, 1)
    }

    // MARK: - Macro alignment

    func testRank_macroAlignmentRanksCloserMatchHigher() {
        // Both have full coverage; the one closer to remaining macros should win.
        let closeMatch = makeRecipe(
            name: "Close",
            ingredients: [("chicken breast", false, []), ("rice", false, [])],
            totalCalories: 600, totalProtein: 40, totalCarbs: 70, totalFat: 15
        )
        let farMatch = makeRecipe(
            name: "Far",
            ingredients: [("chicken breast", false, []), ("rice", false, [])],
            totalCalories: 1200, totalProtein: 80, totalCarbs: 140, totalFat: 35
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["chicken breast", "rice"],
            remainingCalories: 600, remainingProtein: 40,
            remainingCarbs: 70, remainingFat: 15
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [farMatch, closeMatch], inputs: inputs)
        XCTAssertEqual(ranked.first?.recipeName, "Close")
        XCTAssertGreaterThan(ranked[0].macroAlignmentScore, ranked[1].macroAlignmentScore)
    }

    func testRank_archivedRecipesExcluded() {
        let live = makeRecipe(
            name: "Active",
            ingredients: [("oats", false, [])]
        )
        let archived = makeRecipe(
            name: "Archived",
            ingredients: [("oats", false, [])]
        )
        archived.isArchived = true
        let inputs = RecipeSuggestionInputs(pantryCanonicalNames: ["oats"])
        let ranked = RecipeSuggestionEngine.rank(candidates: [archived, live], inputs: inputs)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.recipeName, "Active")
    }

    // MARK: - Coverage score sanity

    func testRank_coverageScoreReflectsRatio() {
        let recipe = makeRecipe(
            name: "Four-ingredient",
            ingredients: [
                ("a", false, []),
                ("b", false, []),
                ("c", false, []),
                ("d", false, []),
            ]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["a", "b"],
            requireCompletePantry: false,
            maxMissingIngredients: 5
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [recipe], inputs: inputs)
        XCTAssertEqual(ranked.first?.coverageScore ?? 0, 0.5, accuracy: 0.001)
    }

    // MARK: - Expiry urgency (Pre-1 — FIFO ranking)

    func testUrgencyOf_buckets() {
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: -1), 0.0)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 0), 1.0)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 1), 1.0)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 2), 0.7)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 3), 0.7)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 4), 0.3)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 7), 0.3)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 8), 0.0)
        XCTAssertEqual(RecipeSuggestionEngine.urgencyOf(daysToExpire: 30), 0.0)
    }

    func testRank_expiryUrgencyBoostsRecipesWithExpiringItems() {
        let fresh = makeRecipe(
            name: "Fresh Pantry Bowl",
            ingredients: [
                ("rice", false, []),
                ("beans", false, []),
            ]
        )
        let urgent = makeRecipe(
            name: "Chicken Rice",
            ingredients: [
                ("chicken breast", false, []),
                ("rice", false, []),
            ]
        )
        // Same coverage (both 100%), same macros (default). Urgency tips the scale.
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["rice", "beans", "chicken breast"],
            pantryExpiryByName: ["chicken breast": 1, "rice": 30, "beans": 30]
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [fresh, urgent], inputs: inputs)
        XCTAssertEqual(ranked.first?.recipeName, "Chicken Rice")
        XCTAssertEqual(ranked.first?.expiryUrgencyScore ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(ranked.last?.expiryUrgencyScore ?? -1, 0.0, accuracy: 0.001)
    }

    func testRank_expiryUrgencyEmptyMap_noEffect() {
        // Without expiry data, scoring falls back to coverage + macros only.
        let recipeA = makeRecipe(name: "A", ingredients: [("rice", false, [])])
        let recipeB = makeRecipe(name: "B", ingredients: [("chicken breast", false, [])])
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["rice", "chicken breast"]
            // pantryExpiryByName defaults to [:]
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [recipeA, recipeB], inputs: inputs)
        XCTAssertEqual(ranked.count, 2)
        for s in ranked {
            XCTAssertEqual(s.expiryUrgencyScore, 0.0, accuracy: 0.001)
        }
    }

    func testRank_expiredItemDoesNotBoost() {
        // Already-spoiled items should not surface — urgencyOf returns 0 for negative days.
        let recipe = makeRecipe(
            name: "Old Chicken Salad",
            ingredients: [("chicken breast", false, [])]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["chicken breast"],
            pantryExpiryByName: ["chicken breast": -2]
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [recipe], inputs: inputs)
        XCTAssertEqual(ranked.first?.expiryUrgencyScore ?? -1, 0.0, accuracy: 0.001)
    }

    func testRank_expiryUrgencyTakesMaxAcrossIngredients() {
        // Recipe has one item at 1 day, one at 30 days. Score should reflect the urgent one.
        let recipe = makeRecipe(
            name: "Mixed",
            ingredients: [
                ("spinach", false, []),
                ("rice", false, []),
            ]
        )
        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: ["spinach", "rice"],
            pantryExpiryByName: ["spinach": 1, "rice": 30]
        )
        let ranked = RecipeSuggestionEngine.rank(candidates: [recipe], inputs: inputs)
        XCTAssertEqual(ranked.first?.expiryUrgencyScore ?? 0, 1.0, accuracy: 0.001)
    }
}
