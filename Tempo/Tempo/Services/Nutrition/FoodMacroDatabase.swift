//
// FoodMacroDatabase.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation

// MARK: - FoodMacros

struct FoodMacros {
    let calories: Double // per 100g
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double

    /// Scale macros from per-100g to a specific weight.
    func scaled(to grams: Double) -> FoodMacros {
        let factor = grams / 100.0
        return FoodMacros(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            fiber: fiber * factor
        )
    }
}

// MARK: - FoodMacroDatabase

enum FoodMacroDatabase {
    // MARK: - Macro Data (per 100g raw/uncooked weight)

    static let macrosPer100g: [String: FoodMacros] = [
        // ── Proteins ──────────────────────────────────────────────
        "chicken breast": FoodMacros(calories: 165, protein: 31.0, carbs: 0.0, fat: 3.6, fiber: 0.0),
        "chicken thigh": FoodMacros(calories: 209, protein: 26.0, carbs: 0.0, fat: 10.9, fiber: 0.0),
        "salmon": FoodMacros(calories: 208, protein: 20.4, carbs: 0.0, fat: 13.4, fiber: 0.0),
        "tuna": FoodMacros(calories: 132, protein: 28.2, carbs: 0.0, fat: 1.3, fiber: 0.0),
        "tuna canned": FoodMacros(calories: 116, protein: 25.5, carbs: 0.0, fat: 0.8, fiber: 0.0),
        "eggs": FoodMacros(calories: 155, protein: 13.0, carbs: 1.1, fat: 11.0, fiber: 0.0),
        "egg whites": FoodMacros(calories: 52, protein: 10.9, carbs: 0.7, fat: 0.2, fiber: 0.0),
        "turkey breast": FoodMacros(calories: 135, protein: 30.0, carbs: 0.0, fat: 1.0, fiber: 0.0),
        "ground turkey": FoodMacros(calories: 170, protein: 27.0, carbs: 0.0, fat: 6.5, fiber: 0.0),
        "beef sirloin": FoodMacros(calories: 210, protein: 26.0, carbs: 0.0, fat: 11.0, fiber: 0.0),
        "ground beef 90/10": FoodMacros(calories: 176, protein: 20.0, carbs: 0.0, fat: 10.0, fiber: 0.0),
        "ground beef 80/20": FoodMacros(calories: 254, protein: 17.2, carbs: 0.0, fat: 20.0, fiber: 0.0),
        "pork tenderloin": FoodMacros(calories: 143, protein: 26.0, carbs: 0.0, fat: 3.5, fiber: 0.0),
        "shrimp": FoodMacros(calories: 99, protein: 24.0, carbs: 0.2, fat: 0.3, fiber: 0.0),
        "cod": FoodMacros(calories: 82, protein: 18.0, carbs: 0.0, fat: 0.7, fiber: 0.0),
        "tofu": FoodMacros(calories: 76, protein: 8.0, carbs: 1.9, fat: 4.8, fiber: 0.3),
        "tempeh": FoodMacros(calories: 192, protein: 20.3, carbs: 7.6, fat: 10.8, fiber: 0.0),
        "greek yogurt": FoodMacros(calories: 97, protein: 9.0, carbs: 3.6, fat: 5.0, fiber: 0.0),
        "greek yogurt 0%": FoodMacros(calories: 59, protein: 10.2, carbs: 3.6, fat: 0.7, fiber: 0.0),
        "cottage cheese": FoodMacros(calories: 98, protein: 11.1, carbs: 3.4, fat: 4.3, fiber: 0.0),
        "whey protein": FoodMacros(calories: 380, protein: 75.0, carbs: 10.0, fat: 5.0, fiber: 0.0),
        "casein protein": FoodMacros(calories: 370, protein: 70.0, carbs: 12.0, fat: 5.0, fiber: 0.0),

        // ── Carbohydrates ─────────────────────────────────────────
        "white rice": FoodMacros(calories: 365, protein: 7.1, carbs: 80.0, fat: 0.7, fiber: 1.3),
        "brown rice": FoodMacros(calories: 362, protein: 7.5, carbs: 76.2, fat: 2.7, fiber: 3.4),
        "basmati rice": FoodMacros(calories: 356, protein: 8.0, carbs: 77.0, fat: 0.6, fiber: 0.8),
        "pasta": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "whole wheat pasta": FoodMacros(calories: 348, protein: 14.6, carbs: 68.0, fat: 2.5, fiber: 8.0),
        "oats": FoodMacros(calories: 389, protein: 16.9, carbs: 66.3, fat: 6.9, fiber: 10.6),
        "sweet potato": FoodMacros(calories: 86, protein: 1.6, carbs: 20.1, fat: 0.1, fiber: 3.0),
        "potato": FoodMacros(calories: 77, protein: 2.0, carbs: 17.5, fat: 0.1, fiber: 2.2),
        "white bread": FoodMacros(calories: 265, protein: 9.4, carbs: 49.0, fat: 3.2, fiber: 2.7),
        "whole wheat bread": FoodMacros(calories: 247, protein: 13.0, carbs: 41.3, fat: 3.4, fiber: 6.0),
        "banana": FoodMacros(calories: 89, protein: 1.1, carbs: 22.8, fat: 0.3, fiber: 2.6),
        "apple": FoodMacros(calories: 52, protein: 0.3, carbs: 13.8, fat: 0.2, fiber: 2.4),
        "orange": FoodMacros(calories: 47, protein: 0.9, carbs: 11.8, fat: 0.1, fiber: 2.4),
        "blueberries": FoodMacros(calories: 57, protein: 0.7, carbs: 14.5, fat: 0.3, fiber: 2.4),
        "strawberries": FoodMacros(calories: 32, protein: 0.7, carbs: 7.7, fat: 0.3, fiber: 2.0),
        "quinoa": FoodMacros(calories: 368, protein: 14.1, carbs: 64.2, fat: 6.1, fiber: 7.0),
        "couscous": FoodMacros(calories: 376, protein: 12.8, carbs: 77.4, fat: 0.6, fiber: 5.0),
        "tortilla wrap": FoodMacros(calories: 312, protein: 8.0, carbs: 52.0, fat: 8.0, fiber: 3.0),
        "rice cakes": FoodMacros(calories: 387, protein: 8.0, carbs: 82.0, fat: 2.8, fiber: 3.6),
        "honey": FoodMacros(calories: 304, protein: 0.3, carbs: 82.4, fat: 0.0, fiber: 0.2),
        "granola": FoodMacros(calories: 471, protein: 10.0, carbs: 64.0, fat: 20.0, fiber: 5.0),

        // ── Fats ──────────────────────────────────────────────────
        "olive oil": FoodMacros(calories: 884, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "coconut oil": FoodMacros(calories: 862, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "avocado": FoodMacros(calories: 160, protein: 2.0, carbs: 8.5, fat: 14.7, fiber: 6.7),
        "almonds": FoodMacros(calories: 579, protein: 21.2, carbs: 21.7, fat: 49.9, fiber: 12.2),
        "walnuts": FoodMacros(calories: 654, protein: 15.2, carbs: 13.7, fat: 65.2, fiber: 6.7),
        "peanut butter": FoodMacros(calories: 588, protein: 25.1, carbs: 20.0, fat: 50.4, fiber: 6.0),
        "almond butter": FoodMacros(calories: 614, protein: 21.0, carbs: 18.8, fat: 55.5, fiber: 10.5),
        "cashews": FoodMacros(calories: 553, protein: 18.2, carbs: 30.2, fat: 43.9, fiber: 3.3),
        "peanuts": FoodMacros(calories: 567, protein: 25.8, carbs: 16.1, fat: 49.2, fiber: 8.5),
        "chia seeds": FoodMacros(calories: 486, protein: 16.5, carbs: 42.1, fat: 30.7, fiber: 34.4),
        "flax seeds": FoodMacros(calories: 534, protein: 18.3, carbs: 28.9, fat: 42.2, fiber: 27.3),
        "dark chocolate 85%": FoodMacros(calories: 598, protein: 7.8, carbs: 46.0, fat: 42.6, fiber: 11.0),

        // ── Vegetables ────────────────────────────────────────────
        "broccoli": FoodMacros(calories: 34, protein: 2.8, carbs: 7.0, fat: 0.4, fiber: 2.6),
        "spinach": FoodMacros(calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4, fiber: 2.2),
        "asparagus": FoodMacros(calories: 20, protein: 2.2, carbs: 3.9, fat: 0.1, fiber: 2.1),
        "bell pepper": FoodMacros(calories: 31, protein: 1.0, carbs: 6.0, fat: 0.3, fiber: 2.1),
        "tomato": FoodMacros(calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2, fiber: 1.2),
        "cucumber": FoodMacros(calories: 15, protein: 0.7, carbs: 3.6, fat: 0.1, fiber: 0.5),
        "lettuce": FoodMacros(calories: 15, protein: 1.4, carbs: 2.9, fat: 0.2, fiber: 1.3),
        "mushroom": FoodMacros(calories: 22, protein: 3.1, carbs: 3.3, fat: 0.3, fiber: 1.0),
        "onion": FoodMacros(calories: 40, protein: 1.1, carbs: 9.3, fat: 0.1, fiber: 1.7),
        "carrot": FoodMacros(calories: 41, protein: 0.9, carbs: 9.6, fat: 0.2, fiber: 2.8),
        "zucchini": FoodMacros(calories: 17, protein: 1.2, carbs: 3.1, fat: 0.3, fiber: 1.0),
        "green beans": FoodMacros(calories: 31, protein: 1.8, carbs: 7.0, fat: 0.1, fiber: 3.4),
        "kale": FoodMacros(calories: 49, protein: 4.3, carbs: 8.8, fat: 0.9, fiber: 3.6),
        "cauliflower": FoodMacros(calories: 25, protein: 1.9, carbs: 5.0, fat: 0.3, fiber: 2.0),
        "cabbage": FoodMacros(calories: 25, protein: 1.3, carbs: 5.8, fat: 0.1, fiber: 2.5),
        "celery": FoodMacros(calories: 16, protein: 0.7, carbs: 3.0, fat: 0.2, fiber: 1.6),
        "eggplant": FoodMacros(calories: 25, protein: 1.0, carbs: 6.0, fat: 0.2, fiber: 3.0),

        // ── Dairy-Free Alternatives ───────────────────────────────
        "almond milk": FoodMacros(calories: 15, protein: 0.6, carbs: 0.3, fat: 1.1, fiber: 0.2),
        "oat milk": FoodMacros(calories: 43, protein: 1.0, carbs: 7.0, fat: 1.5, fiber: 0.8),
        "soy milk": FoodMacros(calories: 33, protein: 2.9, carbs: 1.2, fat: 1.8, fiber: 0.4),
        "lactose-free milk": FoodMacros(calories: 42, protein: 3.4, carbs: 5.0, fat: 1.0, fiber: 0.0),
        "coconut yogurt": FoodMacros(calories: 110, protein: 1.0, carbs: 9.0, fat: 7.0, fiber: 1.0),
        "coconut milk": FoodMacros(calories: 23, protein: 0.2, carbs: 3.3, fat: 1.1, fiber: 0.0),

        // ── Legumes ───────────────────────────────────────────────
        "chickpeas": FoodMacros(calories: 164, protein: 8.9, carbs: 27.4, fat: 2.6, fiber: 7.6),
        "lentils": FoodMacros(calories: 116, protein: 9.0, carbs: 20.1, fat: 0.4, fiber: 7.9),
        "black beans": FoodMacros(calories: 132, protein: 8.9, carbs: 23.7, fat: 0.5, fiber: 8.7),
        "kidney beans": FoodMacros(calories: 127, protein: 8.7, carbs: 22.8, fat: 0.5, fiber: 6.4),
        "edamame": FoodMacros(calories: 121, protein: 11.9, carbs: 8.6, fat: 5.2, fiber: 5.2),

        // ── Prepared / Convenience ────────────────────────────────
        "protein shake": FoodMacros(calories: 120, protein: 25.0, carbs: 3.0, fat: 1.5, fiber: 0.5),
        "protein bar": FoodMacros(calories: 350, protein: 20.0, carbs: 35.0, fat: 12.0, fiber: 5.0),
        "energy bar": FoodMacros(calories: 250, protein: 5.0, carbs: 45.0, fat: 7.0, fiber: 3.0),
        "meal replacement": FoodMacros(calories: 400, protein: 30.0, carbs: 45.0, fat: 10.0, fiber: 5.0),

        // ── Condiments / Extras ───────────────────────────────────
        "butter": FoodMacros(calories: 717, protein: 0.9, carbs: 0.1, fat: 81.1, fiber: 0.0),
        "cream cheese": FoodMacros(calories: 342, protein: 5.9, carbs: 4.1, fat: 34.2, fiber: 0.0),
        "hummus": FoodMacros(calories: 166, protein: 7.9, carbs: 14.3, fat: 9.6, fiber: 6.0),
        "mozzarella": FoodMacros(calories: 280, protein: 28.0, carbs: 3.1, fat: 17.1, fiber: 0.0),
        "parmesan": FoodMacros(calories: 431, protein: 38.5, carbs: 4.1, fat: 29.0, fiber: 0.0),
        "cheddar": FoodMacros(calories: 403, protein: 25.0, carbs: 1.3, fat: 33.1, fiber: 0.0),
    ]

    // MARK: - Cooking Factors (raw weight -> cooked weight multiplier)

    // e.g. 100g raw pasta becomes ~220g cooked

    static let cookingFactors: [String: Double] = [
        "pasta": 2.2,
        "whole wheat pasta": 2.2,
        "white rice": 2.5,
        "brown rice": 2.5,
        "basmati rice": 2.5,
        "chicken breast": 0.75,
        "chicken thigh": 0.75,
        "salmon": 0.80,
        "cod": 0.80,
        "oats": 3.0,
        "quinoa": 2.6,
        "couscous": 2.5,
        "lentils": 2.0,
        "chickpeas": 2.0,
        "black beans": 2.0,
        "kidney beans": 2.0,
        "shrimp": 0.85,
        "beef sirloin": 0.75,
        "ground beef 90/10": 0.75,
        "ground beef 80/20": 0.70,
        "ground turkey": 0.75,
        "turkey breast": 0.75,
        "pork tenderloin": 0.75,
        "sweet potato": 0.90,
        "potato": 0.90,
        "edamame": 1.0,
    ]

    // MARK: - Natural Portions

    static let naturalPortions: [String: (grams: Double, unit: String, plural: String)] = [
        "eggs": (grams: 50, unit: "egg", plural: "eggs"),
        "egg whites": (grams: 33, unit: "white", plural: "whites"),
        "banana": (grams: 120, unit: "banana", plural: "bananas"),
        "apple": (grams: 182, unit: "apple", plural: "apples"),
        "orange": (grams: 131, unit: "orange", plural: "oranges"),
        "avocado": (grams: 150, unit: "avocado", plural: "avocados"),
        "white bread": (grams: 30, unit: "slice", plural: "slices"),
        "whole wheat bread": (grams: 30, unit: "slice", plural: "slices"),
        "tortilla wrap": (grams: 65, unit: "wrap", plural: "wraps"),
        "rice cakes": (grams: 9, unit: "cake", plural: "cakes"),
        "protein shake": (grams: 100, unit: "shake", plural: "shakes"),
        "protein bar": (grams: 60, unit: "bar", plural: "bars"),
        "energy bar": (grams: 40, unit: "bar", plural: "bars"),
    ]

    // MARK: - Lookup

    /// Look up macros by food name. Tries exact match first, then fuzzy (contains) match.
    static func lookup(_ food: String) -> FoodMacros? {
        let normalized = food.lowercased().trimmingCharacters(in: .whitespaces)

        // Exact match
        if let macros = macrosPer100g[normalized] {
            return macros
        }

        // Fuzzy: check if any key contains the query or vice-versa
        // Prefer shorter key matches (more specific)
        let candidates = macrosPer100g
            .filter { key, _ in
                key.contains(normalized) || normalized.contains(key)
            }
            .sorted { $0.key.count < $1.key.count }

        return candidates.first?.value
    }

    // MARK: - Calculate Macros

    /// Calculate macros for a given food and quantity in grams.
    /// Quantity is assumed to be raw/uncooked weight unless the food has no cooking factor.
    static func calculateMacros(food: String, quantityGrams: Double) -> FoodMacros? {
        guard let baseMacros = lookup(food) else {
            return nil
        }
        return baseMacros.scaled(to: quantityGrams)
    }

    // MARK: - Raw Weight from Cooked

    /// Convert cooked weight to raw weight using cooking factors.
    /// Returns the cooked weight unchanged if no cooking factor is available.
    static func rawWeight(fromCookedGrams cooked: Double, food: String) -> Double {
        let normalized = food.lowercased().trimmingCharacters(in: .whitespaces)
        guard let factor = cookingFactors[normalized], factor > 0 else {
            return cooked
        }
        return cooked / factor
    }

    // MARK: - Format Portion

    /// Format a gram quantity into natural portions when possible.
    /// Returns "2 eggs" instead of "100g eggs", "1 banana" instead of "120g banana".
    static func formatPortion(food: String, grams: Double) -> String {
        let normalized = food.lowercased().trimmingCharacters(in: .whitespaces)

        if let portion = naturalPortions[normalized] {
            let count = grams / portion.grams
            if count >= 0.8 {
                let rounded = (count * 2).rounded() / 2 // round to nearest 0.5
                if rounded == 1.0 {
                    return "1 \(portion.unit)"
                } else if rounded == rounded.rounded() {
                    // Whole number
                    return "\(Int(rounded)) \(portion.plural)"
                } else {
                    // Half portion like 1.5
                    return "\(String(format: "%.1f", rounded)) \(portion.plural)"
                }
            }
        }

        // Default: show grams
        if grams == grams.rounded() {
            return "\(Int(grams))g \(normalized)"
        }
        return "\(String(format: "%.0f", grams))g \(normalized)"
    }
}
