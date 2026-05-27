//
// RecipeSuggestionEngine.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation

// MARK: - RecipeSuggestionInputs

struct RecipeSuggestionInputs: Sendable {
    /// Canonical food names currently in the pantry (non-archived, quantity > 0).
    let pantryCanonicalNames: Set<String>

    /// Optional days-to-expire map keyed by canonical pantry name.
    /// Negative = already expired (treated as non-urgent — don't suggest spoiled food).
    /// Missing key or empty map = no urgency weighting (backward-compatible).
    let pantryExpiryByName: [String: Int]

    /// Optional remaining macros from NutritionEngine for ranking by macro fit.
    /// All values in their natural unit (kcal, grams). Nil → skip macro ranking.
    let remainingCalories: Int?
    let remainingProtein: Int?
    let remainingCarbs: Int?
    let remainingFat: Int?

    /// When non-nil, filter recipes to a specific meal type.
    let mealTypeFilter: RecipeMealType?

    /// When `true`, recipes with missing non-optional ingredients are excluded.
    /// When `false`, recipes can have up to `maxMissingIngredients` missing and
    /// will be ranked below complete-pantry recipes.
    let requireCompletePantry: Bool

    /// Cap on missing ingredients per recipe when `requireCompletePantry` is false.
    /// When `nil` (the new default), the cap is computed per-recipe as
    /// `max(2, ceil(required * 0.6))` so a 10-ingredient recipe tolerates 6
    /// missing items while a 4-ingredient one still caps at 2. Tight pantries
    /// were silently producing zero suggestions because every candidate
    /// breached the old hard cap of 2.
    let maxMissingIngredients: Int?

    init(
        pantryCanonicalNames: Set<String>,
        pantryExpiryByName: [String: Int] = [:],
        remainingCalories: Int? = nil,
        remainingProtein: Int? = nil,
        remainingCarbs: Int? = nil,
        remainingFat: Int? = nil,
        mealTypeFilter: RecipeMealType? = nil,
        requireCompletePantry: Bool = false,
        maxMissingIngredients: Int? = nil
    ) {
        self.pantryCanonicalNames = pantryCanonicalNames
        self.pantryExpiryByName = pantryExpiryByName
        self.remainingCalories = remainingCalories
        self.remainingProtein = remainingProtein
        self.remainingCarbs = remainingCarbs
        self.remainingFat = remainingFat
        self.mealTypeFilter = mealTypeFilter
        self.requireCompletePantry = requireCompletePantry
        self.maxMissingIngredients = maxMissingIngredients
    }
}

// MARK: - RecipeSuggestion

struct RecipeSuggestion: Identifiable, Sendable {
    let id: UUID
    let recipeID: UUID
    let recipeName: String
    /// Ingredients already present in pantry (canonical names).
    let presentIngredients: [String]
    /// Ingredients missing or only available as substitutes.
    let missingIngredients: [String]
    /// 0.0–1.0 ingredient coverage (presentIngredients / required).
    let coverageScore: Double
    /// 0.0–1.0 macro alignment (1.0 = recipe matches remaining macros exactly).
    let macroAlignmentScore: Double
    /// 0.0–1.0 expiry urgency. Max over the recipe's *present* ingredients of
    /// `urgencyOf(daysToExpire)`. 0 when no expiry data, no urgent items, or
    /// all available items are well-fresh.
    let expiryUrgencyScore: Double
    /// Composite ranking score: 0.5 coverage + 0.3 macros + 0.2 urgency.
    let totalScore: Double

    init(
        recipe: Recipe,
        presentIngredients: [String],
        missingIngredients: [String],
        coverageScore: Double,
        macroAlignmentScore: Double,
        expiryUrgencyScore: Double
    ) {
        self.id = UUID()
        self.recipeID = recipe.id
        self.recipeName = recipe.name
        self.presentIngredients = presentIngredients
        self.missingIngredients = missingIngredients
        self.coverageScore = coverageScore
        self.macroAlignmentScore = macroAlignmentScore
        self.expiryUrgencyScore = expiryUrgencyScore
        self.totalScore = coverageScore * 0.5 + macroAlignmentScore * 0.3 + expiryUrgencyScore * 0.2
    }
}

// MARK: - RecipeSuggestionEngine

enum RecipeSuggestionEngine {
    /// Rank a candidate list of recipes against the inputs. Returns the top
    /// `limit` results sorted by composite score descending.
    static func rank(
        candidates: [Recipe],
        inputs: RecipeSuggestionInputs,
        limit: Int = 10
    ) -> [RecipeSuggestion] {
        let pantry = inputs.pantryCanonicalNames
        var suggestions: [RecipeSuggestion] = []

        for recipe in candidates where !recipe.isArchived {
            if let typeFilter = inputs.mealTypeFilter, recipe.mealType != typeFilter, recipe.mealType != .any {
                continue
            }

            let required = recipe.orderedIngredients.filter { !$0.isOptional }
            guard !required.isEmpty else {
                continue
            }

            var present: [String] = []
            var missing: [String] = []
            for ingredient in required {
                let canonical = ingredient.canonicalFoodName.lowercased()
                if pantry.contains(canonical) {
                    present.append(canonical)
                    continue
                }
                // Substitute hit?
                if ingredient.substitutes.contains(where: { pantry.contains($0.lowercased()) }) {
                    present.append(canonical)
                    continue
                }
                missing.append(canonical)
            }

            if inputs.requireCompletePantry, !missing.isEmpty {
                continue
            }
            if !inputs.requireCompletePantry {
                let cap = inputs.maxMissingIngredients
                    ?? max(2, Int(ceil(Double(required.count) * 0.6)))
                if missing.count > cap {
                    continue
                }
            }

            let coverage = Double(present.count) / Double(required.count)
            let macroScore = macroAlignmentScore(for: recipe, inputs: inputs)
            let urgency = expiryUrgencyScore(presentNames: present, expiryMap: inputs.pantryExpiryByName)

            suggestions.append(.init(
                recipe: recipe,
                presentIngredients: present,
                missingIngredients: missing,
                coverageScore: coverage,
                macroAlignmentScore: macroScore,
                expiryUrgencyScore: urgency
            ))
        }

        return suggestions
            .sorted { $0.totalScore > $1.totalScore }
            .prefix(limit)
            .map(\.self)
    }

    // MARK: - Macro alignment

    /// 1.0 when the recipe macros perfectly match the remaining-macro target,
    /// dropping linearly as the recipe deviates. Returns 0.5 (neutral) when
    /// any of the remaining-macro values are nil — we can't score without them.
    private static func macroAlignmentScore(for recipe: Recipe, inputs: RecipeSuggestionInputs) -> Double {
        guard let remCal = inputs.remainingCalories,
              let remProtein = inputs.remainingProtein,
              let remCarbs = inputs.remainingCarbs,
              let remFat = inputs.remainingFat
        else {
            return 0.5
        }

        // Per-macro deviation from the remaining target. We score how well a
        // single serving fits into what's left for the day.
        let calDelta = absoluteDeviation(actual: recipe.totalCalories, target: Double(remCal))
        let pDelta = absoluteDeviation(actual: recipe.totalProteinGrams, target: Double(remProtein))
        let cDelta = absoluteDeviation(actual: recipe.totalCarbsGrams, target: Double(remCarbs))
        let fDelta = absoluteDeviation(actual: recipe.totalFatGrams, target: Double(remFat))

        // Weight: calories 30%, protein 40% (prioritized), carbs 15%, fat 15%.
        let weighted = (calDelta * 0.3) + (pDelta * 0.4) + (cDelta * 0.15) + (fDelta * 0.15)
        return max(0, 1.0 - weighted)
    }

    /// Returns 0.0 when actual = target, 1.0 when actual is ≥ 2× target (or 0).
    /// Clamped to [0, 1].
    private static func absoluteDeviation(actual: Double, target: Double) -> Double {
        guard target > 0 else {
            return actual == 0 ? 0 : 1
        }
        let diff = abs(actual - target)
        return min(1.0, diff / target)
    }

    // MARK: - Expiry urgency

    /// Score for one pantry item by days-to-expire.
    /// Already expired (< 0) → 0.0 (don't surface spoiled food).
    /// 0-1 days → 1.0; 2-3 days → 0.7; 4-7 days → 0.3; 8+ days → 0.0.
    static func urgencyOf(daysToExpire: Int) -> Double {
        if daysToExpire < 0 { return 0.0 }
        if daysToExpire <= 1 { return 1.0 }
        if daysToExpire <= 3 { return 0.7 }
        if daysToExpire <= 7 { return 0.3 }
        return 0.0
    }

    /// Recipe-level urgency = max urgency across its present ingredients.
    /// Per-ingredient max (not mean) — if one ingredient expires tomorrow, the
    /// recipe should rank up even if others are fresh. Empty map or no urgent
    /// items → 0.0.
    private static func expiryUrgencyScore(
        presentNames: [String],
        expiryMap: [String: Int]
    ) -> Double {
        guard !expiryMap.isEmpty else { return 0.0 }
        var best = 0.0
        for name in presentNames {
            guard let days = expiryMap[name] else { continue }
            let u = urgencyOf(daysToExpire: days)
            if u > best { best = u }
        }
        return best
    }
}
