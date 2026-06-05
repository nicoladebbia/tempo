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
        /// Foods + cuisines the user loves (prefer these). Preferences, not
        /// restrictions — emitted in a separate <taste_preferences> block.
        let favoriteFoods: [String]
        /// Foods the user is bored of (rotate away, don't overuse).
        let boredOfFoods: [String]

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
            favoriteFoods = profile.favoriteFoods
            boredOfFoods = profile.boredOfFoods
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
            dislikedFoods: [String] = [],
            favoriteFoods: [String] = [],
            boredOfFoods: [String] = []
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
            self.favoriteFoods = favoriteFoods
            self.boredOfFoods = boredOfFoods
        }

        /// `<taste_preferences>` prompt block — favorites + bored-of. Empty
        /// string when neither is set so callers interpolate unconditionally.
        var tastePreferencesBlock: String {
            guard !favoriteFoods.isEmpty || !boredOfFoods.isEmpty else { return "" }
            var lines: [String] = []
            if !favoriteFoods.isEmpty {
                let safe = favoriteFoods.map(MealPlanPrompts.sanitizeForPrompt).joined(separator: ", ")
                lines.append("LOVES (prefer these foods/cuisines, work them in often): \(safe)")
            }
            if !boredOfFoods.isEmpty {
                let safe = boredOfFoods.map(MealPlanPrompts.sanitizeForPrompt).joined(separator: ", ")
                lines.append("BORED OF (rotate AWAY from these — do not overuse; an occasional appearance is fine, but never the weekly default): \(safe)")
            }
            return """

            <taste_preferences>
            \(lines.joined(separator: "\n"))
            These are PREFERENCES, not hard rules — honor them within the macro
            targets and the variety requirement. Favorites should genuinely show
            up; bored-of foods should be visibly rare.
            </taste_preferences>
            """
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
                if !recipe.satietyCounts.isEmpty {
                    let satStr = recipe.satietyCounts
                        .sorted { $0.value > $1.value }
                        .map { "\($0.key) \($0.value)×" }
                        .joined(separator: ", ")
                    parts.append("fullness: \(satStr)")
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
        - 'fullness:' counts come from a post-meal satiety tag (too_much / didnt_finish / just_right / still_hungry). \
        The PRIMARY action is to SCALE DOWN: when a recipe/slot is 'too_much' or 'didnt_finish' ≥ 2× more than \
        'still_hungry', REDUCE that meal's portion (lower its calories within the day's target — shrink that slot \
        and let other meals hold the macro total). When 'still_hungry' dominates ≥ 2×, increase that slot's volume \
        (prefer adding high-volume, low-calorie-density foods — vegetables, broth, fruit — before fat/oil). \
        'just_right' is confirmation; keep that portion. Never push a day below its calorie/protein target to honor \
        a fullness signal — rebalance across meals instead.
        </user_feedback>
        """
    }

    /// Evidence-based functional-nutrition layer. This sits ON TOP of the
    /// macro targets (it never changes them) and tells the model WHICH whole
    /// foods to thread into the meals it is already building, and why — chosen
    /// for clear skin, lean recomposition, brain/focus, eyes, and athletic
    /// recovery. The guidance is graded by the strength of human evidence so
    /// the model leans hardest on the foods that actually move the needle and
    /// doesn't over-promise. Static (no per-user args yet) so it's cheap to
    /// test; user-specific gating (dairy, goals) is already carried by the
    /// dietary-restrictions + preferences blocks above.
    static func functionalNutritionBlock() -> String {
        """
        <functional_nutrition>
        Layer evidence-based functional foods INTO the meals you build. This is
        additive — it must NOT change the macro targets above; protein, carbs,
        and fat for each day stay exactly as prescribed. Within those macros,
        prefer the foods below for their nutrients. Lead with the STRONGEST
        evidence; treat the rest as fine-tuning.

        VARIETY IS MANDATORY — this is a real diet, not one dish repeated:
        - ROTATE proteins across the week. Do NOT make chicken (or any single
          protein) the base of most meals. Spread across: eggs, oily fish
          (salmon, sardines, mackerel), white fish, lean beef, turkey, chicken,
          tofu/tempeh, legumes, Greek-yogurt-free options. No protein should
          appear as the main of more than ~3 of the week's dinners.
        - ROTATE the dish family. "Chicken penne pomodoro" and "chicken
          spaghetti pomodoro" are the SAME meal — do not pass these off as
          variety. Vary the cuisine, the cooking method, and the carb base
          (rice, potato, quinoa, oats, bread, pasta) across days.
        - These functional foods MUST ACTUALLY APPEAR, not just be "allowed":
          every day includes at least one vegetable and at least one of the
          skin/brain/eye foods below (leafy greens, berries, oily fish, eggs,
          cooked tomato, etc.). A week with almost no vegetables or fruit is a
          FAILED plan regardless of macros.

        PRIORITY GOAL — clear, soft skin (and supporting gradual skin renewal):
        - LOW GLYCEMIC LOAD is the single biggest dietary lever for clear skin.
          Default every day to low-GI carbs (oats, whole grains, legumes,
          berries, sweet potato) over refined sugar, white bread, and sugary
          drinks. Spiking blood sugar drives breakouts. This also serves the
          lean-recomposition goal — keep it the default unless a training day
          genuinely needs fast carbs around the session.
        - NO ADDED SUGARS OR SWEETENERS in the meals: do NOT add honey, maple
          syrup, agave, table sugar, or sweetened/flavored yogurts. This applies
          even if such an item is in the pantry. Sweetness should come from whole
          fruit and berries. "Honey-sweetened oats" is exactly what to AVOID —
          use oats with berries or cinnamon instead.
        - MINIMIZE DAIRY. Dairy (milk, cheese, yogurt, whey in food) is the most
          common dietary acne aggravator. Hit protein from non-dairy sources
          where you can: eggs, fish, poultry, lean meat, tofu, legumes, edamame.
          Only use dairy when no clean non-dairy option fits the meal.
        - Skin-supporting nutrients to work in regularly: omega-3 (oily fish —
          salmon, sardines, mackerel — 2-3x/week) for lower inflammation;
          vitamin C (kiwi, bell pepper, citrus, berries) and adequate protein
          and zinc (shellfish, pumpkin seeds, legumes) as the raw materials skin
          uses to renew and stay firm and soft over time; green tea as a drink.
        - Frame this as nourishing skin to be clearer, softer, and to renew over
          time — never claim to cure or instantly fix any skin condition.

        BRAIN / FOCUS (student): eggs (choline) at breakfast; blueberries and
        other berries; natural NON-ALKALIZED cocoa (alkalized/"Dutch" cocoa
        loses the active flavanols) for processing speed; oily fish (DHA).

        EYES: lutein + zeaxanthin from leafy greens (spinach, kale) and egg
        yolk. These are fat-soluble — always pair them with a fat source in the
        same meal (olive oil, egg yolk, avocado) or they barely absorb.

        ATHLETIC RECOVERY (periodize by day type — do NOT load these every day):
        - On soccer / double days, include nitrate-rich foods (beetroot, leafy
          greens) and tart-cherry / pomegranate / berry options around the
          session to aid repeated-sprint performance and reduce soreness.
        - On hard strength (muscle-building) days, do NOT pile on extra
          antioxidant-dense recovery foods — a little training inflammation is
          part of the adaptation. Keep those for rest/soccer/competition days.

        ABSORPTION RULES (these change how foods are prepared/paired):
        - Fat-soluble nutrients (lutein, lycopene, beta-carotene, vitamins A/D/E/K)
          REQUIRE a fat source in the same meal — never a fat-free "green juice".
        - Lycopene (tomato) is far better absorbed COOKED with oil — program
          tomato as sauce / shakshuka / roasted, not raw, when it's there for
          skin/UV support.
        - Eggs: cook them (choline + lutein + their own fat), never raw.

        BLEND-OR-SOLID: when a food works well in a smoothie/juice the user can
        prep in a blender (berries, greens, cocoa, kefir/non-dairy yogurt), it
        may be programmed as a blend; foods that lose potency or need cooking
        (tomato, eggs, fish) must stay solid/cooked. Keep any blend low in added
        sugar and juice — whole fruit and berries over fruit juice.
        </functional_nutrition>
        """
    }

    /// Directive overriding the default 4-5 meal structure when the user has a
    /// specific meals-per-day preference. Empty when nil (AI uses the default).
    static func mealCountDirective(_ mealsPerDay: Int?) -> String {
        guard let n = mealsPerDay, (3 ... 6).contains(n) else { return "" }
        return "- MEAL COUNT (user preference, OVERRIDES the default below): give EXACTLY \(n) meals per day. Keep the same calorie distribution spirit, just across \(n) slots."
    }

    /// Directive capping recipe complexity to the user's cooking-time budget.
    /// Empty when neither is set (AI uses its under-20-min weekday default).
    static func cookTimeDirective(weekday: Int?, weekend: Int?) -> String {
        var parts: [String] = []
        if let weekday { parts.append("weekdays ≤ \(weekday) min") }
        if let weekend { parts.append("weekends ≤ \(weekend) min") }
        guard !parts.isEmpty else { return "" }
        return "- COOK-TIME BUDGET (user preference): keep total active cooking/prep time within \(parts.joined(separator: ", ")). On tight-time days favor one-pan, no-cook, or batch-reheat meals; save longer recipes for the higher-budget days. Never exceed the budget for a day."
    }

    /// `<equipment>` block — the cooking appliances the user owns. The AI must
    /// only program recipes makeable with these (no oven-roast if there's no
    /// oven). Empty string when the list is empty (AI assumes a basic
    /// stovetop+microwave kitchen) so callers interpolate unconditionally.
    static func equipmentBlock(_ availableAppliances: [String]) -> String {
        let cleaned = availableAppliances
            .map { MealPlanPrompts.sanitizeForPrompt($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        return """

        <equipment>
        The user's kitchen has ONLY these appliances: \(cleaned.joined(separator: ", ")).
        Program recipes makeable with this set — do NOT call for an appliance
        not listed (e.g. no "roast in the oven" without an oven; no "air-fry"
        without an air fryer). Prefer the appliance that makes a dish faster or
        hands-off (rice cooker → batch rice; blender → smoothie/sauce; slow
        cooker → set-and-forget). When a dish would normally need a missing
        appliance, adapt the method to what's available or choose a different dish.
        </equipment>
        """
    }

    /// The user's owned supplement shelf + the rules for scheduling them per
    /// day. Empty string when the shelf is empty (so callers interpolate
    /// unconditionally and no supplement output is requested). The model may
    /// ONLY schedule items listed here — never recommend buying anything.
    static func supplementShelfBlock(_ supplements: [Supplement]) -> String {
        let active = supplements.filter { !$0.isArchived }
        guard !active.isEmpty else { return "" }

        let lines = active.map { supp -> String in
            var parts = ["- \(sanitizeForPrompt(supp.name)) (\(supp.kind.displayName))"]
            if !supp.dosePerServing.isEmpty {
                parts.append("dose \(sanitizeForPrompt(supp.dosePerServing))")
            }
            if supp.proteinGramsPerServing > 0 {
                parts.append("\(Int(supp.proteinGramsPerServing))g protein/serving")
            }
            if supp.servingsRemaining > 0 {
                let low = supp.isRunningLow ? " — RUNNING LOW" : ""
                parts.append("\(Int(supp.servingsRemaining)) servings left\(low)")
            }
            parts.append(supp.takeDaily ? "daily by default" : "conditional")
            if let notes = supp.userNotes, !notes.isEmpty {
                parts.append("note: \(sanitizeForPrompt(notes))")
            }
            return parts.joined(separator: "; ")
        }.joined(separator: "\n")

        return """

        <supplement_shelf>
        The user OWNS these supplements. You may schedule a daily take/skip
        decision for each, but ONLY from this list — never suggest buying or
        adding anything new, never invent a supplement not listed here.

        \(lines)

        SCHEDULING RULES (emit a per-day "supplements" array — see schema):
        - "daily by default" items (e.g. creatine): take EVERY day. Skip only if
          a user note says otherwise.
        - Protein powder: take ONLY on days the whole-food meals fall short of
          the day's protein target — compute the gap from the meals you built.
          Because the user is minimizing dairy for skin, prefer hitting protein
          from food first and treat whey as the top-up, not the default.
        - Omega-3 / recovery supplements: take on most days for general support,
          but you may emphasize them around soccer / double / hard sessions.
        - Multivitamin / single vitamins: follow the user note; default to daily
          if none, but never exceed a single labeled serving.
        - Respect servings-left: do not schedule a supplement marked RUNNING LOW
          more than its remaining servings; you may note it's low.
        - TIMING: for every "take" decision, say WHEN to take it in plain words
          (with breakfast / after lunch / post-training / before bed), anchored
          to that day's meals and training. You are the nutritionist — the user
          should not have to decide when; you tell them. Examples: creatine →
          any consistent time ("with breakfast"); whey → the meal where protein
          fell short ("after lunch — protein was low today"); omega-3 → with a
          meal that has fat ("with dinner"). Leave timing empty on a skip.
        - Give a SHORT reason per decision ("protein target met by food → skip",
          "creatine daily", "post-match recovery"). Never give medical dosing
          beyond the labeled serving; never tell the user to buy more.
        </supplement_shelf>
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

        These are the user's REAL eating times, anchored to when they actually \
        wake. You MUST set each meal's "scheduledTime" to the time given here \
        for that mealNumber — use it verbatim for EVERY day of the week. Do NOT \
        substitute generic times and do NOT average toward 07:30/12:30. \
        mealNumber 4 ("Snack") is an AFTERNOON snack and mealNumber 3 \
        ("Dinner") is the evening meal, so chronologically the day runs \
        Breakfast < Lunch < Snack(#4) < Dinner(#3). Keep that clock order even \
        though the Snack's mealNumber is higher.
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

        These are the ingredients the user ALREADY HAS. Use them as a TIEBREAKER, \
        not a constraint: when two equally good, varied meal options exist, prefer \
        the one that uses on-hand stock. But VARIETY AND NUTRITION COME FIRST — \
        never repeat the same protein or dish family across the week just to drain \
        the pantry. It is BETTER to buy a few new ingredients for a varied, \
        functional-food-rich week than to cook chicken-and-pasta five times \
        because that's what's in stock. The grocery list SHOULD have real items \
        on it (proteins, vegetables, fruit, the functional foods) — a near-empty \
        grocery list means you over-relied on the pantry and under-delivered \
        variety. Respect quantities when you DO use a pantry item: do not plan to \
        use more than is listed (e.g. 9 eggs on hand → don't schedule 12). Ignore \
        any item that conflicts with the user's dietary restrictions or the \
        clear-skin goals in <functional_nutrition> (e.g. don't build meals around \
        a pantry sweetener).
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
            /// Counts of post-meal satiety chips. Keys are
            /// `MealSatiety.rawValue`. Surfaces "this slot is too_much 4/5
            /// times" so the planner can scale the portion DOWN.
            let satietyCounts: [String: Int]
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
        pantryStock: [String] = [],
        supplements: [Supplement] = [],
        mealsPerDay: Int? = nil,
        cookTimeWeekdayMins: Int? = nil,
        cookTimeWeekendMins: Int? = nil,
        equipment: [String] = []
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
        - NEVER recommend supplements, brands, or products the user does not own. (You MAY schedule items listed in a <supplement_shelf> block when one is provided.)
        - NEVER give medical or clinical nutrition advice, diagnose, or promise to cure/fix a skin or health condition. Choosing whole foods for their nutrients (e.g. eggs for choline, oily fish for omega-3) is nutrition, not medical advice — that is allowed.
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
        \(restrictions.tastePreferencesBlock)
        \(weeklyIntakeBlock(intake))
        \(observedTimesBlock(observedMealTimes))
        \(pantryStockBlock(pantryStock))
        \(expiringSoonBlock(expiringSoon))
        \(feedbackBlock(feedbackDigest))
        \(functionalNutritionBlock())
        \(equipmentBlock(equipment))
        \(supplementShelfBlock(supplements))

        <meal_structure>
        \(mealCountDirective(mealsPerDay))
        \(cookTimeDirective(weekday: cookTimeWeekdayMins, weekend: cookTimeWeekendMins))
        - 4-5 meals per day: Breakfast, Lunch, Dinner, and 1-2 Snacks.
        - Breakfast: ~25% of daily calories
        - Lunch: ~30% of daily calories
        - Dinner: ~30% of daily calories
        - Snacks: ~15% of daily calories total. On training days (strength / soccer / double), prefer TWO snacks: one post-training (protein + carbs to refuel) and one optional lighter snack. On rest days a single snack is fine.
        - Front-load protein: breakfast and lunch should each have 30%+ of daily protein.
        - Snack quality: snacks must earn their slot nutritionally — pair a protein with fruit or a functional food (see <functional_nutrition>), not empty calories.
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
                            "scheduledTime": "HH:mm (within this meal's window; keep the day in chronological order — see the scheduledTime rules below)",
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
                    ],
                    "supplements": [
                        {
                            "name": "string (MUST match a name from <supplement_shelf>)",
                            "take": true,
                            "timing": "WHEN to take it when take=true: 'with breakfast' | 'after lunch' | 'post-training' | 'before bed' etc. Empty string when take=false.",
                            "reason": "short reason, e.g. 'creatine daily' or 'protein met by food, skip'"
                        }
                    ]
                }
            ]
        }

        Rules:
        - dayIndex 0 = Monday, 6 = Sunday.
        - dayType must be one of: strength, cardio, soccer, double, rest.
        - dayType assignment: when an <actual_training_schedule> block is provided above, you MUST use the mapping it specifies for each day. Only when no schedule is given fall back to a typical 3-4 training / 1-2 rest week with varied types.
        - mealNumber: 1 = Breakfast, 2 = Lunch, 3 = Dinner, 4 = Snack (afternoon). An OPTIONAL second snack is mealNumber 5 — use it mainly on training days (post-training refuel or an evening snack). Most days have 4 meals; training days may have 5.
        - scheduledTime format: "HH:mm" (24h). Place each meal at a sensible time \
        WITHIN its window, then verify the whole day is in correct order. \
        WINDOWS (pick the exact time inside these based on the food + training): \
          • Breakfast (mealNumber 1): 06:30–10:30 (anytime in the morning). \
          • Lunch (mealNumber 2): 12:30–14:00. \
          • Dinner (mealNumber 3): 19:30–21:00 (never earlier than 19:00; dinner \
            is an evening meal — do NOT move it to the afternoon to fit a snack). \
          • Afternoon snack (mealNumber 4): between lunch and dinner, ~16:00–17:30. \
          • Optional 2nd snack (mealNumber 5): EITHER post-training (~45–60 min \
            after the session) OR a light evening snack AFTER dinner (~21:30). A \
            "dinner snack" / evening snack is ALWAYS after dinner, never before. \
        - HARD ORDERING RULE: the meals of a day, sorted by scheduledTime, MUST \
        read in this logical order — Breakfast < Lunch < (afternoon Snack #4) < \
        Dinner < (evening Snack #5 if any). A post-training snack #5 may instead \
        sit right after the training session even if that's before dinner — but a \
        snack labeled or intended as an evening/after-dinner snack must come AFTER \
        dinner. NEVER schedule a snack after dinner while also putting dinner in \
        the afternoon. If two meals would collide, space them ≥90 min apart. \
        - When an <observed_meal_times> block is provided, treat its times as the \
        user's PREFERRED time for that meal — use it when it falls inside the \
        window above and keeps the day ordered; otherwise nudge to the nearest \
        time that satisfies the window + ordering rules.
        - Each food's macros must be realistic for the stated quantity. Reference standard per-100g values.
        - Each meal's total macros (sum of foods) must match the meal's share of the day's target within 5%.
        - Each day's total macros (sum of meals) must match the day type's target within 3%.
        - Use varied foods across the week. No identical meals on consecutive days.
        - Include 2-4 foods per meal. Keep it simple and student-practical.
        - All quantities in raw/uncooked grams unless the food is consumed raw (fruits, bread, etc.).
        - "supplements": include this array per day ONLY when a \
        <supplement_shelf> block is provided above. Each entry's "name" MUST \
        exactly match a shelf item. Follow the shelf's SCHEDULING RULES. When \
        NO shelf is provided, OMIT the "supplements" field entirely (do not \
        emit an empty array, do not invent supplements).
        """

        return (system: system, user: user)
    }
}
