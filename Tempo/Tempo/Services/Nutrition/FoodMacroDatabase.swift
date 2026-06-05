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

        // ── Expanded Proteins ─────────────────────────────────────
        // Italian + US common cuts. Values per 100g raw (unless noted).
        "chicken drumstick": FoodMacros(calories: 172, protein: 28.3, carbs: 0.0, fat: 5.7, fiber: 0.0),
        "chicken wing": FoodMacros(calories: 203, protein: 30.5, carbs: 0.0, fat: 8.1, fiber: 0.0),
        "chicken leg quarter": FoodMacros(calories: 184, protein: 26.0, carbs: 0.0, fat: 8.4, fiber: 0.0),
        "rotisserie chicken": FoodMacros(calories: 190, protein: 26.0, carbs: 0.0, fat: 9.0, fiber: 0.0),
        "duck breast": FoodMacros(calories: 195, protein: 23.5, carbs: 0.0, fat: 11.2, fiber: 0.0),
        "beef ribeye": FoodMacros(calories: 291, protein: 24.0, carbs: 0.0, fat: 21.0, fiber: 0.0),
        "beef filet mignon": FoodMacros(calories: 220, protein: 26.0, carbs: 0.0, fat: 12.6, fiber: 0.0),
        "beef flank steak": FoodMacros(calories: 196, protein: 28.0, carbs: 0.0, fat: 8.6, fiber: 0.0),
        "beef brisket": FoodMacros(calories: 235, protein: 21.0, carbs: 0.0, fat: 16.0, fiber: 0.0),
        "ground beef 93/7": FoodMacros(calories: 152, protein: 21.0, carbs: 0.0, fat: 7.0, fiber: 0.0),
        "ground beef 85/15": FoodMacros(calories: 215, protein: 18.6, carbs: 0.0, fat: 15.0, fiber: 0.0),
        "veal cutlet": FoodMacros(calories: 172, protein: 26.0, carbs: 0.0, fat: 7.0, fiber: 0.0),
        "veal scallopini": FoodMacros(calories: 172, protein: 26.0, carbs: 0.0, fat: 7.0, fiber: 0.0),
        "lamb chop": FoodMacros(calories: 294, protein: 25.0, carbs: 0.0, fat: 21.0, fiber: 0.0),
        "lamb shoulder": FoodMacros(calories: 235, protein: 20.0, carbs: 0.0, fat: 17.0, fiber: 0.0),
        "pork loin": FoodMacros(calories: 198, protein: 26.0, carbs: 0.0, fat: 10.0, fiber: 0.0),
        "pork chop": FoodMacros(calories: 231, protein: 25.0, carbs: 0.0, fat: 14.0, fiber: 0.0),
        "pork belly": FoodMacros(calories: 518, protein: 9.3, carbs: 0.0, fat: 53.0, fiber: 0.0),
        "pork sausage": FoodMacros(calories: 290, protein: 12.0, carbs: 2.4, fat: 26.0, fiber: 0.0),
        "italian sausage": FoodMacros(calories: 268, protein: 14.0, carbs: 1.5, fat: 23.0, fiber: 0.0),
        "bacon": FoodMacros(calories: 541, protein: 37.0, carbs: 1.4, fat: 42.0, fiber: 0.0),
        "pancetta": FoodMacros(calories: 458, protein: 12.0, carbs: 0.0, fat: 45.0, fiber: 0.0),
        "prosciutto": FoodMacros(calories: 263, protein: 30.0, carbs: 0.0, fat: 15.0, fiber: 0.0),
        "prosciutto crudo": FoodMacros(calories: 263, protein: 30.0, carbs: 0.0, fat: 15.0, fiber: 0.0),
        "prosciutto cotto": FoodMacros(calories: 215, protein: 21.0, carbs: 1.0, fat: 14.0, fiber: 0.0),
        "bresaola": FoodMacros(calories: 151, protein: 32.0, carbs: 0.0, fat: 2.5, fiber: 0.0),
        "mortadella": FoodMacros(calories: 311, protein: 16.0, carbs: 2.0, fat: 27.0, fiber: 0.0),
        "salami": FoodMacros(calories: 425, protein: 22.0, carbs: 1.6, fat: 37.0, fiber: 0.0),
        "soppressata": FoodMacros(calories: 395, protein: 24.0, carbs: 2.0, fat: 33.0, fiber: 0.0),
        "ham": FoodMacros(calories: 145, protein: 21.0, carbs: 1.5, fat: 5.5, fiber: 0.0),
        "deli turkey": FoodMacros(calories: 104, protein: 17.0, carbs: 3.5, fat: 2.5, fiber: 0.0),
        "deli chicken": FoodMacros(calories: 95, protein: 18.0, carbs: 1.0, fat: 2.0, fiber: 0.0),
        "hot dog": FoodMacros(calories: 290, protein: 10.0, carbs: 2.0, fat: 26.0, fiber: 0.0),
        "anchovies": FoodMacros(calories: 210, protein: 29.0, carbs: 0.0, fat: 10.0, fiber: 0.0),
        "sardines": FoodMacros(calories: 208, protein: 24.6, carbs: 0.0, fat: 11.5, fiber: 0.0),
        "mackerel": FoodMacros(calories: 205, protein: 19.0, carbs: 0.0, fat: 14.0, fiber: 0.0),
        "sea bass": FoodMacros(calories: 124, protein: 23.0, carbs: 0.0, fat: 2.6, fiber: 0.0),
        "sea bream": FoodMacros(calories: 100, protein: 19.0, carbs: 0.0, fat: 2.5, fiber: 0.0),
        "branzino": FoodMacros(calories: 124, protein: 23.0, carbs: 0.0, fat: 2.6, fiber: 0.0),
        "trout": FoodMacros(calories: 148, protein: 21.0, carbs: 0.0, fat: 6.6, fiber: 0.0),
        "halibut": FoodMacros(calories: 111, protein: 23.0, carbs: 0.0, fat: 2.3, fiber: 0.0),
        "swordfish": FoodMacros(calories: 144, protein: 19.8, carbs: 0.0, fat: 6.6, fiber: 0.0),
        "octopus": FoodMacros(calories: 82, protein: 14.9, carbs: 2.2, fat: 1.0, fiber: 0.0),
        "squid": FoodMacros(calories: 92, protein: 15.6, carbs: 3.1, fat: 1.4, fiber: 0.0),
        "calamari": FoodMacros(calories: 92, protein: 15.6, carbs: 3.1, fat: 1.4, fiber: 0.0),
        "mussels": FoodMacros(calories: 86, protein: 12.0, carbs: 3.7, fat: 2.2, fiber: 0.0),
        "clams": FoodMacros(calories: 86, protein: 14.7, carbs: 3.0, fat: 1.0, fiber: 0.0),
        "scallops": FoodMacros(calories: 88, protein: 16.8, carbs: 2.4, fat: 0.8, fiber: 0.0),
        "crab": FoodMacros(calories: 87, protein: 18.0, carbs: 0.0, fat: 1.0, fiber: 0.0),
        "lobster": FoodMacros(calories: 89, protein: 19.0, carbs: 0.0, fat: 0.9, fiber: 0.0),
        "seitan": FoodMacros(calories: 121, protein: 25.0, carbs: 4.0, fat: 1.9, fiber: 0.6),

        // ── Expanded Carbs ────────────────────────────────────────
        "penne": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "fusilli": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "spaghetti": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "rigatoni": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "linguine": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "fettuccine": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "tagliatelle": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "orzo": FoodMacros(calories: 369, protein: 12.0, carbs: 76.0, fat: 1.2, fiber: 3.4),
        "lasagna sheets": FoodMacros(calories: 371, protein: 13.0, carbs: 75.0, fat: 1.5, fiber: 3.2),
        "ravioli": FoodMacros(calories: 270, protein: 11.0, carbs: 40.0, fat: 7.0, fiber: 2.0),
        "tortellini": FoodMacros(calories: 290, protein: 13.0, carbs: 43.0, fat: 7.0, fiber: 2.0),
        "gnocchi": FoodMacros(calories: 133, protein: 3.5, carbs: 27.0, fat: 0.7, fiber: 1.5),
        "cooked pasta": FoodMacros(calories: 131, protein: 5.0, carbs: 25.0, fat: 1.1, fiber: 1.8),
        "cooked rice": FoodMacros(calories: 130, protein: 2.7, carbs: 28.0, fat: 0.3, fiber: 0.4),
        "cooked brown rice": FoodMacros(calories: 123, protein: 2.6, carbs: 26.0, fat: 1.0, fiber: 1.8),
        "cooked oats": FoodMacros(calories: 71, protein: 2.5, carbs: 12.0, fat: 1.5, fiber: 1.7),
        "jasmine rice": FoodMacros(calories: 356, protein: 7.5, carbs: 79.0, fat: 0.7, fiber: 0.5),
        "wild rice": FoodMacros(calories: 357, protein: 14.7, carbs: 75.0, fat: 1.1, fiber: 6.2),
        "arborio rice": FoodMacros(calories: 358, protein: 7.0, carbs: 80.0, fat: 0.6, fiber: 1.5),
        "risotto rice": FoodMacros(calories: 358, protein: 7.0, carbs: 80.0, fat: 0.6, fiber: 1.5),
        "barley": FoodMacros(calories: 354, protein: 12.5, carbs: 73.0, fat: 2.3, fiber: 17.3),
        "farro": FoodMacros(calories: 340, protein: 14.6, carbs: 71.0, fat: 2.5, fiber: 10.7),
        "bulgur": FoodMacros(calories: 342, protein: 12.3, carbs: 75.9, fat: 1.3, fiber: 18.3),
        "polenta": FoodMacros(calories: 362, protein: 8.0, carbs: 79.0, fat: 1.4, fiber: 5.0),
        "cooked polenta": FoodMacros(calories: 70, protein: 1.5, carbs: 15.0, fat: 0.3, fiber: 1.0),
        "cornmeal": FoodMacros(calories: 362, protein: 8.0, carbs: 79.0, fat: 1.4, fiber: 5.0),
        "buckwheat": FoodMacros(calories: 343, protein: 13.3, carbs: 71.5, fat: 3.4, fiber: 10.0),
        "millet": FoodMacros(calories: 378, protein: 11.0, carbs: 73.0, fat: 4.2, fiber: 8.5),
        "ciabatta": FoodMacros(calories: 271, protein: 9.0, carbs: 52.0, fat: 2.8, fiber: 2.0),
        "focaccia": FoodMacros(calories: 271, protein: 7.5, carbs: 43.0, fat: 7.7, fiber: 2.5),
        "baguette": FoodMacros(calories: 274, protein: 9.0, carbs: 55.0, fat: 1.5, fiber: 2.5),
        "sourdough bread": FoodMacros(calories: 256, protein: 10.0, carbs: 51.0, fat: 1.6, fiber: 2.4),
        "rye bread": FoodMacros(calories: 259, protein: 8.5, carbs: 48.0, fat: 3.3, fiber: 5.8),
        "pita bread": FoodMacros(calories: 275, protein: 9.1, carbs: 55.7, fat: 1.2, fiber: 2.2),
        "naan": FoodMacros(calories: 310, protein: 9.0, carbs: 50.0, fat: 7.0, fiber: 2.0),
        "english muffin": FoodMacros(calories: 232, protein: 9.0, carbs: 45.0, fat: 1.7, fiber: 3.3),
        "bagel": FoodMacros(calories: 257, protein: 10.0, carbs: 50.0, fat: 1.5, fiber: 2.0),
        "croissant": FoodMacros(calories: 406, protein: 8.0, carbs: 46.0, fat: 21.0, fiber: 2.6),
        "crackers": FoodMacros(calories: 502, protein: 9.0, carbs: 64.0, fat: 22.0, fiber: 3.0),
        "saltines": FoodMacros(calories: 421, protein: 9.5, carbs: 71.0, fat: 11.0, fiber: 2.5),
        "pretzels": FoodMacros(calories: 380, protein: 10.0, carbs: 80.0, fat: 3.0, fiber: 3.4),
        "popcorn": FoodMacros(calories: 387, protein: 12.0, carbs: 78.0, fat: 4.5, fiber: 14.5),
        "corn tortilla": FoodMacros(calories: 218, protein: 5.7, carbs: 45.0, fat: 2.9, fiber: 6.3),
        "flour tortilla": FoodMacros(calories: 304, protein: 8.0, carbs: 51.0, fat: 7.0, fiber: 3.0),
        "pizza dough": FoodMacros(calories: 250, protein: 8.0, carbs: 51.0, fat: 2.0, fiber: 2.0),
        "white flour": FoodMacros(calories: 364, protein: 10.3, carbs: 76.3, fat: 1.0, fiber: 2.7),
        "whole wheat flour": FoodMacros(calories: 340, protein: 13.2, carbs: 72.0, fat: 2.5, fiber: 10.7),
        "almond flour": FoodMacros(calories: 571, protein: 21.4, carbs: 21.4, fat: 50.0, fiber: 10.7),
        "coconut flour": FoodMacros(calories: 400, protein: 20.0, carbs: 60.0, fat: 13.0, fiber: 40.0),
        "rice flour": FoodMacros(calories: 366, protein: 6.0, carbs: 80.0, fat: 1.4, fiber: 2.4),
        "breadcrumbs": FoodMacros(calories: 395, protein: 13.0, carbs: 72.0, fat: 5.3, fiber: 4.5),
        "panko": FoodMacros(calories: 380, protein: 11.0, carbs: 75.0, fat: 4.0, fiber: 4.0),

        // ── Expanded Fats ─────────────────────────────────────────
        "extra virgin olive oil": FoodMacros(calories: 884, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "evoo": FoodMacros(calories: 884, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "vegetable oil": FoodMacros(calories: 884, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "canola oil": FoodMacros(calories: 884, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "sunflower oil": FoodMacros(calories: 884, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "sesame oil": FoodMacros(calories: 884, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "ghee": FoodMacros(calories: 900, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "lard": FoodMacros(calories: 902, protein: 0.0, carbs: 0.0, fat: 100.0, fiber: 0.0),
        "mayonnaise": FoodMacros(calories: 680, protein: 1.0, carbs: 0.6, fat: 75.0, fiber: 0.0),
        "tahini": FoodMacros(calories: 595, protein: 17.0, carbs: 21.0, fat: 53.8, fiber: 9.3),
        "pesto": FoodMacros(calories: 418, protein: 5.0, carbs: 6.0, fat: 42.0, fiber: 1.0),
        "ricotta": FoodMacros(calories: 174, protein: 11.4, carbs: 3.0, fat: 13.0, fiber: 0.0),
        "ricotta light": FoodMacros(calories: 138, protein: 12.4, carbs: 3.0, fat: 7.5, fiber: 0.0),
        "mascarpone": FoodMacros(calories: 450, protein: 4.0, carbs: 4.0, fat: 47.0, fiber: 0.0),
        "burrata": FoodMacros(calories: 330, protein: 16.0, carbs: 1.0, fat: 30.0, fiber: 0.0),
        "buffalo mozzarella": FoodMacros(calories: 288, protein: 17.0, carbs: 1.0, fat: 24.0, fiber: 0.0),
        "feta": FoodMacros(calories: 264, protein: 14.2, carbs: 4.1, fat: 21.3, fiber: 0.0),
        "goat cheese": FoodMacros(calories: 364, protein: 22.0, carbs: 2.5, fat: 30.0, fiber: 0.0),
        "blue cheese": FoodMacros(calories: 353, protein: 21.0, carbs: 2.3, fat: 29.0, fiber: 0.0),
        "gorgonzola": FoodMacros(calories: 353, protein: 21.0, carbs: 2.3, fat: 29.0, fiber: 0.0),
        "pecorino": FoodMacros(calories: 387, protein: 26.0, carbs: 0.0, fat: 32.0, fiber: 0.0),
        "pecorino romano": FoodMacros(calories: 387, protein: 26.0, carbs: 0.0, fat: 32.0, fiber: 0.0),
        "grana padano": FoodMacros(calories: 384, protein: 33.0, carbs: 0.0, fat: 28.0, fiber: 0.0),
        "asiago": FoodMacros(calories: 392, protein: 30.0, carbs: 1.5, fat: 30.0, fiber: 0.0),
        "provolone": FoodMacros(calories: 351, protein: 26.0, carbs: 2.1, fat: 27.0, fiber: 0.0),
        "fontina": FoodMacros(calories: 389, protein: 25.0, carbs: 1.6, fat: 31.0, fiber: 0.0),
        "gouda": FoodMacros(calories: 356, protein: 25.0, carbs: 2.2, fat: 27.4, fiber: 0.0),
        "brie": FoodMacros(calories: 334, protein: 21.0, carbs: 0.5, fat: 28.0, fiber: 0.0),
        "swiss cheese": FoodMacros(calories: 380, protein: 27.0, carbs: 5.4, fat: 28.0, fiber: 0.0),
        "string cheese": FoodMacros(calories: 280, protein: 27.0, carbs: 2.0, fat: 18.0, fiber: 0.0),
        "milk whole": FoodMacros(calories: 61, protein: 3.2, carbs: 4.8, fat: 3.3, fiber: 0.0),
        "milk 2%": FoodMacros(calories: 50, protein: 3.3, carbs: 4.7, fat: 2.0, fiber: 0.0),
        "milk skim": FoodMacros(calories: 34, protein: 3.4, carbs: 5.0, fat: 0.2, fiber: 0.0),
        "milk lactose free": FoodMacros(calories: 50, protein: 3.3, carbs: 5.0, fat: 2.0, fiber: 0.0),
        "heavy cream": FoodMacros(calories: 345, protein: 2.0, carbs: 2.8, fat: 37.0, fiber: 0.0),
        "half and half": FoodMacros(calories: 130, protein: 3.0, carbs: 4.3, fat: 11.5, fiber: 0.0),
        "yogurt whole": FoodMacros(calories: 61, protein: 3.5, carbs: 4.7, fat: 3.3, fiber: 0.0),
        "skyr": FoodMacros(calories: 63, protein: 11.0, carbs: 4.0, fat: 0.2, fiber: 0.0),
        "kefir": FoodMacros(calories: 51, protein: 3.3, carbs: 4.8, fat: 1.6, fiber: 0.0),

        // ── Expanded Vegetables ───────────────────────────────────
        "arugula": FoodMacros(calories: 25, protein: 2.6, carbs: 3.7, fat: 0.7, fiber: 1.6),
        "radicchio": FoodMacros(calories: 23, protein: 1.4, carbs: 4.5, fat: 0.3, fiber: 0.9),
        "endive": FoodMacros(calories: 17, protein: 1.3, carbs: 3.4, fat: 0.2, fiber: 3.1),
        "romaine": FoodMacros(calories: 17, protein: 1.2, carbs: 3.3, fat: 0.3, fiber: 2.1),
        "iceberg": FoodMacros(calories: 14, protein: 0.9, carbs: 3.0, fat: 0.1, fiber: 1.2),
        "spinach baby": FoodMacros(calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4, fiber: 2.2),
        "chard": FoodMacros(calories: 19, protein: 1.8, carbs: 3.7, fat: 0.2, fiber: 1.6),
        "swiss chard": FoodMacros(calories: 19, protein: 1.8, carbs: 3.7, fat: 0.2, fiber: 1.6),
        "collard greens": FoodMacros(calories: 32, protein: 3.0, carbs: 5.4, fat: 0.6, fiber: 4.0),
        "brussels sprouts": FoodMacros(calories: 43, protein: 3.4, carbs: 8.9, fat: 0.3, fiber: 3.8),
        "artichoke": FoodMacros(calories: 47, protein: 3.3, carbs: 10.5, fat: 0.2, fiber: 5.4),
        "fennel": FoodMacros(calories: 31, protein: 1.2, carbs: 7.3, fat: 0.2, fiber: 3.1),
        "leek": FoodMacros(calories: 61, protein: 1.5, carbs: 14.0, fat: 0.3, fiber: 1.8),
        "shallot": FoodMacros(calories: 72, protein: 2.5, carbs: 17.0, fat: 0.1, fiber: 3.2),
        "garlic": FoodMacros(calories: 149, protein: 6.4, carbs: 33.0, fat: 0.5, fiber: 2.1),
        "ginger": FoodMacros(calories: 80, protein: 1.8, carbs: 18.0, fat: 0.8, fiber: 2.0),
        "red onion": FoodMacros(calories: 40, protein: 1.1, carbs: 9.3, fat: 0.1, fiber: 1.7),
        "green onion": FoodMacros(calories: 32, protein: 1.8, carbs: 7.3, fat: 0.2, fiber: 2.6),
        "scallion": FoodMacros(calories: 32, protein: 1.8, carbs: 7.3, fat: 0.2, fiber: 2.6),
        "chive": FoodMacros(calories: 30, protein: 3.3, carbs: 4.4, fat: 0.7, fiber: 2.5),
        "red bell pepper": FoodMacros(calories: 31, protein: 1.0, carbs: 6.0, fat: 0.3, fiber: 2.1),
        "yellow bell pepper": FoodMacros(calories: 27, protein: 1.0, carbs: 6.3, fat: 0.2, fiber: 0.9),
        "green bell pepper": FoodMacros(calories: 20, protein: 0.9, carbs: 4.6, fat: 0.2, fiber: 1.7),
        "jalapeno": FoodMacros(calories: 29, protein: 0.9, carbs: 6.5, fat: 0.4, fiber: 2.8),
        "chili pepper": FoodMacros(calories: 40, protein: 1.9, carbs: 8.8, fat: 0.4, fiber: 1.5),
        "cherry tomatoes": FoodMacros(calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2, fiber: 1.2),
        "roma tomatoes": FoodMacros(calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2, fiber: 1.2),
        "san marzano tomatoes": FoodMacros(calories: 25, protein: 1.2, carbs: 5.0, fat: 0.2, fiber: 1.5),
        "sun dried tomatoes": FoodMacros(calories: 258, protein: 14.1, carbs: 56.0, fat: 3.0, fiber: 12.3),
        "tomato sauce": FoodMacros(calories: 50, protein: 1.8, carbs: 9.0, fat: 1.0, fiber: 2.0),
        "marinara": FoodMacros(calories: 64, protein: 1.6, carbs: 10.0, fat: 2.0, fiber: 2.5),
        "tomato paste": FoodMacros(calories: 82, protein: 4.3, carbs: 19.0, fat: 0.5, fiber: 4.1),
        "olives green": FoodMacros(calories: 145, protein: 1.0, carbs: 3.8, fat: 15.3, fiber: 3.3),
        "olives black": FoodMacros(calories: 115, protein: 0.8, carbs: 6.3, fat: 10.7, fiber: 3.2),
        "olives kalamata": FoodMacros(calories: 142, protein: 1.5, carbs: 6.0, fat: 13.0, fiber: 3.0),
        "capers": FoodMacros(calories: 23, protein: 2.4, carbs: 4.9, fat: 0.9, fiber: 3.2),
        "pickle": FoodMacros(calories: 11, protein: 0.3, carbs: 2.3, fat: 0.2, fiber: 1.0),
        "sauerkraut": FoodMacros(calories: 19, protein: 0.9, carbs: 4.3, fat: 0.1, fiber: 2.9),
        "kimchi": FoodMacros(calories: 23, protein: 1.7, carbs: 4.0, fat: 0.5, fiber: 1.6),
        "squash butternut": FoodMacros(calories: 45, protein: 1.0, carbs: 11.7, fat: 0.1, fiber: 2.0),
        "squash spaghetti": FoodMacros(calories: 31, protein: 0.6, carbs: 7.0, fat: 0.6, fiber: 1.5),
        "pumpkin": FoodMacros(calories: 26, protein: 1.0, carbs: 6.5, fat: 0.1, fiber: 0.5),
        "beets": FoodMacros(calories: 43, protein: 1.6, carbs: 9.6, fat: 0.2, fiber: 2.8),
        "parsnip": FoodMacros(calories: 75, protein: 1.2, carbs: 18.0, fat: 0.3, fiber: 4.9),
        "turnip": FoodMacros(calories: 28, protein: 0.9, carbs: 6.4, fat: 0.1, fiber: 1.8),
        "radish": FoodMacros(calories: 16, protein: 0.7, carbs: 3.4, fat: 0.1, fiber: 1.6),
        "celeriac": FoodMacros(calories: 42, protein: 1.5, carbs: 9.2, fat: 0.3, fiber: 1.8),
        "rutabaga": FoodMacros(calories: 37, protein: 1.1, carbs: 8.6, fat: 0.2, fiber: 2.3),
        "corn": FoodMacros(calories: 86, protein: 3.3, carbs: 18.7, fat: 1.4, fiber: 2.0),
        "peas": FoodMacros(calories: 81, protein: 5.4, carbs: 14.5, fat: 0.4, fiber: 5.7),
        "snap peas": FoodMacros(calories: 42, protein: 2.8, carbs: 7.5, fat: 0.2, fiber: 2.6),
        "snow peas": FoodMacros(calories: 42, protein: 2.8, carbs: 7.5, fat: 0.2, fiber: 2.6),

        // ── Expanded Fruits ───────────────────────────────────────
        "pear": FoodMacros(calories: 57, protein: 0.4, carbs: 15.2, fat: 0.1, fiber: 3.1),
        "peach": FoodMacros(calories: 39, protein: 0.9, carbs: 9.5, fat: 0.3, fiber: 1.5),
        "nectarine": FoodMacros(calories: 44, protein: 1.1, carbs: 10.6, fat: 0.3, fiber: 1.7),
        "plum": FoodMacros(calories: 46, protein: 0.7, carbs: 11.4, fat: 0.3, fiber: 1.4),
        "apricot": FoodMacros(calories: 48, protein: 1.4, carbs: 11.1, fat: 0.4, fiber: 2.0),
        "cherry": FoodMacros(calories: 50, protein: 1.0, carbs: 12.2, fat: 0.3, fiber: 1.6),
        "grape": FoodMacros(calories: 69, protein: 0.7, carbs: 18.1, fat: 0.2, fiber: 0.9),
        "grapes": FoodMacros(calories: 69, protein: 0.7, carbs: 18.1, fat: 0.2, fiber: 0.9),
        "watermelon": FoodMacros(calories: 30, protein: 0.6, carbs: 7.6, fat: 0.2, fiber: 0.4),
        "cantaloupe": FoodMacros(calories: 34, protein: 0.8, carbs: 8.2, fat: 0.2, fiber: 0.9),
        "honeydew": FoodMacros(calories: 36, protein: 0.5, carbs: 9.1, fat: 0.1, fiber: 0.8),
        "pineapple": FoodMacros(calories: 50, protein: 0.5, carbs: 13.1, fat: 0.1, fiber: 1.4),
        "mango": FoodMacros(calories: 60, protein: 0.8, carbs: 15.0, fat: 0.4, fiber: 1.6),
        "papaya": FoodMacros(calories: 43, protein: 0.5, carbs: 11.0, fat: 0.3, fiber: 1.7),
        "kiwi": FoodMacros(calories: 61, protein: 1.1, carbs: 14.7, fat: 0.5, fiber: 3.0),
        "lemon": FoodMacros(calories: 29, protein: 1.1, carbs: 9.3, fat: 0.3, fiber: 2.8),
        "lime": FoodMacros(calories: 30, protein: 0.7, carbs: 10.5, fat: 0.2, fiber: 2.8),
        "grapefruit": FoodMacros(calories: 42, protein: 0.8, carbs: 10.7, fat: 0.1, fiber: 1.6),
        "mandarin": FoodMacros(calories: 53, protein: 0.8, carbs: 13.3, fat: 0.3, fiber: 1.8),
        "clementine": FoodMacros(calories: 47, protein: 0.9, carbs: 12.0, fat: 0.2, fiber: 1.7),
        "raspberries": FoodMacros(calories: 52, protein: 1.2, carbs: 11.9, fat: 0.7, fiber: 6.5),
        "blackberries": FoodMacros(calories: 43, protein: 1.4, carbs: 9.6, fat: 0.5, fiber: 5.3),
        "pomegranate": FoodMacros(calories: 83, protein: 1.7, carbs: 18.7, fat: 1.2, fiber: 4.0),
        "fig": FoodMacros(calories: 74, protein: 0.8, carbs: 19.2, fat: 0.3, fiber: 2.9),
        "dates": FoodMacros(calories: 277, protein: 1.8, carbs: 75.0, fat: 0.2, fiber: 6.7),
        "raisins": FoodMacros(calories: 299, protein: 3.1, carbs: 79.0, fat: 0.5, fiber: 3.7),
        "dried apricot": FoodMacros(calories: 241, protein: 3.4, carbs: 62.6, fat: 0.5, fiber: 7.3),
        "prunes": FoodMacros(calories: 240, protein: 2.2, carbs: 63.9, fat: 0.4, fiber: 7.1),
        "coconut": FoodMacros(calories: 354, protein: 3.3, carbs: 15.2, fat: 33.5, fiber: 9.0),

        // ── Nuts / Seeds ──────────────────────────────────────────
        "pistachios": FoodMacros(calories: 562, protein: 20.0, carbs: 28.0, fat: 45.0, fiber: 10.3),
        "pecans": FoodMacros(calories: 691, protein: 9.2, carbs: 14.0, fat: 72.0, fiber: 9.6),
        "hazelnuts": FoodMacros(calories: 628, protein: 15.0, carbs: 17.0, fat: 60.7, fiber: 9.7),
        "macadamia nuts": FoodMacros(calories: 718, protein: 7.9, carbs: 14.0, fat: 76.0, fiber: 8.6),
        "brazil nuts": FoodMacros(calories: 656, protein: 14.3, carbs: 12.3, fat: 66.4, fiber: 7.5),
        "pine nuts": FoodMacros(calories: 673, protein: 13.7, carbs: 13.1, fat: 68.4, fiber: 3.7),
        "sunflower seeds": FoodMacros(calories: 584, protein: 21.0, carbs: 20.0, fat: 51.5, fiber: 8.6),
        "pumpkin seeds": FoodMacros(calories: 559, protein: 30.0, carbs: 11.0, fat: 49.0, fiber: 6.0),
        "sesame seeds": FoodMacros(calories: 573, protein: 17.7, carbs: 23.4, fat: 49.7, fiber: 11.8),
        "hemp seeds": FoodMacros(calories: 553, protein: 31.6, carbs: 8.7, fat: 48.8, fiber: 4.0),
        "almond butter unsweetened": FoodMacros(calories: 614, protein: 21.0, carbs: 19.0, fat: 56.0, fiber: 10.0),
        "cashew butter": FoodMacros(calories: 587, protein: 17.6, carbs: 27.6, fat: 49.4, fiber: 2.0),

        // ── Legumes + Beans ───────────────────────────────────────
        "white beans": FoodMacros(calories: 333, protein: 23.4, carbs: 60.3, fat: 0.9, fiber: 15.3),
        "cannellini beans": FoodMacros(calories: 333, protein: 23.4, carbs: 60.3, fat: 0.9, fiber: 15.3),
        "borlotti beans": FoodMacros(calories: 335, protein: 23.0, carbs: 60.0, fat: 1.2, fiber: 25.0),
        "fava beans": FoodMacros(calories: 341, protein: 26.1, carbs: 58.3, fat: 1.5, fiber: 25.0),
        "split peas": FoodMacros(calories: 341, protein: 25.0, carbs: 60.0, fat: 1.2, fiber: 26.0),
        "navy beans": FoodMacros(calories: 337, protein: 22.3, carbs: 60.7, fat: 1.5, fiber: 24.4),
        "pinto beans": FoodMacros(calories: 347, protein: 21.4, carbs: 62.6, fat: 1.2, fiber: 15.5),
        "refried beans": FoodMacros(calories: 90, protein: 5.0, carbs: 14.0, fat: 1.5, fiber: 5.0),
        "lentils red": FoodMacros(calories: 358, protein: 24.6, carbs: 63.4, fat: 1.1, fiber: 10.7),
        "lentils green": FoodMacros(calories: 353, protein: 25.8, carbs: 63.4, fat: 1.1, fiber: 10.7),

        // ── Sweets / Snacks / Desserts ────────────────────────────
        "milk chocolate": FoodMacros(calories: 535, protein: 7.7, carbs: 59.4, fat: 30.0, fiber: 3.4),
        "dark chocolate 70%": FoodMacros(calories: 598, protein: 7.8, carbs: 45.9, fat: 42.6, fiber: 10.9),
        "white chocolate": FoodMacros(calories: 539, protein: 5.9, carbs: 59.2, fat: 32.1, fiber: 0.2),
        "nutella": FoodMacros(calories: 539, protein: 6.3, carbs: 57.5, fat: 30.9, fiber: 0.0),
        "cocoa powder": FoodMacros(calories: 228, protein: 19.6, carbs: 57.9, fat: 13.7, fiber: 33.2),
        "sugar": FoodMacros(calories: 387, protein: 0.0, carbs: 100.0, fat: 0.0, fiber: 0.0),
        "brown sugar": FoodMacros(calories: 380, protein: 0.0, carbs: 98.0, fat: 0.0, fiber: 0.0),
        "maple syrup": FoodMacros(calories: 260, protein: 0.0, carbs: 67.0, fat: 0.1, fiber: 0.0),
        "agave": FoodMacros(calories: 310, protein: 0.0, carbs: 76.4, fat: 0.4, fiber: 0.2),
        "ice cream vanilla": FoodMacros(calories: 207, protein: 3.5, carbs: 23.6, fat: 11.0, fiber: 0.7),
        "ice cream chocolate": FoodMacros(calories: 216, protein: 3.8, carbs: 28.2, fat: 11.0, fiber: 1.2),
        "gelato": FoodMacros(calories: 160, protein: 4.0, carbs: 22.0, fat: 6.0, fiber: 0.0),
        "frozen yogurt": FoodMacros(calories: 159, protein: 4.0, carbs: 24.0, fat: 5.6, fiber: 0.0),
        "cookies": FoodMacros(calories: 480, protein: 5.4, carbs: 64.0, fat: 22.0, fiber: 2.0),
        "biscotti": FoodMacros(calories: 425, protein: 7.0, carbs: 65.0, fat: 14.0, fiber: 2.0),
        "tiramisu": FoodMacros(calories: 275, protein: 4.0, carbs: 30.0, fat: 15.0, fiber: 0.5),
        "panna cotta": FoodMacros(calories: 220, protein: 3.0, carbs: 15.0, fat: 16.0, fiber: 0.0),
        "cannoli": FoodMacros(calories: 290, protein: 6.0, carbs: 30.0, fat: 16.0, fiber: 1.0),
        "donut": FoodMacros(calories: 421, protein: 4.9, carbs: 51.0, fat: 22.0, fiber: 1.5),
        "muffin": FoodMacros(calories: 377, protein: 5.5, carbs: 53.0, fat: 16.0, fiber: 1.5),
        "brownie": FoodMacros(calories: 466, protein: 6.0, carbs: 58.0, fat: 24.0, fiber: 2.5),
        "cake plain": FoodMacros(calories: 297, protein: 4.5, carbs: 50.0, fat: 9.0, fiber: 1.0),
        "cheesecake": FoodMacros(calories: 321, protein: 5.5, carbs: 26.0, fat: 22.0, fiber: 0.5),

        // ── Beverages ─────────────────────────────────────────────
        "coffee black": FoodMacros(calories: 2, protein: 0.3, carbs: 0.0, fat: 0.0, fiber: 0.0),
        "espresso": FoodMacros(calories: 9, protein: 0.5, carbs: 1.7, fat: 0.2, fiber: 0.0),
        "tea": FoodMacros(calories: 1, protein: 0.0, carbs: 0.3, fat: 0.0, fiber: 0.0),
        "green tea": FoodMacros(calories: 1, protein: 0.0, carbs: 0.3, fat: 0.0, fiber: 0.0),
        "matcha": FoodMacros(calories: 3, protein: 0.5, carbs: 0.5, fat: 0.0, fiber: 0.0),
        "orange juice": FoodMacros(calories: 45, protein: 0.7, carbs: 10.4, fat: 0.2, fiber: 0.2),
        "apple juice": FoodMacros(calories: 46, protein: 0.1, carbs: 11.3, fat: 0.1, fiber: 0.2),
        "cranberry juice": FoodMacros(calories: 46, protein: 0.0, carbs: 12.0, fat: 0.0, fiber: 0.0),
        "lemonade": FoodMacros(calories: 40, protein: 0.0, carbs: 10.0, fat: 0.0, fiber: 0.0),
        "coke": FoodMacros(calories: 42, protein: 0.0, carbs: 10.6, fat: 0.0, fiber: 0.0),
        "diet coke": FoodMacros(calories: 0, protein: 0.0, carbs: 0.0, fat: 0.0, fiber: 0.0),
        "sprite": FoodMacros(calories: 42, protein: 0.0, carbs: 10.6, fat: 0.0, fiber: 0.0),
        "beer": FoodMacros(calories: 43, protein: 0.5, carbs: 3.6, fat: 0.0, fiber: 0.0),
        "wine red": FoodMacros(calories: 85, protein: 0.1, carbs: 2.6, fat: 0.0, fiber: 0.0),
        "wine white": FoodMacros(calories: 82, protein: 0.1, carbs: 2.6, fat: 0.0, fiber: 0.0),
        "prosecco": FoodMacros(calories: 80, protein: 0.1, carbs: 1.5, fat: 0.0, fiber: 0.0),
        "champagne": FoodMacros(calories: 76, protein: 0.1, carbs: 1.5, fat: 0.0, fiber: 0.0),
        "vodka": FoodMacros(calories: 231, protein: 0.0, carbs: 0.0, fat: 0.0, fiber: 0.0),
        "whiskey": FoodMacros(calories: 250, protein: 0.0, carbs: 0.0, fat: 0.0, fiber: 0.0),
        "sports drink": FoodMacros(calories: 26, protein: 0.0, carbs: 6.0, fat: 0.0, fiber: 0.0),
        "soda water": FoodMacros(calories: 0, protein: 0.0, carbs: 0.0, fat: 0.0, fiber: 0.0),

        // ── Condiments / Sauces ───────────────────────────────────
        "ketchup": FoodMacros(calories: 112, protein: 1.0, carbs: 25.0, fat: 0.4, fiber: 0.3),
        "mustard": FoodMacros(calories: 66, protein: 4.0, carbs: 5.3, fat: 4.0, fiber: 3.3),
        "soy sauce": FoodMacros(calories: 53, protein: 8.1, carbs: 4.9, fat: 0.6, fiber: 0.8),
        "vinegar balsamic": FoodMacros(calories: 88, protein: 0.5, carbs: 17.0, fat: 0.0, fiber: 0.0),
        "vinegar white": FoodMacros(calories: 22, protein: 0.0, carbs: 0.9, fat: 0.0, fiber: 0.0),
        "vinegar apple cider": FoodMacros(calories: 22, protein: 0.0, carbs: 0.9, fat: 0.0, fiber: 0.0),
        "salt": FoodMacros(calories: 0, protein: 0.0, carbs: 0.0, fat: 0.0, fiber: 0.0),
        "pepper": FoodMacros(calories: 251, protein: 10.4, carbs: 64.0, fat: 3.3, fiber: 26.0),
        "salsa": FoodMacros(calories: 36, protein: 1.5, carbs: 7.7, fat: 0.2, fiber: 2.0),
        "guacamole": FoodMacros(calories: 150, protein: 2.0, carbs: 8.0, fat: 14.0, fiber: 6.0),
        "ranch dressing": FoodMacros(calories: 484, protein: 0.4, carbs: 6.4, fat: 51.0, fiber: 0.0),
        "italian dressing": FoodMacros(calories: 240, protein: 0.6, carbs: 11.0, fat: 23.0, fiber: 0.0),
        "vinaigrette": FoodMacros(calories: 290, protein: 0.4, carbs: 4.5, fat: 30.0, fiber: 0.0),
        "bbq sauce": FoodMacros(calories: 172, protein: 0.8, carbs: 41.0, fat: 0.4, fiber: 0.9),
        "hot sauce": FoodMacros(calories: 11, protein: 0.5, carbs: 1.8, fat: 0.4, fiber: 0.3),
        "sriracha": FoodMacros(calories: 100, protein: 2.0, carbs: 19.0, fat: 1.0, fiber: 2.0),

        // ── Prepared / Restaurant / Fast Food ─────────────────────
        "pizza margherita": FoodMacros(calories: 240, protein: 11.0, carbs: 30.0, fat: 8.0, fiber: 2.0),
        "pizza pepperoni": FoodMacros(calories: 285, protein: 12.0, carbs: 28.0, fat: 13.0, fiber: 2.0),
        "lasagna": FoodMacros(calories: 132, protein: 7.4, carbs: 12.0, fat: 6.0, fiber: 1.0),
        "carbonara": FoodMacros(calories: 165, protein: 8.0, carbs: 15.0, fat: 8.0, fiber: 0.8),
        "bolognese": FoodMacros(calories: 160, protein: 9.0, carbs: 15.0, fat: 7.0, fiber: 1.5),
        "pesto pasta": FoodMacros(calories: 220, protein: 7.0, carbs: 25.0, fat: 11.0, fiber: 1.5),
        "burger patty": FoodMacros(calories: 254, protein: 17.2, carbs: 0.0, fat: 20.0, fiber: 0.0),
        "cheeseburger": FoodMacros(calories: 295, protein: 17.0, carbs: 25.0, fat: 14.0, fiber: 1.2),
        "french fries": FoodMacros(calories: 312, protein: 3.4, carbs: 41.0, fat: 15.0, fiber: 3.8),
        "sweet potato fries": FoodMacros(calories: 162, protein: 1.7, carbs: 22.0, fat: 8.0, fiber: 3.3),
        "chicken nuggets": FoodMacros(calories: 297, protein: 15.0, carbs: 18.0, fat: 19.0, fiber: 1.0),
        "chicken sandwich": FoodMacros(calories: 245, protein: 18.0, carbs: 23.0, fat: 9.0, fiber: 1.5),
        "burrito": FoodMacros(calories: 206, protein: 9.0, carbs: 26.0, fat: 8.0, fiber: 3.0),
        "taco": FoodMacros(calories: 226, protein: 9.0, carbs: 18.0, fat: 13.0, fiber: 2.5),
        "sushi roll": FoodMacros(calories: 130, protein: 5.0, carbs: 26.0, fat: 1.0, fiber: 0.8),
        "salad caesar": FoodMacros(calories: 190, protein: 7.0, carbs: 8.0, fat: 15.0, fiber: 2.0),
        "salad greek": FoodMacros(calories: 130, protein: 4.0, carbs: 7.0, fat: 9.0, fiber: 2.5),
        "soup minestrone": FoodMacros(calories: 47, protein: 2.4, carbs: 8.0, fat: 1.1, fiber: 1.5),
        "soup chicken noodle": FoodMacros(calories: 38, protein: 2.4, carbs: 4.7, fat: 1.1, fiber: 0.4),
        "miso soup": FoodMacros(calories: 35, protein: 2.2, carbs: 4.0, fat: 1.0, fiber: 0.8),
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
        // `grams` is the COOKED eating portion (matches the NL parser's
        // "a chicken breast is ~150g cooked"); `purchaseGrams` is the RAW buy
        // weight (~170g, shrinks ~12% when cooked). Keeping them split means
        // the eaten-screen macros and the grocery list don't fight: logging
        // "1 breast" reads 150g, but the grocery list still tells you to buy
        // 170g raw.
        "chicken breast": NaturalPortion(grams: 150, unit: "breast", plural: "breasts", purchaseUnit: "breast", purchaseUnitPlural: "breasts", purchaseGrams: 170, isStaple: false),
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
        // unit/plural carry the FULL "rice cake(s)" — a bare "cake" dropped the
        // load-bearing word and the grocery list read "11 cakes". Keeping the
        // full noun also makes the grocery name-strip hit the right branch
        // ("rice cakes".contains("rice cakes")) → "11 rice cakes".
        "rice cakes": .simple(grams: 9, unit: "rice cake", plural: "rice cakes"),
        "bagel": .simple(grams: 100, unit: "bagel", plural: "bagels"),
        // Grocery-list polish: these canonical names (verified via probe) had
        // NO portion entry, so the grocery list showed raw grams ("Grain Bread
        // 249g", "Pasta Pomodoro Sauce 106g"). Buy-as-a-whole-unit portions so
        // the list reads like a shop ("1 loaf", "1 jar"). purchaseGrams is the
        // typical pack size used to round the week's gram total up to units.
        "grain bread": NaturalPortion(grams: 30, unit: "slice", plural: "slices", purchaseUnit: "loaf", purchaseUnitPlural: "loaves", purchaseGrams: 800, isStaple: false),
        "whole grain bread": NaturalPortion(grams: 30, unit: "slice", plural: "slices", purchaseUnit: "loaf", purchaseUnitPlural: "loaves", purchaseGrams: 800, isStaple: false),

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
        // Keyed by the CANONICAL name the grocery generator actually looks up
        // (verified via probe): "blueberries"/"frozen blueberries" canonicalize
        // to "berries", so the punnet portion must live under "berries" too —
        // otherwise it fell through to raw grams ("525g").
        "berries": NaturalPortion(grams: 140, unit: "cup", plural: "cups", purchaseUnit: "punnet", purchaseUnitPlural: "punnets", purchaseGrams: 170, isStaple: false),

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
        // Grocery-list polish (canonical names verified via probe) — were
        // showing raw grams. Sauces buy by the jar, juice by the bottle.
        "tomato sauce": NaturalPortion(grams: 100, unit: "g", plural: "g", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 400, isStaple: false),
        "pasta pomodoro sauce": NaturalPortion(grams: 100, unit: "g", plural: "g", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 400, isStaple: false),
        "pomodoro sauce": NaturalPortion(grams: 100, unit: "g", plural: "g", purchaseUnit: "jar", purchaseUnitPlural: "jars", purchaseGrams: 400, isStaple: false),
        "tart cherry juice": NaturalPortion(grams: 240, unit: "glass", plural: "glasses", purchaseUnit: "bottle", purchaseUnitPlural: "bottles", purchaseGrams: 1000, isStaple: false),
        "beetroot": .simple(grams: 80, unit: "beetroot", plural: "beetroots"),

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

    /// True when a food is counted in whole natural units (eggs, bananas,
    /// chicken breasts) rather than by mass. Used to decide whether a recipe
    /// ingredient should read "5 eggs" instead of "346 g eggs". A food is
    /// countable when it's in the portions table AND its recipe-side unit is
    /// not a gram/volume measure (g, ml, cup, tbsp, etc. stay mass/volume).
    static func isCountable(food: String) -> Bool {
        let normalized = food.lowercased().trimmingCharacters(in: .whitespaces)
        guard let portion = naturalPortions[normalized], !portion.isStaple else {
            return false
        }
        let massOrVolumeUnits: Set<String> = [
            "g", "kg", "ml", "l", "cup", "cups", "tbsp", "tsp", "oz", "lb",
            "scoop", "scoops", "handful", "handfuls",
        ]
        return !massOrVolumeUnits.contains(portion.unit.lowercased())
    }

    /// The best human label for a recipe ingredient amount. For COUNTABLE
    /// foods (eggs, bananas, breasts) the whole-unit form ("5 eggs") always
    /// wins — even over an AI-provided `aiLabel` that may have emitted a gram
    /// string ("346 g eggs"), which the user explicitly does not want. For
    /// non-countable foods (rice, chicken mince, oil) a non-empty `aiLabel`
    /// is preferred (it carries household context like "1 cup"), falling back
    /// to `formatPortion` which renders grams.
    static func bestPortionLabel(food: String, grams: Double, aiLabel: String?) -> String {
        if isCountable(food: food), grams > 0 {
            return formatPortion(food: food, grams: grams)
        }
        if let aiLabel, !aiLabel.isEmpty {
            return aiLabel
        }
        if grams > 0 {
            return formatPortion(food: food, grams: grams)
        }
        return aiLabel ?? ""
    }
}
