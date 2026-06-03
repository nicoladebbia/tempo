//
// MealRecipePrompts.swift
// Tempo
//
// Created by Tempo on 12/05/2026.
//
//

import Foundation

/// Prompt assembly for the Haiku-powered "generate full recipe for a planned meal" call.
///
/// Used by `MealPlanGeneratorService` after each `PlannedMeal` is persisted — one Haiku
/// call per meal, fanned out concurrently. Haiku returns a structured JSON object that
/// the generator decodes into `Recipe` + `RecipeIngredient` + `RecipeStep`.
enum MealRecipePrompts {
    /// Hard client-side cap on number of recipe steps. Keeps the meal-detail screen
    /// readable and the JSON payload bounded.
    static let maxSteps = 25

    static let systemPrompt: String = """
    You are a culinary assistant for a nutrition app called Tempo. Given a meal name,
    its target macros, and the foods it contains, output a fully-detailed recipe.

    HARD RULES:
    1. Output VALID JSON ONLY. No prose, no markdown, no code fences.
    2. Return at most \(maxSteps) numbered steps. Combine fiddly steps if needed.
    3. `prepTimeMinutes` is hands-on prep before cooking starts. `cookTimeMinutes`
       is unattended/active cooking. Both are integers >= 0.
    4. Every ingredient must have `storageLocation` = "fridge" | "freezer" | "pantry"
       | "cupboard". Use "freezer" only when the user would realistically buy it
       frozen (frozen veg, frozen meat portions, frozen berries).
    5. `defrostLeadTimeHours` is an integer >= 0. Set > 0 ONLY when `storageLocation`
       is "freezer". Typical values: large meat cuts = 12, chicken breast = 8,
       shrimp/berries = 2, sliced bread = 1, ice cubes = 0.
    6. Macros per serving must be plausible. Calories should land within 10% of
       the calorie target provided.
    7. No optional or ambiguous ingredients ("a splash of", "to taste") — give
       concrete quantities in grams for solids, millilitres for liquids.
    8. `displayQuantity` is REQUIRED and must be a human shopping/cooking unit
       paired with the gram amount. Examples:
       - 180g carrots         → "3 medium carrots"
       - 240g black beans     → "1 can black beans (drained)"
       - 100g rolled oats     → "1 cup rolled oats"
       - 50g eggs             → "1 large egg"
       - 14g olive oil        → "1 tbsp olive oil"
       - 5g salt              → "1 tsp salt"
       - 110g chicken breast  → "1 small chicken breast"
       - 30g cheddar          → "1 slice cheddar"
       - 240g whole milk      → "1 cup whole milk"
       - 120g banana          → "1 medium banana"
       Use cups / tbsp / tsp for liquids and dry goods; pieces (egg, breast,
       carrot, banana) where the natural unit is a whole item; cans for
       canned legumes/tomatoes. NEVER output an empty string here.
       9. BUT do NOT invent a whole-item count for a food that is already a
       measured or processed form — "shredded", "diced", "ground", "sliced",
       "minced", "chopped", a sauce, a powder, or anything sold/stored by
       weight. For those, keep the gram/ml amount as the displayQuantity
       (e.g. 80g shredded carrots → "80 g shredded carrots", NOT "1 carrot";
       120g ground beef → "120 g ground beef"). Only use whole-item counts
       for foods genuinely bought as whole units.

    JSON SCHEMA (strict):
    {
      "name": "<recipe name>",
      "description": "<one-sentence summary>",
      "cuisine": "<cuisine or empty string>",
      "servings": <int>,
      "prepTimeMinutes": <int>,
      "cookTimeMinutes": <int>,
      "difficulty": "easy" | "medium" | "hard",
      "equipment": ["<item>", ...],
      "dietaryTags": ["<tag>", ...],
      "ingredients": [
        {
          "name": "<canonical food name, lowercase>",
          "displayName": "<user-facing label>",
          "quantityGrams": <number>,
          "displayQuantity": "<REQUIRED human unit string, see rule 8>",
          "calories": <number>,
          "proteinGrams": <number>,
          "carbsGrams": <number>,
          "fatGrams": <number>,
          "storageLocation": "fridge" | "freezer" | "pantry" | "cupboard",
          "defrostLeadTimeHours": <int>
        }
      ],
      "steps": [
        {
          "order": <int starting at 1>,
          "instruction": "<imperative sentence>",
          "durationMinutes": <int or null>
        }
      ],
      "macrosPerServing": {
        "calories": <number>,
        "protein": <number>,
        "carbs": <number>,
        "fat": <number>
      }
    }
    """

    /// Build the user prompt for a single planned meal.
    /// `exclusions` should be the user's `temporaryExclusions` from the intake
    /// wizard (e.g. ["dairy", "shellfish"]) — Haiku will avoid recipes that
    /// rely on them as primary ingredients.
    static func userPrompt(
        mealName: String,
        servings: Int,
        foods: [PlannedFood],
        skillLevel: String,
        exclusions: [String] = []
    ) -> String {
        let foodLines = foods.map { f in
            let kcal = Int(f.calories.rounded())
            let prot = Int(f.proteinG.rounded())
            let carbs = Int(f.carbsG.rounded())
            let fat = Int(f.fatG.rounded())
            return "- \(f.name): \(Int(f.quantityGrams))g (\(kcal) kcal, P\(prot) C\(carbs) F\(fat))"
        }.joined(separator: "\n")

        let totalCal = Int(foods.reduce(0.0) { $0 + $1.calories }.rounded())
        let totalProt = Int(foods.reduce(0.0) { $0 + $1.proteinG }.rounded())
        let totalCarbs = Int(foods.reduce(0.0) { $0 + $1.carbsG }.rounded())
        let totalFat = Int(foods.reduce(0.0) { $0 + $1.fatG }.rounded())

        // The caller (MealPlanGeneratorService.attachRecipes) merges
        // the user's permanent allergies + disliked foods with this
        // week's temporary exclusions before passing them in. From
        // Haiku's perspective they're all "do not use" — the weekly-
        // plan-level prompt has already separated strict-allergy from
        // soft-dislike at the meal-design step. Keep this line firm.
        let exclusionBlock = exclusions.isEmpty
            ? ""
            : "\nDo NOT use any of these ingredients: \(exclusions.joined(separator: ", ")). Substitute or restructure the recipe if needed."

        return """
        Meal: \(mealName)
        Servings: \(servings)
        User cooking skill: \(skillLevel)\(exclusionBlock)

        Target macros for ONE serving:
        - Calories: \(totalCal) kcal
        - Protein: \(totalProt) g
        - Carbs: \(totalCarbs) g
        - Fat: \(totalFat) g

        Foods to feature (quantities are TOTAL for the whole recipe, not per serving):
        \(foodLines)

        Return the JSON object only. Do not wrap it in markdown.
        """
    }
}
