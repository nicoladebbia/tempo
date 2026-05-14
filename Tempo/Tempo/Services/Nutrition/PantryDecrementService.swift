//
// PantryDecrementService.swift
// Tempo
//
// Created by Tempo on 14/05/2026.
//

import Foundation
import os
import SwiftData

// MARK: - PantryDecrementResult

/// Per-ingredient outcome of a pantry decrement. Callers can surface a
/// banner when items hit zero ("you're out of rolled oats — added to
/// grocery list") or roll up totals for telemetry.
struct PantryDecrementResult: Sendable {
    enum Outcome: Sendable {
        case decremented(remaining: Double)
        case depleted
        case notFound
        case skippedStaple
        case skippedNoUnitMatch
    }
    let canonicalName: String
    let requestedGrams: Double
    let outcome: Outcome
}

// MARK: - PantryDecrementService

/// Subtracts a meal's ingredients from the pantry the moment the user
/// marks it eaten. Honest about its limits:
///   - Staples (salt, olive oil, etc.) are skipped — flagged in
///     `FoodMacroDatabase.naturalPortions` with `isStaple == true`.
///   - Pantry items stored in `.grams` / `.kilograms` / `.milliliters` /
///     `.liters` are decremented directly with unit normalization.
///   - Pantry items stored in `.pieces` are decremented using the
///     natural-portion grams-per-piece (180g carrots ÷ 65g/medium = 3
///     pieces).
///   - Other units (`.servings`, `.ounces`, `.pounds`) are left alone
///     for now — they'd need their own conversion table and a stronger
///     "user intent" signal.
///
/// Callers should NOT invoke this when the user logged a substitute
/// ("ate something else") — in that case the planned ingredients weren't
/// consumed.
@MainActor
enum PantryDecrementService {
    private static let logger = Logger(subsystem: "app.tempo", category: "PantryDecrement")

    /// Decrement pantry for every required ingredient of `meal`. Returns
    /// per-ingredient outcomes so the caller can surface user-facing
    /// banners (e.g. "out of rolled oats").
    @discardableResult
    static func decrement(
        for meal: PlannedMeal,
        modelContext: ModelContext
    ) -> [PantryDecrementResult] {
        guard let ingredients = meal.recipe?.ingredients, !ingredients.isEmpty else {
            return []
        }

        // Fetch all non-archived pantry rows once and index by canonical
        // name. Pantry size is bounded (~50–150 items); a single fetch is
        // cheaper than per-ingredient predicates.
        let pantryDescriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false
            }
        )
        let pantryRows = (try? modelContext.fetch(pantryDescriptor)) ?? []
        var byName: [String: PantryItem] = [:]
        for row in pantryRows {
            byName[row.canonicalName.lowercased()] = row
        }

        var results: [PantryDecrementResult] = []
        for ingredient in ingredients where !ingredient.isOptional {
            let canonical = ingredient.canonicalFoodName.lowercased()
            let grams = ingredient.quantityGrams
            guard grams > 0 else { continue }

            // Staple? Don't decrement (you bought a jar of salt months ago).
            if FoodMacroDatabase.naturalPortions[canonical]?.isStaple == true {
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: grams,
                    outcome: .skippedStaple
                ))
                continue
            }

            guard let pantryItem = byName[canonical] else {
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: grams,
                    outcome: .notFound
                ))
                continue
            }

            let delta = convertGramsToPantryUnit(
                grams: grams,
                canonicalName: canonical,
                unit: pantryItem.unit
            )
            guard let delta else {
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: grams,
                    outcome: .skippedNoUnitMatch
                ))
                continue
            }

            let newQty = max(0, pantryItem.quantity - delta)
            pantryItem.quantity = newQty
            pantryItem.updatedAt = Date()

            if newQty <= 0 {
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: grams,
                    outcome: .depleted
                ))
            } else {
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: grams,
                    outcome: .decremented(remaining: newQty)
                ))
            }
        }

        do {
            try modelContext.save()
            logger.info("Pantry decrement for \(meal.mealName, privacy: .public): \(results.count) ingredient(s)")
        } catch {
            // A failed save leaves quantities mutated in memory but not on
            // disk; surfacing the error in the log makes a stale-pantry
            // bug debuggable instead of silently rolling back at relaunch.
            logger.error("Pantry decrement save failed for \(meal.mealName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return results
    }

    // MARK: - Unit conversion

    /// Translate a recipe gram quantity into the pantry item's stored unit.
    /// Returns nil when the unit can't be converted (caller surfaces a
    /// `skippedNoUnitMatch` result so the user can see what was missed).
    ///
    /// Conversion strategy:
    /// - Mass / volume units: direct math (g, kg, mL, L). Liquids assumed
    ///   1 g/mL (water-like) — staples like oil drift ~8% but never
    ///   decrement anyway.
    /// - Countable container units (.cans/.bottles/.jars/.packs/.pieces):
    ///   divide grams by the naturalPortion's `purchaseGrams` (which
    ///   carries the per-container weight) and round up. For `.pieces`
    ///   we fall back to the per-item `grams` field so legacy entries
    ///   that meant "1 banana ≈ 120g" still work.
    private static func convertGramsToPantryUnit(
        grams: Double,
        canonicalName: String,
        unit: PantryUnit
    ) -> Double? {
        switch unit {
        case .grams:
            return grams
        case .kilograms:
            return grams / 1000
        case .milliliters:
            return grams
        case .liters:
            return grams / 1000
        case .pieces, .cans, .bottles, .jars, .packs:
            guard let portion = FoodMacroDatabase.naturalPortions[canonicalName] else {
                return nil
            }
            // For containers, prefer purchaseGrams (the full container
            // weight). For .pieces, fall back to the recipe-side `grams`
            // since legacy entries (egg, banana) were authored that way.
            let perUnit: Double = {
                if unit == .pieces {
                    return portion.grams
                }
                return portion.purchaseGrams > 0 ? portion.purchaseGrams : portion.grams
            }()
            guard perUnit > 0 else { return nil }
            return (grams / perUnit).rounded(.up)
        case .servings, .ounces, .pounds:
            return nil
        }
    }
}
