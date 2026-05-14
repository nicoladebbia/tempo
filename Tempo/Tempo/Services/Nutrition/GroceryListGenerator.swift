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
    ///
    /// Two post-processing steps were added when this method started
    /// using the extended `FoodMacroDatabase.naturalPortions` table:
    ///
    ///   1. **Staples are skipped** when the pantry has any quantity of
    ///      them (you don't restock olive oil every week). Staples with
    ///      zero pantry quantity still surface so first-time users get
    ///      a shopping list with the basics.
    ///   2. **Gram totals are rounded up to whole purchase units** when
    ///      a portion entry is present. "180g carrots" becomes
    ///      "3 medium carrots"; the underlying gram count rides along
    ///      as a note so pantry-side macro math stays accurate.
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

        // Pantry-on-hand lookup for the staple gate. Key by canonical name.
        let pantryByName = Dictionary(
            uniqueKeysWithValues: input.pantry
                .filter { !$0.isArchived }
                .map { ($0.canonicalName.lowercased(), $0) }
        )

        // Drop fully-covered items, then rewrite remaining entries in
        // purchase units when a natural portion entry exists. Staples
        // with any pantry quantity are suppressed entirely.
        return aggregated.values
            .filter { $0.quantity > 0 }
            .compactMap { entry in
                applyPurchaseUnit(entry: entry, pantryByName: pantryByName)
            }
    }

    /// Translate a gram-denominated aggregated entry into its purchase-unit
    /// equivalent. Returns nil for staples whose pantry quantity > 0
    /// (suppressed from this week's grocery list). When no portion
    /// metadata exists, the entry is returned unchanged.
    private static func applyPurchaseUnit(
        entry: Aggregated,
        pantryByName: [String: PantryItem]
    ) -> Aggregated? {
        guard let portion = FoodMacroDatabase.naturalPortions[entry.canonicalName.lowercased()] else {
            return entry
        }

        // Staple suppression: only surface when pantry has zero of it.
        if portion.isStaple {
            let onHand = pantryByName[entry.canonicalName.lowercased()]?.quantity ?? 0
            if onHand > 0 {
                return nil
            }
            // First-time buy: show as a single purchase unit and use the
            // most accurate native PantryUnit (so the pantry row created
            // from the grocery checkoff reads as "1 jar" not "1 piece").
            return Aggregated(
                canonicalName: entry.canonicalName,
                displayName: friendlyDisplay(canonical: entry.canonicalName, qty: 1, unitWord: portion.purchaseUnit),
                quantity: 1,
                unit: pantryUnit(for: portion.purchaseUnit),
                category: entry.category
            )
        }

        // Non-staple with a purchase unit: round up to whole units and
        // store the natural label in displayName so the user reads
        // "3 medium carrots" not "3 pieces of carrot."
        let purchaseGrams = max(1, portion.purchaseGrams)
        let units = (entry.quantity / purchaseGrams).rounded(.up)
        let unitWord = units == 1 ? portion.purchaseUnit : portion.purchaseUnitPlural
        let resolvedQty = max(1, units)

        return Aggregated(
            canonicalName: entry.canonicalName,
            displayName: friendlyDisplay(canonical: entry.canonicalName, qty: Int(resolvedQty), unitWord: unitWord),
            quantity: resolvedQty,
            unit: pantryUnit(for: portion.purchaseUnit),
            category: entry.category
        )
    }

    /// Map a natural-portion `purchaseUnit` word to the canonical
    /// `PantryUnit` case. Falls back to `.pieces` for anything we don't
    /// have a native case for (yet).
    private static func pantryUnit(for purchaseUnit: String) -> PantryUnit {
        let w = purchaseUnit.lowercased()
        if w.contains("can") { return .cans }
        if w.contains("bottle") { return .bottles }
        if w.contains("jar") { return .jars }
        // Match the container-word set in ReceiptLineItem.containerPantryUnit
        // so receipt-ingested items and grocery-generated items round-trip
        // to the same PantryUnit case.
        if w.contains("pack") || w.contains("box") || w.contains("bag")
            || w.contains("tub") || w.contains("tube") || w.contains("tin") { return .packs }
        if w.contains("kg") { return .kilograms }
        if w.contains("liter") || w.contains("litre") { return .liters }
        return .pieces
    }

    /// Build the user-facing label, stripping the canonical food name
    /// when the unit word already contains it. Prevents the "3 medium
    /// carrots carrot" duplication that showed up when carrot's
    /// purchaseUnit is "medium carrot" and we naively appended the
    /// canonical name.
    private static func friendlyDisplay(canonical: String, qty: Int, unitWord: String) -> String {
        let canonLower = canonical.lowercased()
        let unitLower = unitWord.lowercased()
        if unitLower.contains(canonLower) || canonLower.contains(unitLower) {
            return "\(qty) \(unitWord)"
        }
        return "\(qty) \(unitWord) \(canonical)"
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
