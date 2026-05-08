//
// MealPlanPrompts.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation

// MARK: - Meal Plan Prompts

/// Static prompt templates for Claude Sonnet meal plan generation.
/// Per AI_INTELLIGENCE_ENGINE.md Section 3 -- all prompts use XML tags for structured context,
/// reference exact numbers, and include safety rails.
/// Voice follows UX_COPY_BIBLE.md Section 1.1: Drill Sergeant default.
enum MealPlanPrompts {
    // MARK: - Dietary Restrictions

    struct DietaryRestrictions {
        let isLactoseFree: Bool
        let noCoffee: Bool
        let isGlutenFree: Bool
        let isVegetarian: Bool
        let isVegan: Bool
        let isHalal: Bool
        let isNutFree: Bool
        let isShellFishAllergy: Bool
        let allergies: [String]
        let dislikedFoods: [String]

        init(from profile: DietaryProfile) {
            isLactoseFree = profile.isLactoseFree
            noCoffee = profile.noCoffee
            isGlutenFree = profile.isGlutenFree
            isVegetarian = profile.isVegetarian
            isVegan = profile.isVegan
            isHalal = profile.isHalal
            isNutFree = profile.isNutFree
            isShellFishAllergy = profile.isShellFishAllergy
            allergies = profile.allergies
            dislikedFoods = profile.dislikedFoods
        }

        init(
            isLactoseFree: Bool = false,
            noCoffee: Bool = false,
            isGlutenFree: Bool = false,
            isVegetarian: Bool = false,
            isVegan: Bool = false,
            isHalal: Bool = false,
            isNutFree: Bool = false,
            isShellFishAllergy: Bool = false,
            allergies: [String] = [],
            dislikedFoods: [String] = []
        ) {
            self.isLactoseFree = isLactoseFree
            self.noCoffee = noCoffee
            self.isGlutenFree = isGlutenFree
            self.isVegetarian = isVegetarian
            self.isVegan = isVegan
            self.isHalal = isHalal
            self.isNutFree = isNutFree
            self.isShellFishAllergy = isShellFishAllergy
            self.allergies = allergies
            self.dislikedFoods = dislikedFoods
        }

        var formattedList: String {
            var lines: [String] = []
            if isLactoseFree {
                lines
                    .append(
                        "- LACTOSE-FREE: No milk, cheese, yogurt, cream, whey protein, or any dairy-containing products. Use lactose-free milk, coconut yogurt, oat milk, or soy-based alternatives."
                    )
            }
            if noCoffee {
                lines.append("- NO COFFEE: No coffee or coffee-based drinks. Tea is acceptable.")
            }
            if isGlutenFree {
                lines
                    .append(
                        "- GLUTEN-FREE: No wheat, barley, rye, or gluten-containing grains. Use rice, quinoa, oats (certified GF), potatoes, or corn-based alternatives."
                    )
            }
            if isVegetarian {
                lines.append("- VEGETARIAN: No meat or fish. Eggs and dairy are acceptable unless otherwise restricted.")
            }
            if isVegan {
                lines
                    .append(
                        "- VEGAN: No animal products whatsoever. No meat, fish, eggs, dairy, honey. Use plant-based protein sources: tofu, tempeh, legumes, seitan, nutritional yeast."
                    )
            }
            if isHalal {
                lines
                    .append("- HALAL: No pork, no alcohol in cooking, all meat must be halal-certified. No gelatin from non-halal sources.")
            }
            if isNutFree {
                lines
                    .append(
                        "- NUT-FREE: No tree nuts (almonds, walnuts, cashews, pecans, pistachios, etc.) or peanuts. No nut butters, nut milks, or nut-derived oils."
                    )
            }
            if isShellFishAllergy {
                lines
                    .append(
                        "- SHELLFISH ALLERGY (STRICT EXCLUSION): No shrimp, crab, lobster, mussels, clams, oysters, scallops, or any shellfish-derived ingredients."
                    )
            }
            if !allergies.isEmpty {
                lines.append("- ALLERGIES (STRICT EXCLUSION): \(allergies.joined(separator: ", "))")
            }
            if !dislikedFoods.isEmpty {
                lines.append("- DISLIKED FOODS (avoid): \(dislikedFoods.joined(separator: ", "))")
            }
            if lines.isEmpty {
                return "None."
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Weekly Plan Prompt

    /// Generate a full weekly meal plan with exact macros per day type.
    /// Model: Sonnet | Temp: 0.3 | Max tokens: 4096 | Timeout: 30s
    static func weeklyPlanPrompt(
        targets: [DayType: MacroTargets],
        restrictions: DietaryRestrictions,
        preferences: String
    ) -> (system: String, user: String) {
        let system = """
        You are the nutrition arm of Tempo, a drill-sergeant life operating system for student-athletes. \
        You generate structured, macro-precise weekly meal plans as valid JSON.

        <voice>
        - You are a sports nutritionist who programs fuel, not a chef who writes recipes.
        - Every gram is intentional. Every meal earns its slot.
        - No fluff, no "enjoy your meal" nonsense. This is a prescription.
        - Use common, student-affordable foods. No specialty ingredients.
        - Meals must be practical: under 20 min prep for weekday meals.
        </voice>

        <safety>
        - NEVER plan below 1,500 kcal/day for any reason.
        - NEVER skip meals or suggest fasting windows.
        - NEVER recommend specific supplements, brands, or products.
        - NEVER give medical or clinical nutrition advice.
        - NEVER include foods that violate the stated dietary restrictions.
        - If lactose-free is specified, absolutely NO dairy products -- use alternatives only.
        - Output ONLY valid JSON. No markdown wrapping, no code blocks, no preamble.
        </safety>
        """

        // Build day-type target lines
        var targetLines = ""
        for dayType in DayType.allCases {
            if let t = targets[dayType] {
                targetLines += """
                - \(dayType.displayName): \(t.calories) kcal, \(t.proteinGrams)g P, \(t.carbsGrams)g C, \(t.fatGrams)g F
                \n
                """
            }
        }

        let user = """
        Generate a 7-day meal plan. Each day has a day type with specific macro targets.

        <data>
        <macro_targets_by_day_type>
        \(targetLines)</macro_targets_by_day_type>

        <dietary_restrictions>
        \(restrictions.formattedList)
        </dietary_restrictions>

        <preferences>
        \(preferences.isEmpty ? "No specific preferences." : preferences)
        </preferences>

        <meal_structure>
        - 4 meals per day: Breakfast, Lunch, Dinner, Snack
        - Breakfast: 25% of daily calories
        - Lunch: 30% of daily calories
        - Dinner: 30% of daily calories
        - Snack: 15% of daily calories
        - Front-load protein: breakfast and lunch should each have 30%+ of daily protein
        </meal_structure>
        </data>

        Return ONLY valid JSON (start with {, no markdown, no code blocks) matching this exact schema:
        {
            "days": [
                {
                    "dayIndex": 0,
                    "dayType": "strength",
                    "meals": [
                        {
                            "mealNumber": 1,
                            "mealName": "Breakfast",
                            "scheduledTime": "07:30",
                            "foods": [
                                {
                                    "name": "string (food name, lowercase)",
                                    "quantityGrams": number,
                                    "calories": number,
                                    "proteinG": number,
                                    "carbsG": number,
                                    "fatG": number
                                }
                            ]
                        }
                    ]
                }
            ]
        }

        Rules:
        - dayIndex 0 = Monday, 6 = Sunday.
        - dayType must be one of: strength, cardio, soccer, double, rest.
        - Assign day types to match a typical training week: 3-4 training days, 1-2 rest days. Vary the types.
        - mealNumber: 1 = Breakfast, 2 = Lunch, 3 = Dinner, 4 = Snack.
        - scheduledTime format: "HH:mm" (24h). Breakfast ~07:30, Lunch ~12:30, Dinner ~19:30, Snack ~16:00.
        - Each food's macros must be realistic for the stated quantity. Reference standard per-100g values.
        - Each meal's total macros (sum of foods) must match the meal's share of the day's target within 5%.
        - Each day's total macros (sum of meals) must match the day type's target within 3%.
        - Use varied foods across the week. No identical meals on consecutive days.
        - Include 2-4 foods per meal. Keep it simple and student-practical.
        - All quantities in raw/uncooked grams unless the food is consumed raw (fruits, bread, etc.).
        """

        return (system: system, user: user)
    }
}
