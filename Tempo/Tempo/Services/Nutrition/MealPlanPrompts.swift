//
// MealPlanPrompts.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation

// MARK: - Meal Plan Prompts

/// Static prompt templates for Claude Sonnet meal plan generation.
/// Per AI_INTELLIGENCE_ENGINE.md Section 3 -- all prompts use XML tags for structured context,
/// reference exact numbers, and include safety rails.
/// Voice follows UX_COPY_BIBLE.md Section 1.1: Drill Sergeant default.
enum MealPlanPrompts {
    /// Strip characters that could close a surrounding prompt block
    /// (newlines, angle brackets, quotes) so user-supplied dietary text
    /// can't inject instructions into the generation prompt.
    static func sanitizeForPrompt(_ input: String) -> String {
        var s = input
        for ch in ["\n", "\r", "<", ">", "\"", "`"] {
            s = s.replacingOccurrences(of: ch, with: " ")
        }
        return String(s.prefix(120))
    }

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
        let avoidAddedSugars: Bool
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
            avoidAddedSugars = profile.avoidAddedSugars
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
            avoidAddedSugars: Bool = false,
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
            self.avoidAddedSugars = avoidAddedSugars
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
            if avoidAddedSugars {
                lines.append(
                    "- NO ADDED SUGARS (still satisfy a sweet tooth): avoid added, refined, "
                        + "and processed sugars (table sugar, syrups, honey added as sweetener, "
                        + "sweetened cereals/yogurts, pastries, sugary drinks). The user DOES want "
                        + "sweet-tasting options — satisfy cravings with NATURALLY sweet whole foods "
                        + "(fresh fruit, berries, dates in moderation), unsweetened dairy, and "
                        + "naturally-sweet breakfasts (e.g. oats with banana/berries, Greek yogurt "
                        + "with fruit, protein smoothies with no added sugar). Do NOT make the plan "
                        + "bland or artificially sugar-free; favor whole-food sweetness. Skin/acne-conscious."
                )
            }
            if !allergies.isEmpty {
                // Strip newlines and angle brackets so a wizard paste can't
                // close the surrounding XML-style block in the larger prompt.
                let safe = allergies.map(MealPlanPrompts.sanitizeForPrompt).joined(separator: ", ")
                lines.append("- ALLERGIES (STRICT EXCLUSION): \(safe)")
            }
            if !dislikedFoods.isEmpty {
                let safe = dislikedFoods.map(MealPlanPrompts.sanitizeForPrompt).joined(separator: ", ")
                lines.append("- DISLIKED FOODS (avoid): \(safe)")
            }
            if lines.isEmpty {
                return "None."
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Weekly Intake Block

    /// Format a `MealPlanIntake` as a prompt block. Returns an empty string when intake is nil
    /// so callers can interpolate unconditionally.
    static func weeklyIntakeBlock(_ intake: MealPlanIntake?) -> String {
        guard let intake else {
            return ""
        }

        var lines: [String] = []
        lines.append("- Cookable days this week: \(intake.cookableDaysThisWeek). Concentrate prep there.")
        lines.append("- Leftover tolerance: \(intake.leftoverTolerance.promptDescriptor)")
        lines.append("- Eating window: \(intake.eatingWindow.formattedForPrompt)")
        if let grocery = intake.groceryIntent {
            lines.append("- Grocery context: \(grocery.formattedForPrompt)")
        }
        if intake.recoveryAdjusted {
            lines.append("- Adjust calorie distribution to skew toward training-day fuel and lighter rest-day intake. User opted in.")
        }
        if !intake.temporaryExclusions.isEmpty {
            lines
                .append(
                    "- Off-limits this week (temporary, not allergies): \(intake.temporaryExclusions.joined(separator: ", ")). Do not include."
                )
        }

        // Inject the user's actual weekly training schedule when available.
        // The day-type assignment rule in weeklyPlanPrompt was previously a
        // generic "match a typical training week", so the model returned
        // Wed=strength / Thu=cardio that bore no relation to the user's
        // Mon=upper, Tue=lower, Wed=football reality. With this block the
        // model is bound to the real schedule.
        var scheduleBlock = ""
        if let schedule = intake.trainingSchedule {
            scheduleBlock = """

            <actual_training_schedule>
            \(schedule.formattedForPrompt)
            </actual_training_schedule>

            DAY-TYPE MAPPING REQUIREMENT: For each calendar day above, map the
            user's training kind to a calorie day type as follows:
            - Football → soccer
            - Lower / Legs → strength
            - Upper / Push / Pull / Full Body / Chest / Back / Shoulders / Arms → strength
            - Mobility → rest
            - Conditioning / Run / Sprint → cardio
            - Rest → rest
            Two trainings in one day (e.g. lifting + football) → double.
            Do NOT improvise day types — use the schedule above.
            """
        }

        return """

        <weekly_intake>
        \(lines.joined(separator: "\n"))
        </weekly_intake>\(scheduleBlock)
        """
    }

    /// Format the rolling 4-week meal feedback digest as a prompt block.
    /// Empty when no rows are present. Instructs the model to use the
    /// signal nuanced-ly — drop recipes the user clearly disliked, apply
    /// specific suggested changes, respect portion preferences, but NOT
    /// over-react to a single mention.
    static func feedbackBlock(_ digest: FeedbackDigest?) -> String {
        guard let digest, !digest.recipes.isEmpty || !digest.ingredients.isEmpty else {
            return ""
        }

        var sections: [String] = []

        if !digest.recipes.isEmpty {
            let lines = digest.recipes.map { recipe -> String in
                var parts: [String] = ["• \(recipe.recipeName) (\(recipe.mentionCount)×)"]
                if let avg = recipe.averageRating {
                    parts.append(String(format: "avg %.1f★", avg))
                }
                if !recipe.feelCounts.isEmpty {
                    let feelStr = recipe.feelCounts
                        .sorted { $0.value > $1.value }
                        .map { "\($0.key) \($0.value)×" }
                        .joined(separator: ", ")
                    parts.append("feel: \(feelStr)")
                }
                if !recipe.notes.isEmpty {
                    parts.append("notes: " + recipe.notes.joined(separator: " / "))
                }
                if !recipe.portionNotes.isEmpty {
                    parts.append("portion: " + recipe.portionNotes.joined(separator: " / "))
                }
                if !recipe.suggestedChanges.isEmpty {
                    parts.append("change: " + recipe.suggestedChanges.joined(separator: " / "))
                }
                if !recipe.substituteNotes.isEmpty {
                    parts.append("swapped \(recipe.substituteNotes.count)× for: " + recipe.substituteNotes.joined(separator: " / "))
                }
                return parts.joined(separator: " | ")
            }
            sections.append("Recipes (last 4 weeks):\n" + lines.joined(separator: "\n"))
        }

        if !digest.ingredients.isEmpty {
            let lines = digest.ingredients.map { ing -> String in
                var parts: [String] = ["• \(ing.ingredientName) (👍 \(ing.likedCount), 👎 \(ing.dislikedCount))"]
                if !ing.perRecipeNotes.isEmpty {
                    parts.append("ctx: " + ing.perRecipeNotes.joined(separator: " / "))
                }
                return parts.joined(separator: " | ")
            }
            sections.append("Ingredient sentiment:\n" + lines.joined(separator: "\n"))
        }

        return """

        <user_feedback>
        \(sections.joined(separator: "\n\n"))

        Apply this signal nuanced-ly:
        - Drop recipes the user clearly disliked (avg rating ≤ 2 or explicit negative notes).
        - APPLY specific suggested changes when they generate a similar dish ("add lemon", "100g not 300g").
        - For an ingredient, distinguish dish-context: "rice was mushy in dish X" doesn't ban rice — try a different prep.
        - Do NOT over-react to a single mention; require ≥ 2 mentions before treating it as a hard preference.
        - 'feel:' counts come from a post-meal one-word tag (light / clean / energising / heavy / sluggish). \
        When a recipe is 'sluggish' ≥ 2× more than 'energising', DROP it on training days (strength/soccer/double) \
        and keep it only for rest days. When 'energising' dominates, prefer it for training-day breakfasts and lunches.
        - 'swapped Nx for:' means the user marked the planned meal eaten but logged a DIFFERENT meal instead. \
        ≥ 2 swaps for the same recipe = DROP it from the new plan entirely; the user is voting with their behavior. \
        Read the swap descriptions to learn what dishes they prefer in that slot and surface similar options.
        </user_feedback>
        """
    }

    /// Format the user's rolling 14-day actual eat-times by mealNumber as a
    /// prompt block. Empty when no observations exist so callers can
    /// interpolate unconditionally. Tells the model to anchor scheduledTime
    /// to these observations rather than the schema defaults.
    static func observedTimesBlock(_ observed: ObservedMealTimes?) -> String {
        guard let observed, !observed.isEmpty else {
            return ""
        }
        let labelFor: (Int) -> String = { number in
            switch number {
            case 1: "Breakfast"
            case 2: "Lunch"
            case 3: "Dinner"
            case 4: "Snack"
            default: "Meal \(number)"
            }
        }
        let lines = observed
            .sorted { $0.key < $1.key }
            .map { "- \(labelFor($0.key)) (mealNumber \($0.key)): user actually eats around \($0.value)." }
            .joined(separator: "\n")

        return """

        <observed_meal_times>
        \(lines)

        Use these as the scheduledTime defaults for the matching mealNumber. \
        Override the 07:30 / 12:30 / 19:30 / 16:00 hints when an observation exists.
        </observed_meal_times>
        """
    }

    /// Optional expiring-pantry block. Empty when no items are within the
    /// urgency window (≤7 days). Encourages the planner to consume soon-to-expire
    /// ingredients before they spoil (FIFO).
    ///
    /// `expiringSoon` is a sorted list of (canonical name, daysToExpire), already
    /// filtered to items with daysToExpire in 0...7.
    static func expiringSoonBlock(_ expiringSoon: [(name: String, days: Int)]) -> String {
        guard !expiringSoon.isEmpty else {
            return ""
        }
        let lines = expiringSoon
            .map { entry -> String in
                let timing: String
                switch entry.days {
                case 0: timing = "expires today"
                case 1: timing = "expires tomorrow"
                default: timing = "expires in \(entry.days) days"
                }
                return "- \(entry.name) (\(timing))"
            }
            .joined(separator: "\n")

        return """

        <expiring_pantry_items>
        \(lines)

        When designing meals for this week, prefer recipes that consume the items above before \
        they expire. Treat items expiring today or tomorrow as hard priority for the first 1-2 days \
        of the plan. Do not include any of these items in meals scheduled for days after their \
        expiry. If a listed item conflicts with the user's dietary restrictions, ignore it.
        </expiring_pantry_items>
        """
    }

    /// Full pantry stock the user already owns. Distinct from
    /// `expiringSoonBlock` (urgency/FIFO) — this is the "build meals around
    /// what's on hand" signal so the grocery list is genuinely just the gap.
    /// `stock` is pre-formatted "name — qty unit [location]" lines.
    static func pantryStockBlock(_ stock: [String]) -> String {
        guard !stock.isEmpty else {
            return ""
        }
        let lines = stock.map { "- \($0)" }.joined(separator: "\n")
        return """

        <pantry_on_hand>
        \(lines)

        These are the ingredients the user ALREADY HAS. Build the week's meals \
        primarily around this stock — prefer recipes that consume what's on hand \
        before specifying anything new to buy. Respect the quantities: do not \
        plan to use more of an item than is listed (e.g. if 9 eggs are on hand, \
        do not schedule 12 across the week — scale portions or spread them, using \
        whole units for countable foods). Only introduce a new ingredient when a \
        balanced meal genuinely needs something not in stock; the grocery list is \
        meant to cover the GAP, not re-buy what's here. Ignore any item that \
        conflicts with the user's dietary restrictions.
        </pantry_on_hand>
        """
    }

    // MARK: - Weekly Plan Prompt

    /// Generate a full weekly meal plan with exact macros per day type.
    /// Model: Sonnet | Temp: 0.3 | Max tokens: 4096 | Timeout: 30s
    /// Rolling average actual eat-times by `mealNumber` (1=Breakfast … 4=Snack).
    /// Computed by `MealPlanGeneratorService` from the last 14 days of
    /// `PlannedMeal.actualEatenAt`. When present, the prompt anchors each
    /// meal to the user's real rhythm rather than the default 07:30/12:30/etc.
    typealias ObservedMealTimes = [Int: String]

    /// Aggregated feedback signal pulled from the last 4 weeks of
    /// `MealFeedback`. The plan generator uses this to bias the new plan
    /// toward liked recipes, drop disliked ones, apply suggested changes,
    /// and respect portion preferences.
    struct FeedbackDigest: Sendable {
        struct RecipeSignal: Sendable {
            let recipeName: String
            /// Average rating across all feedback rows that gave a rating.
            /// Nil when no row provided a rating.
            let averageRating: Double?
            let mentionCount: Int
            /// Verbatim freeform notes the model should read directly.
            let notes: [String]
            let portionNotes: [String]
            let suggestedChanges: [String]
            /// Counts of post-meal feel chips for this recipe. Keys are
            /// `MealFeel.rawValue`. Surfaces patterns like "this dish
            /// makes them sluggish 4/5 times" to the planner.
            let feelCounts: [String: Int]
            /// Free-text descriptions of what the user ate INSTEAD of the
            /// planned recipe. Each entry is a "I swapped this dish" event.
            /// Heavy signal — repeated substitution means the dish should
            /// be dropped, period.
            let substituteNotes: [String]
        }
        struct IngredientSignal: Sendable {
            let ingredientName: String
            /// Per-recipe sentiment so the model can see "user dislikes rice
            /// in stir-fries but is fine with it in burrito bowls."
            let perRecipeNotes: [String]
            let likedCount: Int
            let dislikedCount: Int
        }
        let recipes: [RecipeSignal]
        let ingredients: [IngredientSignal]
    }

    static func weeklyPlanPrompt(
        targets: [DayType: MacroTargets],
        restrictions: DietaryRestrictions,
        preferences: String,
        intake: MealPlanIntake? = nil,
        observedMealTimes: ObservedMealTimes? = nil,
        feedbackDigest: FeedbackDigest? = nil,
        expiringSoon: [(name: String, days: Int)] = [],
        pantryStock: [String] = []
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
        \(weeklyIntakeBlock(intake))
        \(observedTimesBlock(observedMealTimes))
        \(pantryStockBlock(pantryStock))
        \(expiringSoonBlock(expiringSoon))
        \(feedbackBlock(feedbackDigest))

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
        - dayType assignment: when an <actual_training_schedule> block is provided above, you MUST use the mapping it specifies for each day. Only when no schedule is given fall back to a typical 3-4 training / 1-2 rest week with varied types.
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
