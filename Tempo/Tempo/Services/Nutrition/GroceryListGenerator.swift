//
// GroceryListGenerator.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

enum GroceryListGenerator {
    // MARK: - Inputs

    struct GeneratorInput {
        /// Source weekly plan. Required: items pull from each meal's `foods`.
        let mealPlan: WeeklyMealPlan
        /// Current non-archived pantry items.
        let pantry: [PantryItem]
        /// Week start to stamp on the resulting list.
        let weekStartDate: Date
    }

    /// Aggregated entry pre-persist.
    struct Aggregated {
        var canonicalName: String
        var displayName: String
        var quantity: Double
        var unit: PantryUnit
        var category: String
    }

    // MARK: - Generate

    /// Build aggregated grocery entries. Caller persists them on a new
    /// `GroceryList` via `GroceryListService`.
    static func generate(from input: GeneratorInput) -> [Aggregated] {
        var aggregated: [String: Aggregated] = [:]

        for meal in input.mealPlan.meals ?? [] {
            for food in meal.foods {
                let canonical = FoodCanonicalizer.canonicalize(food.name)
                guard !canonical.isEmpty else {
                    continue
                }
                let display = FoodCanonicalizer.displayName(food.name)
                let unit: PantryUnit = .grams
                let qty = food.quantityGrams

                if var existing = aggregated[canonical] {
                    existing.quantity += qty
                    aggregated[canonical] = existing
                } else {
                    aggregated[canonical] = .init(
                        canonicalName: canonical,
                        displayName: display.isEmpty ? food.name.capitalized : display,
                        quantity: qty,
                        unit: unit,
                        category: category(for: canonical)
                    )
                }
            }
        }

        // Subtract pantry on-hand.
        for pantryItem in input.pantry where !pantryItem.isArchived {
            let canonical = pantryItem.canonicalName
            guard var entry = aggregated[canonical], entry.unit == pantryItem.unit else {
                continue
            }
            entry.quantity = max(0, entry.quantity - pantryItem.quantity)
            aggregated[canonical] = entry
        }

        // Drop fully-covered items.
        return aggregated.values.filter { $0.quantity > 0 }
    }

    // MARK: - Category heuristic

    /// Coarse grocery-aisle categorization. Used for sort/group in the UI and
    /// matches the categories Apple Reminders shows.
    static func category(for canonicalName: String) -> String {
        let n = canonicalName.lowercased()
        let produce = [
            "banana",
            "berries",
            "spinach",
            "broccoli",
            "asparagus",
            "kiwi",
            "avocado",
            "orange",
            "lemon",
            "bell pepper",
            "ginger",
            "sweet potato",
        ]
        let protein = ["chicken breast", "salmon", "ground beef", "ground turkey", "turkey breast", "protein powder", "eggs"]
        let dairy = ["greek yogurt", "milk", "cheese"]
        let grains = ["rice", "oats", "rice cakes"]
        let frozen = ["frozen", "ice"]
        let oils = ["olive oil"]

        if produce.contains(where: n.contains) {
            return "produce"
        }
        if protein.contains(where: n.contains) {
            return "protein"
        }
        if dairy.contains(where: n.contains) {
            return "dairy"
        }
        if grains.contains(where: n.contains) {
            return "grains"
        }
        if frozen.contains(where: n.contains) {
            return "frozen"
        }
        if oils.contains(where: n.contains) {
            return "oils"
        }
        return "pantry"
    }
}
