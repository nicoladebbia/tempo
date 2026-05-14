//
// FoodMacroDatabase.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
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
        // Common vegetables (raw → cooked); water loss dominates.
        "broccoli": 0.85,
        "cauliflower": 0.85,
        "asparagus": 0.85,
        "spinach": 0.30,
        "kale": 0.65,
        "zucchini": 0.80,
        "bell pepper": 0.85,
        "carrot": 0.90,
        "mushroom": 0.65,
        "green beans": 0.85,
    ]

    // MARK: - Natural Portions

    /// Structured portion record. Replaces the prior tuple shape so callers
    /// can read `.isStaple` and `.purchaseUnit` without spreading lookup
    /// logic everywhere. Two units coexist:
    ///   - `unit` / `plural`: the *recipe-side* natural portion (1 egg, 1
    ///     banana). Used by `formatPortion` for ingredient display.
    ///   - `purchaseUnit` / `purchaseUnitPlural` / `purchaseGrams`: the
    ///     *grocery-side* shopping unit (1 can of black beans = 400g
    ///     drained; 3 medium carrots from a recipe of 180g). The
    ///     grocery list rounds gram totals up to whole `purchaseUnit`s.
    /// Staples are pantry items that you buy once and use across many
    /// meals (salt, oil, garlic powder). Their `quantityGrams` deductions
    /// are skipped by the pantry decrement, and the grocery list only
    /// surfaces them when the pantry shows 0.
    struct NaturalPortion: Sendable {
        let grams: Double
        let unit: String
        let plural: String
        let purchaseUnit: String
        let purchaseUnitPlural: String
        let purchaseGrams: Double
        let isStaple: Bool

        /// Convenience for entries where recipe-side and grocery-side
        /// portions coincide (e.g. an egg — you buy 1, you cook with 1).
        static func simple(grams: Double, unit: String, plural: String) -> NaturalPortion {
            NaturalPortion(
                grams: grams,
                unit: unit,
                plural: plural,
                purchaseUnit: unit,
                purchaseUnitPlural: plural,
                purchaseGrams: grams,
                isStaple: false
            )
        }

        static func staple(grams: Double = 1, unit: String = "jar", plural: String = "jars") -> NaturalPortion {
            NaturalPortion(
                grams: grams,
                unit: unit,
                plural: plural,
                purchaseUnit: unit,
                purchaseUnitPlural: plural,
                purchaseGrams: grams,
                isStaple: true
            )
        }
    }

    static let naturalPortions: [String: NaturalPortion] = [
        // Proteins ───────────────────────────────────────────────────
        "eggs": .simple(grams: 50, unit: "egg", plural: "eggs"),
        "egg": .simple(grams: 50, unit: "egg", plural: "eggs"),
        "egg whites": .simple(grams: 33, unit: "white", plural: "whites"),
        "chicken breast": NaturalPortion(grams: 170, unit: "breast", plural: "breasts", purchaseUnit: "breast", purchaseUnitPlural: "breasts", purchaseGrams: 170, isStaple: false),
        "chicken thigh": NaturalPortion(grams: 110, unit: "thigh", plural: "thighs", purchaseUnit: "thigh", purchaseUnitPlural: "thighs", purchaseGrams: 110, isStaple: false),
        "ground beef": NaturalPortion(grams: 450, unit: "g", plural: "g", purchaseUnit: "pack", purchaseUnitPlural: "packs", purchaseGrams: 450, isStaple: false),
        "ground turkey": NaturalPortion(grams: 450, unit: "g", plural: "g", purchaseUnit: "pack", purchaseUnitPlural: "packs", purchaseGrams: 450, isStaple: false),
        "salmon": NaturalPortion(grams: 150, unit: "fillet", plural: "fillets", purchaseUnit: "fillet", purchaseUnitPlural: "fillets", purchaseGrams: 150, isStaple: false),
        "tuna canned": NaturalPortion(grams: 120, unit: "can", plural: "cans", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 120, isStaple: false),
        "tofu": NaturalPortion(grams: 400, unit: "g", plural: "g", purchaseUnit: "block", purchaseUnitPlural: "blocks", purchaseGrams: 400, isStaple: false),
        "greek yogurt": NaturalPortion(grams: 170, unit: "container", plural: "containers", purchaseUnit: "container", purchaseUnitPlural: "containers", purchaseGrams: 170, isStaple: false),
        "cottage cheese": NaturalPortion(grams: 226, unit: "tub", plural: "tubs", purchaseUnit: "tub", purchaseUnitPlural: "tubs", purchaseGrams: 226, isStaple: false),

        // Grains & starches ────────────────────────────────────────
        "rice": NaturalPortion(grams: 185, unit: "cup", plural: "cups", purchaseUnit: "kg bag", purchaseUnitPlural: "kg bags", purchaseGrams: 1000, isStaple: false),
        "white rice": NaturalPortion(grams: 185, unit: "cup", plural: "cups", purchaseUnit: "kg bag", purchaseUnitPlural: "kg bags", purchaseGrams: 1000, isStaple: false),
        "brown rice": NaturalPortion(grams: 195, unit: "cup", plural: "cups", purchaseUnit: "kg bag", purchaseUnitPlural: "kg bags", purchaseGrams: 1000, isStaple: false),
        "rolled oats": NaturalPortion(grams: 80, unit: "cup", plural: "cups", purchaseUnit: "kg bag", purchaseUnitPlural: "kg bags", purchaseGrams: 1000, isStaple: false),
        "oatmeal": NaturalPortion(grams: 80, unit: "cup", plural: "cups", purchaseUnit: "kg bag", purchaseUnitPlural: "kg bags", purchaseGrams: 1000, isStaple: false),
        "pasta": NaturalPortion(grams: 100, unit: "g", plural: "g", purchaseUnit: "500g box", purchaseUnitPlural: "500g boxes", purchaseGrams: 500, isStaple: false),
        "quinoa": NaturalPortion(grams: 185, unit: "cup", plural: "cups", purchaseUnit: "500g bag", purchaseUnitPlural: "500g bags", purchaseGrams: 500, isStaple: false),
        "sweet potato": NaturalPortion(grams: 130, unit: "potato", plural: "potatoes", purchaseUnit: "potato", purchaseUnitPlural: "potatoes", purchaseGrams: 130, isStaple: false),
        "potato": NaturalPortion(grams: 170, unit: "potato", plural: "potatoes", purchaseUnit: "potato", purchaseUnitPlural: "potatoes", purchaseGrams: 170, isStaple: false),
        "white bread": .simple(grams: 30, unit: "slice", plural: "slices"),
        "whole wheat bread": .simple(grams: 30, unit: "slice", plural: "slices"),
        "tortilla wrap": .simple(grams: 65, unit: "wrap", plural: "wraps"),
        "rice cakes": .simple(grams: 9, unit: "cake", plural: "cakes"),
        "bagel": .simple(grams: 100, unit: "bagel", plural: "bagels"),

        // Legumes ──────────────────────────────────────────────────
        "black beans canned": NaturalPortion(grams: 240, unit: "can", plural: "cans", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 400, isStaple: false),
        "chickpeas canned": NaturalPortion(grams: 240, unit: "can", plural: "cans", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 400, isStaple: false),
        "kidney beans canned": NaturalPortion(grams: 240, unit: "can", plural: "cans", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 400, isStaple: false),
        "lentils dry": NaturalPortion(grams: 200, unit: "cup", plural: "cups", purchaseUnit: "500g bag", purchaseUnitPlural: "500g bags", purchaseGrams: 500, isStaple: false),

        // Produce — fruits ─────────────────────────────────────────
        "banana": .simple(grams: 120, unit: "banana", plural: "bananas"),
        "apple": .simple(grams: 182, unit: "apple", plural: "apples"),
        "orange": .simple(grams: 131, unit: "orange", plural: "oranges"),
        "avocado": .simple(grams: 150, unit: "avocado", plural: "avocados"),
        "lemon": .simple(grams: 65, unit: "lemon", plural: "lemons"),
        "lime": .simple(grams: 45, unit: "lime", plural: "limes"),
        "blueberries": NaturalPortion(grams: 140, unit: "cup", plural: "cups", purchaseUnit: "punnet", purchaseUnitPlural: "punnets", purchaseGrams: 170, isStaple: false),
        "strawberries": NaturalPortion(grams: 150, unit: "cup", plural: "cups", purchaseUnit: "punnet", purchaseUnitPlural: "punnets", purchaseGrams: 250, isStaple: false),

        // Produce — vegetables ────────────────────────────────────
        "carrot": .simple(grams: 65, unit: "medium carrot", plural: "medium carrots"),
        "carrots": .simple(grams: 65, unit: "medium carrot", plural: "medium carrots"),
        "onion": .simple(grams: 110, unit: "onion", plural: "onions"),
        "garlic clove": .simple(grams: 3, unit: "clove", plural: "cloves"),
        "tomato": .simple(grams: 120, unit: "tomato", plural: "tomatoes"),
        "cherry tomato": NaturalPortion(grams: 17, unit: "tomato", plural: "tomatoes", purchaseUnit: "punnet", purchaseUnitPlural: "punnets", purchaseGrams: 250, isStaple: false),
        "bell pepper": .simple(grams: 120, unit: "pepper", plural: "peppers"),
        "cucumber": .simple(grams: 300, unit: "cucumber", plural: "cucumbers"),
        "zucchini": .simple(grams: 200, unit: "zucchini", plural: "zucchinis"),
        "broccoli": NaturalPortion(grams: 90, unit: "cup", plural: "cups", purchaseUnit: "head", purchaseUnitPlural: "heads", purchaseGrams: 350, isStaple: false),
        "spinach": NaturalPortion(grams: 30, unit: "cup", plural: "cups", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 200, isStaple: false),
        "kale": NaturalPortion(grams: 30, unit: "cup", plural: "cups", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 200, isStaple: false),
        "lettuce": NaturalPortion(grams: 50, unit: "cup", plural: "cups", purchaseUnit: "head", purchaseUnitPlural: "heads", purchaseGrams: 350, isStaple: false),
        "mushrooms": NaturalPortion(grams: 70, unit: "cup", plural: "cups", purchaseUnit: "pack", purchaseUnitPlural: "packs", purchaseGrams: 250, isStaple: false),

        // Dairy ────────────────────────────────────────────────────
        "whole milk": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "liter", purchaseUnitPlural: "liters", purchaseGrams: 1030, isStaple: false),
        "skim milk": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "liter", purchaseUnitPlural: "liters", purchaseGrams: 1030, isStaple: false),
        "almond milk": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "liter", purchaseUnitPlural: "liters", purchaseGrams: 1000, isStaple: false),
        "butter": NaturalPortion(grams: 14, unit: "tbsp", plural: "tbsp", purchaseUnit: "stick", purchaseUnitPlural: "sticks", purchaseGrams: 113, isStaple: false),
        "cheddar": NaturalPortion(grams: 28, unit: "slice", plural: "slices", purchaseUnit: "block", purchaseUnitPlural: "blocks", purchaseGrams: 220, isStaple: false),
        "mozzarella": NaturalPortion(grams: 28, unit: "slice", plural: "slices", purchaseUnit: "ball", purchaseUnitPlural: "balls", purchaseGrams: 125, isStaple: false),
        "parmesan": NaturalPortion(grams: 5, unit: "tbsp", plural: "tbsp", purchaseUnit: "wedge", purchaseUnitPlural: "wedges", purchaseGrams: 200, isStaple: false),
        "feta": NaturalPortion(grams: 30, unit: "g", plural: "g", purchaseUnit: "pack", purchaseUnitPlural: "packs", purchaseGrams: 200, isStaple: false),

        // Fats & oils (staples) ───────────────────────────────────
        "olive oil": .staple(unit: "bottle", plural: "bottles"),
        "extra virgin oil": .staple(unit: "bottle", plural: "bottles"),
        "extra virgin olive oil": .staple(unit: "bottle", plural: "bottles"),
        "vegetable oil": .staple(unit: "bottle", plural: "bottles"),
        "coconut oil": .staple(unit: "jar", plural: "jars"),
        "peanut butter": NaturalPortion(grams: 16, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 500, isStaple: false),
        "almond butter": NaturalPortion(grams: 16, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 340, isStaple: false),
        "almonds": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "walnuts": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),

        // Condiments & spices (staples) ───────────────────────────
        "salt": .staple(),
        "black pepper": .staple(),
        "pepper": .staple(),
        "garlic powder": .staple(),
        "onion powder": .staple(),
        "paprika": .staple(),
        "cumin": .staple(),
        "oregano": .staple(),
        "basil": .staple(),
        "thyme": .staple(),
        "rosemary": .staple(),
        "chili powder": .staple(),
        "cinnamon": .staple(),
        "vanilla extract": .staple(unit: "bottle", plural: "bottles"),
        "soy sauce": .staple(unit: "bottle", plural: "bottles"),
        "balsamic vinegar": .staple(unit: "bottle", plural: "bottles"),
        "honey": .staple(unit: "jar", plural: "jars"),
        "mustard": .staple(unit: "jar", plural: "jars"),
        "hot sauce": .staple(unit: "bottle", plural: "bottles"),

        // Snacks / shakes ─────────────────────────────────────────
        "protein shake": .simple(grams: 100, unit: "shake", plural: "shakes"),
        "protein bar": .simple(grams: 60, unit: "bar", plural: "bars"),
        "energy bar": .simple(grams: 40, unit: "bar", plural: "bars"),
        "protein powder": NaturalPortion(grams: 30, unit: "scoop", plural: "scoops", purchaseUnit: "tub", purchaseUnitPlural: "tubs", purchaseGrams: 900, isStaple: false),

        // Mediterranean / Italian ────────────────────────────────
        "pesto": NaturalPortion(grams: 15, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 190, isStaple: false),
        "sun dried tomatoes": NaturalPortion(grams: 28, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 200, isStaple: false),
        "olives": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 200, isStaple: false),
        "capers": .staple(unit: "jar", plural: "jars"),
        "anchovies": NaturalPortion(grams: 25, unit: "can", plural: "cans", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 50, isStaple: false),
        "ricotta": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "tub", purchaseUnitPlural: "tubs", purchaseGrams: 425, isStaple: false),
        "burrata": NaturalPortion(grams: 125, unit: "ball", plural: "balls", purchaseUnit: "ball", purchaseUnitPlural: "balls", purchaseGrams: 125, isStaple: false),
        "prosciutto": NaturalPortion(grams: 30, unit: "pack", plural: "packs", purchaseUnit: "pack", purchaseUnitPlural: "packs", purchaseGrams: 90, isStaple: false),

        // Asian pantry ────────────────────────────────────────────
        "fish sauce": .staple(unit: "bottle", plural: "bottles"),
        "rice vinegar": .staple(unit: "bottle", plural: "bottles"),
        "sesame oil": .staple(unit: "bottle", plural: "bottles"),
        "sriracha": .staple(unit: "bottle", plural: "bottles"),
        "miso paste": .staple(unit: "tub", plural: "tubs"),
        "kimchi": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 500, isStaple: false),
        "edamame": NaturalPortion(grams: 75, unit: "cup", plural: "cups", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 500, isStaple: false),
        "tahini": NaturalPortion(grams: 15, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 350, isStaple: false),
        "hummus": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "tub", purchaseUnitPlural: "tubs", purchaseGrams: 250, isStaple: false),

        // Herbs & spices (more staples) ──────────────────────────
        "fresh parsley": NaturalPortion(grams: 5, unit: "tbsp", plural: "tbsp", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 30, isStaple: false),
        "fresh basil": NaturalPortion(grams: 3, unit: "tbsp", plural: "tbsp", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 25, isStaple: false),
        "fresh cilantro": NaturalPortion(grams: 4, unit: "tbsp", plural: "tbsp", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 30, isStaple: false),
        "fresh mint": NaturalPortion(grams: 3, unit: "tbsp", plural: "tbsp", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 20, isStaple: false),
        "fresh dill": NaturalPortion(grams: 3, unit: "tbsp", plural: "tbsp", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 25, isStaple: false),
        "ginger": NaturalPortion(grams: 5, unit: "tsp", plural: "tsp", purchaseUnit: "knob", purchaseUnitPlural: "knobs", purchaseGrams: 60, isStaple: false),
        "sumac": .staple(),
        "turmeric": .staple(),
        "smoked paprika": .staple(),
        "red pepper flakes": .staple(),
        "bay leaves": .staple(),
        "curry powder": .staple(),
        "cayenne": .staple(),
        "nutmeg": .staple(),
        "ginger powder": .staple(),

        // Sweeteners / baking (staples) ─────────────────────────
        "maple syrup": .staple(unit: "bottle", plural: "bottles"),
        "sugar": .staple(unit: "bag", plural: "bags"),
        "brown sugar": .staple(unit: "bag", plural: "bags"),
        "flour": .staple(unit: "bag", plural: "bags"),
        "baking soda": .staple(unit: "box", plural: "boxes"),
        "baking powder": .staple(unit: "tin", plural: "tins"),
        "cocoa powder": .staple(unit: "tin", plural: "tins"),

        // Produce — more ──────────────────────────────────────────
        "ginger root": NaturalPortion(grams: 5, unit: "tsp", plural: "tsp", purchaseUnit: "knob", purchaseUnitPlural: "knobs", purchaseGrams: 60, isStaple: false),
        "jalapeno": .simple(grams: 14, unit: "jalapeno", plural: "jalapenos"),
        "shallot": .simple(grams: 25, unit: "shallot", plural: "shallots"),
        "leek": .simple(grams: 90, unit: "leek", plural: "leeks"),
        "celery": NaturalPortion(grams: 40, unit: "stalk", plural: "stalks", purchaseUnit: "head", purchaseUnitPlural: "heads", purchaseGrams: 600, isStaple: false),
        "asparagus": NaturalPortion(grams: 80, unit: "cup", plural: "cups", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 500, isStaple: false),
        "raspberries": NaturalPortion(grams: 125, unit: "cup", plural: "cups", purchaseUnit: "punnet", purchaseUnitPlural: "punnets", purchaseGrams: 170, isStaple: false),
        "grapes": NaturalPortion(grams: 150, unit: "cup", plural: "cups", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 500, isStaple: false),
        "pineapple": NaturalPortion(grams: 165, unit: "cup", plural: "cups", purchaseUnit: "pineapple", purchaseUnitPlural: "pineapples", purchaseGrams: 900, isStaple: false),
        "mango": .simple(grams: 200, unit: "mango", plural: "mangos"),
        "kiwi": .simple(grams: 70, unit: "kiwi", plural: "kiwis"),

        // Canned / jarred ─────────────────────────────────────────
        "diced tomatoes canned": NaturalPortion(grams: 240, unit: "can", plural: "cans", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 400, isStaple: false),
        "tomato paste": NaturalPortion(grams: 16, unit: "tbsp", plural: "tbsp", purchaseUnit: "tube", purchaseUnitPlural: "tubes", purchaseGrams: 150, isStaple: false),
        "coconut milk canned": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 400, isStaple: false),

        // Cheeses (expanded) ─────────────────────────────────────
        "gouda": NaturalPortion(grams: 28, unit: "slice", plural: "slices", purchaseUnit: "block", purchaseUnitPlural: "blocks", purchaseGrams: 200, isStaple: false),
        "brie": NaturalPortion(grams: 30, unit: "slice", plural: "slices", purchaseUnit: "wheel", purchaseUnitPlural: "wheels", purchaseGrams: 200, isStaple: false),
        "camembert": NaturalPortion(grams: 30, unit: "slice", plural: "slices", purchaseUnit: "wheel", purchaseUnitPlural: "wheels", purchaseGrams: 250, isStaple: false),
        "blue cheese": NaturalPortion(grams: 28, unit: "tbsp", plural: "tbsp", purchaseUnit: "wedge", purchaseUnitPlural: "wedges", purchaseGrams: 150, isStaple: false),
        "gorgonzola": NaturalPortion(grams: 28, unit: "tbsp", plural: "tbsp", purchaseUnit: "wedge", purchaseUnitPlural: "wedges", purchaseGrams: 150, isStaple: false),
        "goat cheese": NaturalPortion(grams: 28, unit: "slice", plural: "slices", purchaseUnit: "log", purchaseUnitPlural: "logs", purchaseGrams: 120, isStaple: false),
        "halloumi": NaturalPortion(grams: 30, unit: "slice", plural: "slices", purchaseUnit: "block", purchaseUnitPlural: "blocks", purchaseGrams: 225, isStaple: false),
        "manchego": NaturalPortion(grams: 28, unit: "slice", plural: "slices", purchaseUnit: "wedge", purchaseUnitPlural: "wedges", purchaseGrams: 200, isStaple: false),
        "swiss cheese": NaturalPortion(grams: 28, unit: "slice", plural: "slices", purchaseUnit: "block", purchaseUnitPlural: "blocks", purchaseGrams: 200, isStaple: false),
        "provolone": NaturalPortion(grams: 28, unit: "slice", plural: "slices", purchaseUnit: "block", purchaseUnitPlural: "blocks", purchaseGrams: 200, isStaple: false),
        "pecorino": NaturalPortion(grams: 5, unit: "tbsp", plural: "tbsp", purchaseUnit: "wedge", purchaseUnitPlural: "wedges", purchaseGrams: 200, isStaple: false),
        "mascarpone": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "tub", purchaseUnitPlural: "tubs", purchaseGrams: 250, isStaple: false),
        "cream cheese": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "tub", purchaseUnitPlural: "tubs", purchaseGrams: 225, isStaple: false),

        // Nuts / seeds (expanded) ────────────────────────────────
        "pistachios": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "cashews": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "pecans": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "hazelnuts": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "macadamia nuts": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 200, isStaple: false),
        "pine nuts": NaturalPortion(grams: 14, unit: "tbsp", plural: "tbsp", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 100, isStaple: false),
        "chia seeds": NaturalPortion(grams: 12, unit: "tbsp", plural: "tbsp", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "flax seeds": NaturalPortion(grams: 10, unit: "tbsp", plural: "tbsp", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "pumpkin seeds": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "sunflower seeds": NaturalPortion(grams: 28, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "sesame seeds": NaturalPortion(grams: 9, unit: "tbsp", plural: "tbsp", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 200, isStaple: false),

        // Prepared sauces / dressings / spreads ──────────────────
        "pasta sauce": NaturalPortion(grams: 125, unit: "cup", plural: "cups", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 680, isStaple: false),
        "marinara sauce": NaturalPortion(grams: 125, unit: "cup", plural: "cups", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 680, isStaple: false),
        "salsa": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 450, isStaple: false),
        "guacamole": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "tub", purchaseUnitPlural: "tubs", purchaseGrams: 200, isStaple: false),
        "mayonnaise": .staple(unit: "jar", plural: "jars"),
        "ketchup": .staple(unit: "bottle", plural: "bottles"),
        "bbq sauce": .staple(unit: "bottle", plural: "bottles"),
        "ranch dressing": .staple(unit: "bottle", plural: "bottles"),
        "italian dressing": .staple(unit: "bottle", plural: "bottles"),
        "vinaigrette": .staple(unit: "bottle", plural: "bottles"),
        "worcestershire sauce": .staple(unit: "bottle", plural: "bottles"),
        "jam": .staple(unit: "jar", plural: "jars"),
        "marmalade": .staple(unit: "jar", plural: "jars"),
        "nutella": NaturalPortion(grams: 19, unit: "tbsp", plural: "tbsp", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 350, isStaple: false),

        // More cuts of meat / fish ───────────────────────────────
        "pork chop": NaturalPortion(grams: 170, unit: "chop", plural: "chops", purchaseUnit: "chop", purchaseUnitPlural: "chops", purchaseGrams: 170, isStaple: false),
        "bacon": NaturalPortion(grams: 8, unit: "slice", plural: "slices", purchaseUnit: "pack", purchaseUnitPlural: "packs", purchaseGrams: 340, isStaple: false),
        "sausage": NaturalPortion(grams: 75, unit: "link", plural: "links", purchaseUnit: "pack", purchaseUnitPlural: "packs", purchaseGrams: 450, isStaple: false),
        "lamb chop": NaturalPortion(grams: 100, unit: "chop", plural: "chops", purchaseUnit: "chop", purchaseUnitPlural: "chops", purchaseGrams: 100, isStaple: false),
        "ribeye": NaturalPortion(grams: 230, unit: "steak", plural: "steaks", purchaseUnit: "steak", purchaseUnitPlural: "steaks", purchaseGrams: 230, isStaple: false),
        "sirloin steak": NaturalPortion(grams: 200, unit: "steak", plural: "steaks", purchaseUnit: "steak", purchaseUnitPlural: "steaks", purchaseGrams: 200, isStaple: false),
        "white fish": NaturalPortion(grams: 150, unit: "fillet", plural: "fillets", purchaseUnit: "fillet", purchaseUnitPlural: "fillets", purchaseGrams: 150, isStaple: false),
        "cod fillet": NaturalPortion(grams: 150, unit: "fillet", plural: "fillets", purchaseUnit: "fillet", purchaseUnitPlural: "fillets", purchaseGrams: 150, isStaple: false),
        "shrimp": NaturalPortion(grams: 85, unit: "handful", plural: "handfuls", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 450, isStaple: false),

        // Drinks / pantry beverages ──────────────────────────────
        "coconut water": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "carton", purchaseUnitPlural: "cartons", purchaseGrams: 500, isStaple: false),
        "oat milk": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "liter", purchaseUnitPlural: "liters", purchaseGrams: 1000, isStaple: false),
        "soy milk": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "liter", purchaseUnitPlural: "liters", purchaseGrams: 1000, isStaple: false),
        "orange juice": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "carton", purchaseUnitPlural: "cartons", purchaseGrams: 1750, isStaple: false),
        "apple juice": NaturalPortion(grams: 240, unit: "cup", plural: "cups", purchaseUnit: "carton", purchaseUnitPlural: "cartons", purchaseGrams: 1750, isStaple: false),
        "espresso": NaturalPortion(grams: 30, unit: "shot", plural: "shots", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 250, isStaple: false),
        "ground coffee": .staple(unit: "bag", plural: "bags"),
        "tea bags": .staple(unit: "box", plural: "boxes"),

        // Baking / dessert ───────────────────────────────────────
        "dark chocolate": NaturalPortion(grams: 10, unit: "square", plural: "squares", purchaseUnit: "bar", purchaseUnitPlural: "bars", purchaseGrams: 100, isStaple: false),
        "milk chocolate": NaturalPortion(grams: 10, unit: "square", plural: "squares", purchaseUnit: "bar", purchaseUnitPlural: "bars", purchaseGrams: 100, isStaple: false),
        "chocolate chips": NaturalPortion(grams: 30, unit: "tbsp", plural: "tbsp", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 340, isStaple: false),
        "raisins": NaturalPortion(grams: 30, unit: "handful", plural: "handfuls", purchaseUnit: "box", purchaseUnitPlural: "boxes", purchaseGrams: 425, isStaple: false),
        "dates": .simple(grams: 8, unit: "date", plural: "dates"),

        // More produce ───────────────────────────────────────────
        "scallion": NaturalPortion(grams: 15, unit: "stalk", plural: "stalks", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 120, isStaple: false),
        "arugula": NaturalPortion(grams: 20, unit: "cup", plural: "cups", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 150, isStaple: false),
        "radish": NaturalPortion(grams: 15, unit: "radish", plural: "radishes", purchaseUnit: "bunch", purchaseUnitPlural: "bunches", purchaseGrams: 200, isStaple: false),
        "cabbage": NaturalPortion(grams: 90, unit: "cup", plural: "cups", purchaseUnit: "head", purchaseUnitPlural: "heads", purchaseGrams: 900, isStaple: false),
        "brussels sprouts": NaturalPortion(grams: 88, unit: "cup", plural: "cups", purchaseUnit: "bag", purchaseUnitPlural: "bags", purchaseGrams: 450, isStaple: false),
        "corn": NaturalPortion(grams: 75, unit: "cup", plural: "cups", purchaseUnit: "can", purchaseUnitPlural: "cans", purchaseGrams: 425, isStaple: false),

        // Water — ubiquitous, no need to track ────────────────────
        "water": .staple(unit: "tap", plural: "tap"),
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
