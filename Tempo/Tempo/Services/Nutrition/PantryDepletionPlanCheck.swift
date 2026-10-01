//
// PantryDepletionPlanCheck.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

/// Decides whether a pantry item that just hit zero deserves a grocery-list
/// candidate, or just a "used up" chip. Per the Pantry Smarts spec: a
/// depleted item only becomes a grocery-list candidate when it's actually
/// needed again soon (still on the active plan in the next few days) —
/// otherwise every incidental staple-adjacent ingredient a meal happens to
/// finish off would spam the shopping list.
@MainActor
enum PantryDepletionPlanCheck {
    /// `true` when `canonicalName` is used by a still-`.planned` meal
    /// scheduled within `withinDays` days (inclusive of today) of `plan`.
    static func isNeededSoon(
        canonicalName: String,
        in plan: WeeklyMealPlan?,
        withinDays: Int = 3,
        now: Date = Date()
    ) -> Bool {
        guard let plan, let meals = plan.meals, !meals.isEmpty else {
            return false
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: withinDays, to: today) else {
            return false
        }
        let canonical = FoodCanonicalizer.canonicalize(canonicalName)

        for meal in meals {
            guard meal.status == .planned else {
                continue
            }
            let day = calendar.startOfDay(for: meal.dayDate)
            guard day >= today, day <= cutoff else {
                continue
            }

            if let ingredients = meal.recipe?.ingredients, !ingredients.isEmpty {
                let match = ingredients.contains {
                    FoodCanonicalizer.canonicalize($0.canonicalFoodName) == canonical
                }
                if match {
                    return true
                }
            } else {
                let match = meal.foods.contains {
                    FoodCanonicalizer.canonicalize($0.name) == canonical
                }
                if match {
                    return true
                }
            }
        }
        return false
    }

    /// Call once after a `PantryDecrementService.decrement` batch: for every
    /// `.depleted` outcome, adds it to the current week's grocery list ONLY
    /// if it's still needed by the active plan in the next few days.
    /// Otherwise the item stays depleted-but-off-list — the pantry row shows
    /// "used up" (`PantryItem.isDepleted`) instead of nagging the shopping
    /// list with something nobody's cooking again soon.
    @discardableResult
    static func handleDepletions(
        _ results: [PantryDecrementResult],
        weeklyPlan: WeeklyMealPlan?,
        modelContext: ModelContext
    ) -> Int {
        var added = 0
        for result in results {
            guard case .depleted = result.outcome else {
                continue
            }
            guard isNeededSoon(canonicalName: result.canonicalName, in: weeklyPlan) else {
                continue
            }
            let displayName = FoodCanonicalizer.displayName(result.canonicalName)
            let restock = PantryGroceryBridge.restockDefault(canonicalName: result.canonicalName)
            if (try? PantryGroceryBridge.addToCurrentGroceryList(
                canonicalName: result.canonicalName,
                displayName: displayName.isEmpty ? result.canonicalName : displayName,
                quantity: restock.quantity,
                unit: restock.unit,
                modelContext: modelContext
            )) != nil {
                added += 1
            }
        }
        return added
    }
}
