//
// MealPlanGeneratorService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - MealPlanGeneratorService

/// Generates weekly meal plans via Claude Sonnet, validates macros against FoodMacroDatabase,
/// and persists plans + meals to SwiftData.
///
/// Per AI_INTELLIGENCE_ENGINE.md + INTELLIGENCE_REMEDIATION_PLAN.md §3:
/// - Sonnet for deep analysis (meal plan generation)
/// - All Claude calls proxied through the Vapor backend (no embedded API key)
/// - JSON extraction fallback for parsing
@Observable
final class MealPlanGeneratorService: @unchecked Sendable {
    // MARK: - State

    enum GenerationState {
        case idle
        case calculating
        case generating
        case validating
        case saving
        case attachingRecipes
        case failed(String)
        case complete

        /// User-facing copy for the long-running spinner. Drill-sergeant tone.
        var statusLabel: String {
            switch self {
            case .idle: ""
            case .calculating: "Crunching your numbers…"
            case .generating: "Drafting the week…"
            case .validating: "Double-checking macros…"
            case .saving: "Locking it in…"
            case .attachingRecipes: "Writing recipes for every meal…"
            case let .failed(msg): msg
            case .complete: "Done."
            }
        }
    }

    private(set) var state: GenerationState = .idle

    // MARK: - Dependencies

    /// All Claude calls are now proxied through the Tempo backend so the
    /// Anthropic API key never ships in the app binary.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §3 + ADR-018.
    private let apiClient: APIClient
    private let logger = Logger.nutrition

    // MARK: - Retry Configuration

    private let maxRetries = 2
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Init

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Generate Weekly Plan

    /// Generate a full weekly meal plan from the user's dietary profile and optional Whoop TDEE.
    ///
    /// 1. Calculate TDEE and per-day-type macro targets
    /// 2. Build dietary restrictions from profile
    /// 3. Call Claude Sonnet with MealPlanPrompts
    /// 4. Parse JSON response into PlannedMeal objects
    /// 5. Validate macros (cross-check with FoodMacroDatabase, scale if >5% off)
    /// 6. Create WeeklyMealPlan + PlannedMeal records, insert into modelContext
    /// 7. Return the plan
    @MainActor
    func generateWeeklyPlan(
        profile: DietaryProfile,
        whoopTDEE: Double?,
        wakeMinutesOverride: Int? = nil,
        modelContext: ModelContext,
        intake callerIntake: MealPlanIntake? = nil,
        onStatus: ((GenerationState) -> Void)? = nil
    ) async throws -> WeeklyMealPlan {
        // Onboarding eating preferences (UserDailyPlanProfile) — the eating
        // window until the wizard / AI Meals settings saves one, plus
        // breakfastSkipped + postWorkoutMandatory always. Read here (not in
        // the callers) so every generate path honors them.
        let onboardingSettings = Self.fetchUserSettings(modelContext: modelContext)
        let dailyPlanProfile = UserDailyPlanProfile.current(in: modelContext)
        let intake: MealPlanIntake? = if let callerIntake {
            callerIntake.applyingOnboarding(dailyPlanProfile, settings: onboardingSettings)
        } else if dailyPlanProfile != nil {
            MealPlanIntake.seeded(settings: onboardingSettings, dailyPlan: dailyPlanProfile)
        } else {
            nil
        }
        if let intake {
            let window = "\(intake.eatingWindow.firstMealHour)-\(intake.eatingWindow.lastMealHour)"
            let skip = intake.breakfastSkipped
            let postWorkout = intake.postWorkoutMandatory
            logger.info(
                "[Diag.Plan] eating pattern: window=\(window, privacy: .public) breakfastSkipped=\(skip) postWorkoutMandatory=\(postWorkout)"
            )
        }
        // Resolve BEFORE persistPlan replaces the old plan — the one-time
        // migration keys off "a plan already exists".
        let clearSkinFocus = ClearSkinFocusSetting.resolve(modelContext: modelContext)

        let setState: (GenerationState) -> Void = { newState in
            self.state = newState
            onStatus?(newState)
        }
        setState(.calculating)

        // Step 1: Calculate TDEE and macro targets per day type
        let tdeeResult = TDEECalculator.calculate(
            weightKg: profile.currentWeightKg,
            heightCm: profile.heightCm,
            age: profile.age,
            biologicalSex: profile.biologicalSex,
            bodyFatPercent: profile.bodyFatPercent,
            trainingFrequency: profile.trainingFrequency,
            whoopAverageTDEE: whoopTDEE,
            goal: profile.primaryGoal,
            goalWeightKg: profile.goalWeightKg,
            weeklyRateKg: profile.weeklyRateKg
        )

        logger.info("TDEE calculated: \(Int(tdeeResult.tdee)) kcal, adjusted: \(tdeeResult.adjustedCalories) kcal")

        // Step 2: Build dietary restrictions from profile
        let restrictions = MealPlanPrompts.DietaryRestrictions(from: profile)

        // Step 3: Build prompt and call Claude Sonnet
        setState(.generating)

        let preferences = buildPreferences(from: profile)

        // Pull the user's rolling 14-day actual eat-times per mealNumber so
        // the AI anchors the new plan to their real rhythm rather than the
        // 07:30/12:30/19:30/16:00 schema defaults.
        let observed = observedMealTimes(
            modelContext: modelContext,
            wakeMinutesOverride: wakeMinutesOverride,
            eatingWindow: intake?.eatingWindow,
            breakfastSkipped: intake?.breakfastSkipped ?? false
        )
        let feedback = recentFeedbackDigest(modelContext: modelContext)
        let expiringSoon = expiringPantryItems(modelContext: modelContext)
        if !expiringSoon.isEmpty {
            logger.info("Expiring pantry items injected into plan prompt: \(expiringSoon.count)")
        }
        let stock = pantryStock(modelContext: modelContext)
        if !stock.isEmpty {
            logger.info("Pantry stock injected into plan prompt: \(stock.count) items")
        }

        let supplements = supplementShelf(modelContext: modelContext)
        if !supplements.isEmpty {
            logger.info("Supplement shelf injected into plan prompt: \(supplements.count) items")
        }

        // INPUT training schedule fed to the AI (Mon=1 … Sun=7). Compared
        // against the persisted day-types in [Diag.Plan], this tells us whether
        // a wrong day-type (e.g. Saturday showing REST when the user lifts) is
        // bad INPUT (this schedule) or a downstream keying bug.
        if let sched = intake?.trainingSchedule {
            let dump = sched.byWeekday.sorted { $0.key < $1.key }
                .map { "wd\($0.key)=\($0.value)" }.joined(separator: ", ")
            logger.info("[Diag.Plan] INPUT trainingSchedule (Mon=1..Sun=7): \(dump)")
        } else {
            logger.info("[Diag.Plan] INPUT trainingSchedule: nil (AI will guess day types)")
        }

        // Meals-per-day + cook-time budget prefs (persisted on UserSettings,
        // set from the AI Meals settings page). nil → AI uses its defaults.
        let mealsPrefSettings = Self.fetchUserSettings(modelContext: modelContext)
        let mealsPerDay = mealsPrefSettings?.mealsPerDayPreference
        let cookWeekday = mealsPrefSettings?.cookTimeWeekdayMins
        let cookWeekend = mealsPrefSettings?.cookTimeWeekendMins
        if mealsPerDay != nil || cookWeekday != nil || cookWeekend != nil {
            logger.info("[Diag.Plan] meal prefs: mealsPerDay=\(mealsPerDay ?? 0) cookWeekday=\(cookWeekday ?? 0) cookWeekend=\(cookWeekend ?? 0)")
        }

        // Available kitchen appliances (display names) so the AI only programs
        // recipes the user can actually make. Empty → the prompt block omits the
        // constraint and the AI assumes a basic stovetop+microwave kitchen.
        let equipment = Self.availableEquipment(modelContext: modelContext)
        if !equipment.isEmpty {
            logger.info("[Diag.Plan] equipment: \(equipment.joined(separator: ", "))")
        }

        let (systemPrompt, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: tdeeResult.dayTypeTargets,
            restrictions: restrictions,
            preferences: preferences,
            intake: intake,
            observedMealTimes: observed,
            feedbackDigest: feedback,
            expiringSoon: expiringSoon,
            pantryStock: stock,
            supplements: supplements,
            mealsPerDay: mealsPerDay,
            cookTimeWeekdayMins: cookWeekday,
            cookTimeWeekendMins: cookWeekend,
            equipment: equipment,
            clearSkinFocus: clearSkinFocus
        )

        let response = try await sendWithRetry(
            system: systemPrompt,
            prompt: userPrompt,
            feature: "meal_plan_generation"
        )

        // Step 4: Parse JSON response
        setState(.validating)

        var parsedPlan = try parseWeeklyPlanJSON(response)
        if let intake {
            parsedPlan = enforceEatingPattern(parsedPlan, intake: intake)
        }

        // Step 5: Validate and scale macros
        let validatedPlan = validateAndScaleMeals(
            parsedPlan,
            targets: tdeeResult.dayTypeTargets
        )

        // Step 6: Persist to SwiftData
        setState(.saving)

        let weeklyPlan = try persistPlan(
            validatedPlan,
            targets: tdeeResult.dayTypeTargets,
            modelContext: modelContext
        )

        // Step 7: Generate per-meal recipes via Haiku (fan-out, attach in main actor)
        setState(.attachingRecipes)
        await attachRecipes(
            to: weeklyPlan,
            profile: profile,
            intake: intake,
            modelContext: modelContext
        )

        setState(.complete)
        logger.info("Weekly meal plan generated: \(weeklyPlan.id) with \(weeklyPlan.meals?.count ?? 0) meals")
        logPlanDiagnostics(weeklyPlan)

        return weeklyPlan
    }

    /// Dump a structured, human-readable summary of the generated plan so a
    /// regenerate can be verified from the console alone — without screenshots.
    /// Covers the four things that keep going wrong: meal TIMING + ordering,
    /// day-TYPE labels, supplement decisions, and food VARIETY. All under the
    /// `[Diag.Plan]` tag for easy filtering.
    /// Parse "HH:mm" → minutes-from-midnight for ordering checks. Nil on a
    /// malformed string.
    private static func minutesOfDay(from hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else {
            return nil
        }
        return h * 60 + m
    }

    private func logPlanDiagnostics(_ plan: WeeklyMealPlan) {
        let cal = Calendar.current
        let meals = plan.meals ?? []
        let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        logger.info("[Diag.Plan] ===== Plan \(plan.id) =====")

        // RAW day-type dictionary exactly as stored (key → value), so we can
        // see the TRUE keying convention vs how each surface reads it. The
        // generator WRITES keys as dayIndex+1 (Monday=1 … Sunday=7). If the
        // displayed day-types are wrong, comparing this raw dump to the screen
        // tells us whether it's a read-convention bug or genuinely-wrong input.
        let rawDict = plan.dayTypeAssignments.sorted { $0.key < $1.key }
            .map { "key\($0.key)=\($0.value)" }.joined(separator: ", ")
        logger.info("[Diag.Plan] RAW dayTypeAssignments: \(rawDict)")

        // Per-day: day-type + meals in chronological order with time/name/kcal.
        // Group by dayDate so we read each day as the user will see it.
        let byDay = Dictionary(grouping: meals) { cal.startOfDay(for: $0.dayDate) }
        var orderViolations = 0
        for dayStart in byDay.keys.sorted() {
            let dayMeals = (byDay[dayStart] ?? []).sorted {
                (Self.minutesOfDay(from: $0.scheduledTime) ?? 0) < (Self.minutesOfDay(from: $1.scheduledTime) ?? 0)
            }
            let weekdayIdx = (cal.component(.weekday, from: dayStart) + 5) % 7 // Mon=0
            let label = weekdayIdx < weekdayNames.count ? weekdayNames[weekdayIdx] : "?"
            // dict is keyed Mon=1 … Sun=7, so the key is weekdayIdx + 1.
            let dayType = plan.dayTypeAssignments[weekdayIdx + 1] ?? "?"
            let line = dayMeals.map { m in
                "\(m.scheduledTime) \(m.mealName)(\(Int(m.totalCalories))kcal)"
            }.joined(separator: " → ")
            logger.info("[Diag.Plan] \(label) [\(dayType)]: \(line)")

            // Ordering sanity: dinner should not precede an afternoon snack, and
            // times must be non-decreasing (the sort guarantees the latter, so
            // we flag a Dinner that sits before a Snack by mealNumber instead).
            if let dinner = dayMeals.first(where: { $0.mealName.lowercased().contains("dinner") }),
               let dinnerMin = Self.minutesOfDay(from: dinner.scheduledTime),
               dinnerMin < 19 * 60 {
                logger.warning("[Diag.Plan] ⚠️ \(label): dinner at \(dinner.scheduledTime) is before 19:00")
                orderViolations += 1
            }
        }

        // Variety audit: distinct foods across the week + how concentrated the
        // most-repeated food is (the chicken-pasta-monotony detector).
        let allFoodNames = meals.flatMap { $0.foods.map { $0.name.lowercased() } }
        let distinct = Set(allFoodNames)
        var counts: [String: Int] = [:]
        for name in allFoodNames { counts[name, default: 0] += 1 }
        let top = counts.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
        logger.info("[Diag.Plan] Variety: \(distinct.count) distinct foods across \(allFoodNames.count) slots. Most repeated: \(top)")

        // Supplement decisions actually persisted.
        let suppDays = plan.supplementDecisions.count
        if suppDays > 0 {
            let sample = plan.supplementDecisions.sorted { $0.key < $1.key }.first
            let sampleStr = (sample?.value ?? []).map {
                "\($0.name):\($0.take ? "take@\($0.timing ?? "?")" : "skip")"
            }.joined(separator: ", ")
            logger.info("[Diag.Plan] Supplements: decisions on \(suppDays) days. Day \(sample?.key ?? 0): \(sampleStr)")
        } else {
            logger.info("[Diag.Plan] Supplements: none (user owns no shelf items)")
        }

        if orderViolations > 0 {
            logger.warning("[Diag.Plan] ⚠️ \(orderViolations) day(s) with dinner-before-19:00 — timing rule not honored")
        }
        logger.info("[Diag.Plan] ===== end =====")
    }

    // MARK: - Recipe Generation (Haiku)

    /// Generate one Recipe per PlannedMeal via Claude Haiku in parallel, then attach
    /// them to their meals. Recipe failures are logged but do not abort the plan —
    /// the user still gets a usable plan with the flat food list.
    @MainActor
    private func attachRecipes(
        to plan: WeeklyMealPlan,
        profile: DietaryProfile,
        intake: MealPlanIntake?,
        modelContext: ModelContext
    ) async {
        let meals = plan.meals ?? []
        guard !meals.isEmpty else {
            return
        }

        // Snapshot the data Haiku needs OUTSIDE the concurrency boundary — SwiftData
        // models are main-actor-isolated and can't cross into a TaskGroup body.
        struct MealRequest: Sendable {
            let mealID: UUID
            let mealName: String
            let foods: [PlannedFood]
        }
        let skillLevel = profile.cookingSkill.displayName
        // Recipe-level exclusions need to include the user's permanent
        // dislikes + allergies as well as this week's temporary
        // exclusions. Previously we only passed `temporaryExclusions`,
        // so Haiku could happily put broccoli in a recipe even when the
        // user had marked it as a permanent dislike on the DietaryProfile
        // — the weekly-plan-level prompt avoided it at the meal level,
        // but the per-recipe Haiku call had no idea.
        let exclusions: [String] = {
            var combined = intake?.temporaryExclusions ?? []
            combined.append(contentsOf: profile.allergies)
            combined.append(contentsOf: profile.dislikedFoods)
            return Array(Set(combined.map { $0.trimmingCharacters(in: .whitespaces) }))
                .filter { !$0.isEmpty }
        }()
        let requests: [MealRequest] = meals.map { meal in
            MealRequest(mealID: meal.id, mealName: meal.mealName, foods: meal.foods)
        }

        // Capped fan-out. Previously we fired all 28 recipes in parallel,
        // which routinely tripped the backend's 429 rate limit and
        // stretched attachRecipes wall-time non-deterministically — that
        // stretched window was the timing for the SwiftData invalidation
        // crash on plan regen. Batches of 4 stay under the rate limit
        // while keeping total wall-time roughly the same.
        let concurrency = 4
        var collected: [UUID: ParsedRecipe] = [:]
        for chunk in requests.chunked(into: concurrency) {
            let batch = await withTaskGroup(of: (UUID, ParsedRecipe?).self) { group in
                for request in chunk {
                    group.addTask { [weak self] in
                        guard let self else {
                            return (request.mealID, nil)
                        }
                        let parsed = await self.generateRecipeJSON(
                            mealName: request.mealName,
                            foods: request.foods,
                            skillLevel: skillLevel,
                            exclusions: exclusions
                        )
                        return (request.mealID, parsed)
                    }
                }
                var local: [UUID: ParsedRecipe] = [:]
                for await (id, parsed) in group {
                    if let parsed { local[id] = parsed }
                }
                return local
            }
            collected.merge(batch) { _, new in new }
        }
        let results = collected

        // Attach recipes to meals on the main actor.
        var attached = 0
        for meal in meals {
            guard let parsed = results[meal.id] else {
                continue
            }
            let recipe = makeRecipe(from: parsed, mealServings: 1)
            modelContext.insert(recipe)
            for ingredient in recipe.ingredients ?? [] {
                modelContext.insert(ingredient)
            }
            for step in recipe.steps ?? [] {
                modelContext.insert(step)
            }
            meal.recipe = recipe
            attached += 1
        }
        do {
            try modelContext.save()
            logger.info("Attached \(attached)/\(meals.count) recipes to meal plan \(plan.id)")
        } catch {
            logger.error("Failed to save recipes for plan \(plan.id): \(error.localizedDescription)")
        }
    }

    /// Single Haiku call for one meal via the backend proxy. Returns nil on
    /// failure (logged) so the fan-out can finish without aborting the whole
    /// plan. Per INTELLIGENCE_REMEDIATION_PLAN.md §3.
    private nonisolated func generateRecipeJSON(
        mealName: String,
        foods: [PlannedFood],
        skillLevel: String,
        exclusions: [String]
    ) async -> ParsedRecipe? {
        let systemPrompt = MealRecipePrompts.systemPrompt
        let userPrompt = MealRecipePrompts.userPrompt(
            mealName: mealName,
            servings: 1,
            foods: foods,
            skillLevel: skillLevel,
            exclusions: exclusions
        )

        do {
            let body = NutritionProxyTextRequest(
                model: "haiku",
                system: systemPrompt,
                userMessage: userPrompt,
                maxTokens: 4096,
                temperature: 0.4,
                caller: "meal_recipe"
            )
            let response: NutritionProxyTextResponse = try await apiClient.request(
                APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                body: body
            )
            return try parseRecipeJSON(response.text)
        } catch {
            logger.warning("Recipe generation failed for '\(mealName)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Decode the Haiku JSON envelope. Tolerates markdown/text wrap by extracting
    /// the first `{...}` block. Captures the underlying decode error so the
    /// caller's log shows *why* the parse failed — silent decode-or-nil hid
    /// missing-key bugs (e.g. recipe steps without `instruction`).
    private nonisolated func parseRecipeJSON(_ response: String) throws -> ParsedRecipe {
        let decoder = JSONDecoder()
        var firstError: Error?
        if let data = response.data(using: .utf8) {
            do {
                return try decoder.decode(ParsedRecipe.self, from: data)
            } catch {
                firstError = error
            }
        }
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8) {
                return try decoder.decode(ParsedRecipe.self, from: data)
            }
        }
        let detail = firstError.map { String(describing: $0) } ?? "no '{...}' block found"
        throw MealPlanGeneratorError.parsingFailed("Could not parse recipe JSON: \(detail)")
    }

    /// Convert the decoded JSON into SwiftData entities. Caps step count and
    /// guards against negative defrost values. Called on the main actor by
    /// `attachRecipes` since SwiftData models share the context's actor.
    @MainActor
    private func makeRecipe(from parsed: ParsedRecipe, mealServings: Int) -> Recipe {
        let recipe = Recipe(
            name: parsed.name,
            recipeDescription: parsed.description,
            cuisine: parsed.cuisine?.isEmpty == false ? parsed.cuisine : nil,
            servings: parsed.servings > 0 ? parsed.servings : max(mealServings, 1),
            prepMinutes: max(0, parsed.prepTimeMinutes),
            cookMinutes: max(0, parsed.cookTimeMinutes),
            difficulty: RecipeDifficulty(rawValue: parsed.difficulty.lowercased()) ?? .easy,
            equipment: parsed.equipment ?? [],
            dietaryTags: parsed.dietaryTags ?? [],
            totalCalories: parsed.macrosPerServing.calories,
            totalProteinGrams: parsed.macrosPerServing.protein,
            totalCarbsGrams: parsed.macrosPerServing.carbs,
            totalFatGrams: parsed.macrosPerServing.fat,
            source: .aiGenerated
        )

        let ingredients: [RecipeIngredient] = parsed.ingredients.enumerated().map { idx, raw in
            let location = PantryStorageLocation(rawValue: raw.storageLocation.lowercased())
            let defrostHours: Int = location == .freezer ? max(0, raw.defrostLeadTimeHours) : 0
            return RecipeIngredient(
                recipe: recipe,
                orderIndex: idx,
                canonicalFoodName: raw.name.lowercased(),
                displayName: raw.displayName.isEmpty ? raw.name : raw.displayName,
                quantityGrams: max(0, raw.quantityGrams),
                displayQuantity: raw.displayQuantity?.isEmpty == false ? raw.displayQuantity : nil,
                calories: raw.calories,
                proteinGrams: raw.proteinGrams,
                carbsGrams: raw.carbsGrams,
                fatGrams: raw.fatGrams,
                storageLocation: location,
                defrostLeadTimeHours: defrostHours
            )
        }
        recipe.ingredients = ingredients

        let cappedSteps = parsed.steps.prefix(MealRecipePrompts.maxSteps)
        let steps: [RecipeStep] = cappedSteps.enumerated().map { idx, raw in
            RecipeStep(
                recipe: recipe,
                orderIndex: idx,
                instruction: raw.instruction,
                durationMinutes: raw.durationMinutes.map { max(0, $0) }
            )
        }
        recipe.steps = steps
        return recipe
    }

    // MARK: - Private Helpers

    /// Build user preferences string from profile.
    /// Rolling 14-day average of the user's actual eat times, grouped by
    /// `mealNumber`. Reads `PlannedMeal.actualEatenAt` (set by `markMealEaten`).
    /// Returns nil/empty when there's no signal yet so the prompt falls back
    /// to the schema defaults (07:30 / 12:30 / 19:30 / 16:00).
    func observedMealTimes(
        modelContext: ModelContext,
        windowDays: Int = 14,
        wakeMinutesOverride: Int? = nil,
        eatingWindow: EatingWindow? = nil,
        breakfastSkipped: Bool = false
    ) -> MealPlanPrompts.ObservedMealTimes? {
        let calendar = Calendar.current

        // Wake anchor priority:
        //   1. Whoop's actual wake (wakeMinutesOverride) — the user's real
        //      rhythm. iOS won't share the Health Sleep Schedule, so Whoop
        //      is the best signal we have.
        //   2. UserSettings.wakeTimeMinutes — the onboarding/planned wake.
        //   3. 07:00 default.
        let wakeMinutes = wakeMinutesOverride
            ?? (try? modelContext.fetch(FetchDescriptor<UserSettings>()).first?.wakeTimeMinutes)
            ?? 420

        // Learned signal: average actualEatenAt per mealNumber over the
        // window, ≥2 observations required.
        var learned: [Int: Int] = [:] // mealNumber → minutes-from-midnight
        if let windowStart = calendar.date(
            byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: Date())
        ) {
            let descriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate<PlannedMeal> { meal in
                    meal.dayDate >= windowStart
                }
            )
            let meals = ((try? modelContext.fetch(descriptor)) ?? [])
                .filter { $0.actualEatenAt != nil }
            var minutesByMealNumber: [Int: [Int]] = [:]
            for meal in meals {
                guard let eaten = meal.actualEatenAt else { continue }
                let comps = calendar.dateComponents([.hour, .minute], from: eaten)
                minutesByMealNumber[meal.mealNumber, default: []]
                    .append((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
            }
            for (number, mins) in minutesByMealNumber where mins.count >= 2 {
                learned[number] = mins.reduce(0, +) / mins.count
            }
        }

        // For each of the 4 canonical slots, prefer the learned time;
        // otherwise fall back to wake-anchored defaults with soft
        // ceilings. We ALWAYS return a value (never nil) so the backend's
        // own 08:00/12:30/16:00/19:30 defaults never fire — those ignore
        // the user's wake entirely. Soft ceilings only bind when no
        // learned signal exists; a late calendar event (soccer) is
        // handled at display/shift time, not here.
        //
        //   1 Breakfast : wake + 60m
        //   2 Lunch     : wake + 300m, capped at 13:30
        //   3 Snack     : wake + 480m, capped at 16:30
        //   4 Dinner    : wake + 720m, capped at 21:00
        func clampToCeiling(_ minutes: Int, ceiling: Int) -> Int {
            min(minutes, ceiling)
        }
        // mealNumber → time. NOTE the labels: 1 Breakfast, 2 Lunch,
        // 3 DINNER (evening), 4 SNACK (afternoon). Chronologically the
        // afternoon Snack falls BEFORE Dinner, so slot 4's time is earlier
        // than slot 3's — the Plan/Today views sort by scheduledTime, not
        // mealNumber, so this renders in the right order. (This fixes the
        // prior swap where Dinner got the 16:30 afternoon slot and Snack
        // got 21:00.)
        let defaults: [Int: Int] = [
            1: wakeMinutes + 60, // Breakfast: wake + 1h
            2: clampToCeiling(wakeMinutes + 300, ceiling: 13 * 60 + 30), // Lunch ≤13:30
            3: clampToCeiling(wakeMinutes + 600, ceiling: 20 * 60 + 30), // Dinner (evening) ≤20:30
            4: clampToCeiling(wakeMinutes + 420, ceiling: 17 * 60), // Snack (afternoon) ≤17:00
        ]

        // Onboarding eating window: every anchor must sit inside it, otherwise
        // the prompt gets "use observed times verbatim" AND "no meal before
        // 12:00" for a 09:00 breakfast and the model picks one at random.
        // Breakfast-skippers get no slot 1 at all.
        let window = eatingWindow.flatMap { $0.isValid ? $0 : nil }
        var result: [Int: String] = [:]
        for number in 1 ... 4 {
            if breakfastSkipped, number == 1 {
                continue
            }
            let minutes = learned[number] ?? defaults[number] ?? (wakeMinutes + 60)
            var clamped = max(0, min(minutes, 23 * 60 + 59))
            if let window {
                clamped = min(max(clamped, window.firstMealHour * 60), window.lastMealHour * 60)
            }
            result[number] = String(format: "%02d:%02d", clamped / 60, clamped % 60)
        }
        return result
    }

    /// Pulls non-archived PantryItems expiring within the next 7 days, sorted
    /// by urgency (soonest first). Returns canonical names + days-to-expire
    /// for the weekly-plan prompt's FIFO hint block.
    ///
    /// Items already expired (negative days) are excluded — we don't suggest
    /// recipes that consume spoiled food.
    private func expiringPantryItems(modelContext: ModelContext) -> [(name: String, days: Int)] {
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                !item.isArchived && item.quantity > 0 && item.useBy != nil
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items
            .compactMap { item -> (String, Int)? in
                guard let days = item.daysUntilUseBy, (0...7).contains(days) else {
                    return nil
                }
                return (item.canonicalName, days)
            }
            .sorted { lhs, rhs in lhs.1 < rhs.1 }
            .map { (name: $0.0, days: $0.1) }
    }

    /// Full non-archived pantry stock (qty > 0), as human-readable
    /// "name — quantity unit" lines for the weekly-plan prompt. This lets the
    /// AI build meals AROUND what the user already owns (the pantry-first goal)
    /// rather than only avoiding expiry. Quantities render in whole units for
    /// countable foods ("5 eggs") to match how the user thinks about stock and
    /// how the pantry decrement counts them. Capped + grouped to bound tokens.
    private func pantryStock(modelContext: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                !item.isArchived && item.quantity > 0
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        // Sort by storage location then name for a stable, scannable list.
        return items
            .sorted { lhs, rhs in
                if lhs.storageLocationRaw != rhs.storageLocationRaw {
                    return lhs.storageLocationRaw < rhs.storageLocationRaw
                }
                return lhs.canonicalName < rhs.canonicalName
            }
            .map { item in
                let qty: String
                if item.quantity == item.quantity.rounded() {
                    qty = "\(Int(item.quantity))"
                } else {
                    qty = String(format: "%.1f", item.quantity)
                }
                return "\(item.canonicalName) — \(qty) \(item.unit.displayName) [\(item.storageLocation.displayName)]"
            }
    }

    /// Fetch the single UserSettings record (for meal-count / cook-time prefs).
    /// nil when none exists yet.
    static func fetchUserSettings(modelContext: ModelContext) -> UserSettings? {
        (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first
    }

    /// Display names of the appliances the user has marked available, so the
    /// plan prompt can constrain recipes to a makeable set. Returns [] when no
    /// `KitchenEquipment` rows exist yet (page never opened) — the prompt then
    /// omits the constraint rather than assuming an empty kitchen.
    static func availableEquipment(modelContext: ModelContext) -> [String] {
        let rows = (try? modelContext.fetch(
            FetchDescriptor<KitchenEquipment>(
                predicate: #Predicate<KitchenEquipment> { $0.isAvailable }
            )
        )) ?? []
        return rows
            .compactMap(\.kind)
            .map(\.displayName)
            .sorted()
    }

    /// Fetch the user's active supplement shelf for the plan prompt. The AI
    /// reads this to make a per-day take/skip decision (creatine daily, whey to
    /// fill a protein gap, omega-3 periodized). Empty when the user owns none —
    /// the prompt then omits the supplement block + per-day supplements field.
    private func supplementShelf(modelContext: ModelContext) -> [Supplement] {
        let descriptor = FetchDescriptor<Supplement>(
            predicate: #Predicate<Supplement> { !$0.isArchived }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items.sorted { $0.name < $1.name }
    }

    /// Aggregate the last `windowDays` of `MealFeedback` rows into a digest
    /// the prompt can act on. Groups by recipe and by ingredient. Filters
    /// out empty / signal-less rows so the prompt stays lean.
    private func recentFeedbackDigest(
        modelContext: ModelContext,
        windowDays: Int = 28
    ) -> MealPlanPrompts.FeedbackDigest? {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(
            byAdding: .day,
            value: -windowDays,
            to: calendar.startOfDay(for: Date())
        ) else {
            return nil
        }
        let descriptor = FetchDescriptor<MealFeedback>(
            predicate: #Predicate<MealFeedback> { feedback in
                feedback.createdAt >= windowStart
            }
        )
        let rows = ((try? modelContext.fetch(descriptor)) ?? []).filter(\.hasSignal)
        guard !rows.isEmpty else {
            return nil
        }

        // Group by recipe (denormalized recipeID survives meal deletion).
        var recipeBuckets: [UUID: [MealFeedback]] = [:]
        for row in rows {
            guard let recipeID = row.recipeID else { continue }
            recipeBuckets[recipeID, default: []].append(row)
        }
        let recipes: [MealPlanPrompts.FeedbackDigest.RecipeSignal] = recipeBuckets.compactMap { _, bucket in
            guard let first = bucket.first else { return nil }
            let ratings = bucket.compactMap(\.rating).map(Double.init)
            let avg = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
            // Aggregate post-meal feel chips by raw value so the prompt
            // surface ("sluggish 4×, heavy 1×") matches the enum vocabulary.
            var feelCounts: [String: Int] = [:]
            var satietyCounts: [String: Int] = [:]
            for row in bucket {
                if let feel = row.mealFeel {
                    feelCounts[feel.rawValue, default: 0] += 1
                }
                if let satiety = row.satiety {
                    satietyCounts[satiety.rawValue, default: 0] += 1
                }
            }
            return MealPlanPrompts.FeedbackDigest.RecipeSignal(
                recipeName: first.recipeName ?? "(unknown recipe)",
                averageRating: avg,
                mentionCount: bucket.count,
                notes: bucket.compactMap(\.overallNote).filter { !$0.isEmpty },
                portionNotes: bucket.compactMap(\.portionNote).filter { !$0.isEmpty },
                suggestedChanges: bucket.compactMap(\.suggestedChange).filter { !$0.isEmpty },
                feelCounts: feelCounts,
                satietyCounts: satietyCounts,
                substituteNotes: bucket.compactMap(\.substituteNote).filter { !$0.isEmpty }
            )
        }

        // Aggregate ingredient sentiment across all feedback rows.
        struct IngredientAccumulator {
            var liked = 0
            var disliked = 0
            var notes: [String] = []
        }
        var ingredientBuckets: [String: IngredientAccumulator] = [:]
        for row in rows {
            for note in row.ingredientNotes {
                var acc = ingredientBuckets[note.ingredientName, default: IngredientAccumulator()]
                switch note.sentiment {
                case .liked: acc.liked += 1
                case .disliked, .wrongForm, .portionTooBig, .portionTooSmall: acc.disliked += 1
                case .neutral: break
                }
                if let text = note.note, !text.isEmpty {
                    // Tag with recipe context so the model can disambiguate.
                    let ctx = row.recipeName.map { "[\($0)] " } ?? ""
                    acc.notes.append(ctx + text)
                }
                ingredientBuckets[note.ingredientName] = acc
            }
        }
        let ingredients: [MealPlanPrompts.FeedbackDigest.IngredientSignal] = ingredientBuckets
            .compactMap { name, acc in
                guard acc.liked + acc.disliked + acc.notes.count > 0 else { return nil }
                return MealPlanPrompts.FeedbackDigest.IngredientSignal(
                    ingredientName: name,
                    perRecipeNotes: acc.notes,
                    likedCount: acc.liked,
                    dislikedCount: acc.disliked
                )
            }

        guard !recipes.isEmpty || !ingredients.isEmpty else {
            return nil
        }
        return MealPlanPrompts.FeedbackDigest(recipes: recipes, ingredients: ingredients)
    }

    private func buildPreferences(from profile: DietaryProfile) -> String {
        var prefs: [String] = []
        prefs.append("Training frequency: \(profile.trainingFrequency)x/week")
        prefs.append("Goal: \(profile.primaryGoal.displayName)")
        prefs.append("Skill level: \(profile.skillLevel.displayName)")
        prefs.append("Cooking skill: \(profile.cookingSkill.displayName)")
        return prefs.joined(separator: ". ")
    }

    /// Send a Claude Sonnet request through the backend proxy with retry logic.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §3 — the Anthropic key lives only
    /// on the Vapor backend now; iOS calls /v1/nutrition/ai/proxy/text.
    private func sendWithRetry(
        system: String,
        prompt: String,
        feature: String
    ) async throws -> String {
        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "sonnet",
                    system: system,
                    userMessage: prompt,
                    maxTokens: 32_768,
                    temperature: 0.3,
                    caller: feature
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                logger.info("[\(feature)] Claude response received via backend (attempt \(attempt))")
                return response.text
            } catch let error as APIError {
                lastError = error
                logger.warning("[\(feature)] Backend proxy error (attempt \(attempt)): \(String(describing: error))")

                guard error.isRetryable, attempt < maxRetries else {
                    break
                }

                let delay: TimeInterval = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch {
                lastError = error
                logger.error("[\(feature)] Unexpected error: \(error.localizedDescription)")
                break
            }
        }

        state = .failed("AI generation failed")
        throw MealPlanGeneratorError.generationFailed(lastError ?? APIError.unknown(statusCode: -1))
    }

    // MARK: - JSON Parsing

    /// Parse Claude's JSON response into structured day/meal data.
    private func parseWeeklyPlanJSON(_ response: String) throws -> ParsedWeeklyPlan {
        let decoder = JSONDecoder()
        var lastDecodeError: Error?

        if let data = response.data(using: .utf8) {
            do {
                return try decoder.decode(ParsedWeeklyPlan.self, from: data)
            } catch {
                lastDecodeError = error
            }
        }

        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8) {
                do {
                    let result = try decoder.decode(ParsedWeeklyPlan.self, from: data)
                    logger.info("[meal_plan_generation] JSON extracted from wrapped response")
                    return result
                } catch {
                    lastDecodeError = error
                }
            }
        }

        let length = response.count
        let endsCleanly = response.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}")
        logger
            .error(
                "[meal_plan_generation] JSON parse failed | length=\(length) endsCleanly=\(endsCleanly) error=\(String(describing: lastDecodeError))"
            )
        logger.error("[meal_plan_generation] Response prefix: \(response.prefix(300))")
        logger.error("[meal_plan_generation] Response suffix: \(response.suffix(300))")
        state = .failed("Could not parse meal plan response")
        throw MealPlanGeneratorError.parsingFailed("Could not parse meal plan JSON")
    }

    // MARK: - Eating pattern

    /// Drop breakfast for breakfast-skippers and clamp meal times into the
    /// eating window. Runs before scaling so a dropped breakfast's calories
    /// are re-spread by `scaleMealsToTarget`. See MealPlanScheduleEnforcer.
    private func enforceEatingPattern(_ plan: ParsedWeeklyPlan, intake: MealPlanIntake) -> ParsedWeeklyPlan {
        let days = plan.days.map { day in
            let kept = MealPlanScheduleEnforcer.enforce(
                day.meals.map { .init(mealNumber: $0.mealNumber, scheduledTime: $0.scheduledTime) },
                window: intake.eatingWindow,
                breakfastSkipped: intake.breakfastSkipped
            )
            if kept.count != day.meals.count {
                logger.info("[Diag.Plan] day \(day.dayIndex): dropped \(day.meals.count - kept.count) breakfast slot(s) (breakfastSkipped)")
            }
            let meals = kept.map { entry in
                let meal = day.meals[entry.index]
                return ParsedMealData(
                    mealNumber: meal.mealNumber,
                    mealName: meal.mealName,
                    scheduledTime: entry.scheduledTime,
                    foods: meal.foods
                )
            }
            return ParsedDay(dayIndex: day.dayIndex, dayType: day.dayType, meals: meals, supplements: day.supplements)
        }
        return ParsedWeeklyPlan(days: days)
    }

    // MARK: - Validation & Scaling

    /// Validate each food's macros against FoodMacroDatabase and scale if >5% off.
    private func validateAndScaleMeals(
        _ plan: ParsedWeeklyPlan,
        targets: [DayType: MacroTargets]
    ) -> ParsedWeeklyPlan {
        var correctedDays: [ParsedDay] = []

        for day in plan.days {
            var correctedMeals: [ParsedMealData] = []

            for meal in day.meals {
                var correctedFoods: [ParsedFoodData] = []

                for food in meal.foods {
                    let corrected = validateFood(food)
                    correctedFoods.append(corrected)
                }

                correctedMeals.append(ParsedMealData(
                    mealNumber: meal.mealNumber,
                    mealName: meal.mealName,
                    scheduledTime: meal.scheduledTime,
                    foods: correctedFoods
                ))
            }

            // Scale day totals to match target within tolerance
            let dayType = DayType(rawValue: day.dayType) ?? .rest
            if let target = targets[dayType] {
                correctedMeals = scaleMealsToTarget(correctedMeals, target: target)
            }

            correctedDays.append(ParsedDay(
                dayIndex: day.dayIndex,
                dayType: day.dayType,
                meals: correctedMeals,
                supplements: day.supplements
            ))
        }

        return ParsedWeeklyPlan(days: correctedDays)
    }

    /// Validate a single food item against FoodMacroDatabase.
    /// If the database has it and macros differ by >5%, use database values scaled to the quantity.
    private func validateFood(_ food: ParsedFoodData) -> ParsedFoodData {
        guard let dbMacros = FoodMacroDatabase.lookup(food.name) else {
            return food
        }

        let scaled = dbMacros.scaled(to: food.quantityGrams)
        let calDelta = abs(food.calories - scaled.calories)
        let calThreshold = scaled.calories * 0.05

        if calDelta > calThreshold {
            logger.info("Correcting \(food.name): \(Int(food.calories)) -> \(Int(scaled.calories)) kcal")
            return ParsedFoodData(
                name: food.name,
                quantityGrams: food.quantityGrams,
                calories: scaled.calories.rounded(),
                proteinG: scaled.protein.rounded(),
                carbsG: scaled.carbs.rounded(),
                fatG: scaled.fat.rounded()
            )
        }

        return food
    }

    /// Scale all meals proportionally so the day total matches the target within 3%.
    private func scaleMealsToTarget(
        _ meals: [ParsedMealData],
        target: MacroTargets
    ) -> [ParsedMealData] {
        let totalCal = meals.flatMap(\.foods).reduce(0.0) { $0 + $1.calories }
        let targetCal = Double(target.calories)
        // Both sides must be positive; a zero target would otherwise scale
        // every meal to zero calories silently.
        guard totalCal > 0, targetCal > 0 else {
            return meals
        }

        let ratio = targetCal / totalCal

        // Only scale if off by more than 5%
        guard abs(ratio - 1.0) > 0.05 else {
            return meals
        }

        logger.info("Scaling meals: \(Int(totalCal)) -> \(target.calories) kcal (ratio: \(String(format: "%.2f", ratio)))")

        return meals.map { meal in
            let scaledFoods = meal.foods.map { food in
                ParsedFoodData(
                    name: food.name,
                    quantityGrams: (food.quantityGrams * ratio).rounded(),
                    calories: (food.calories * ratio).rounded(),
                    proteinG: (food.proteinG * ratio).rounded(),
                    carbsG: (food.carbsG * ratio).rounded(),
                    fatG: (food.fatG * ratio).rounded()
                )
            }
            return ParsedMealData(
                mealNumber: meal.mealNumber,
                mealName: meal.mealName,
                scheduledTime: meal.scheduledTime,
                foods: scaledFoods
            )
        }
    }

    // MARK: - Persistence

    /// Create WeeklyMealPlan and PlannedMeal records in SwiftData.
    @MainActor
    private func persistPlan(
        _ plan: ParsedWeeklyPlan,
        targets: [DayType: MacroTargets],
        modelContext: ModelContext
    ) throws -> WeeklyMealPlan {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Plan-start is the Monday of THIS week — matches the prompt's
        // contract that day.dayIndex 0 = Monday, 6 = Sunday. Previously
        // startDate was today and dayIndex was treated as "days from
        // today" — that worked for "today's meal" queries but broke the
        // user's training schedule alignment. With football=Wed+Sun in
        // settings, Haiku correctly emitted dayIndex 2 = soccer; the
        // offset-from-today math then shifted Wed-soccer to (today+2),
        // which was Sat-soccer when the plan was generated on Thursday.
        //
        // Anchoring on the actual Monday makes weekday math trivial:
        // weekdayNumber = dayIndex + 1 (Mon=1, …, Sun=7). The user's
        // Today/Dashboard "today's meal" query (filter by dayDate) still
        // resolves because today's PlannedMeal will be one of the seven
        // rows generated.
        //
        // ISO 8601 week (Calendar.current may not be ISO; .iso8601 returns
        // Monday-anchored). Subtract days to get Monday-of-this-week even
        // when the device locale starts the week on Sunday.
        let weekdayOfToday = calendar.component(.weekday, from: today) // 1=Sun, 2=Mon, ..., 7=Sat
        let mondayOffset = (weekdayOfToday + 5) % 7 // days since Monday: Mon=0, Tue=1, ..., Sun=6
        let startDate = calendar.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
        let endDate = calendar.date(byAdding: .day, value: 6, to: startDate)!

        // Build day type assignments keyed by absolute weekday (Mon=1..Sun=7)
        // so RecoverIQ / training-day logic gets a stable mapping.
        var dayTypeAssignments: [Int: String] = [:]
        var supplementDecisions: [Int: [SupplementDecision]] = [:]
        for day in plan.days {
            // dayIndex 0 = Monday per the prompt contract. Map directly.
            let weekdayNumber = day.dayIndex + 1
            dayTypeAssignments[weekdayNumber] = day.dayType
            // Capture the AI's per-day supplement take/skip decisions (only
            // present when the user owns supplements). Stored on the plan,
            // surfaced as "Today's supplements".
            if let supps = day.supplements, !supps.isEmpty {
                supplementDecisions[weekdayNumber] = supps.map {
                    SupplementDecision(name: $0.name, take: $0.take, timing: $0.timing, reason: $0.reason)
                }
            }
        }

        // ARCHIVE (don't delete) existing active plans. The personalization
        // engine needs last week's ACTUAL behavior — eaten/skipped statuses,
        // actualEatenAt, and recipes — which a hard delete would cascade-wipe
        // (WeeklyMealPlan → PlannedMeal → Recipe are all .cascade). Marking
        // isActive=false + isArchived=true retains the rows.
        //
        // Safe against the old duplicate-meals bug ONLY because every TODAY/
        // active surface now filters `meal.mealPlan?.isActive == true`
        // (NutritionTabViewModel.loadToday/refreshTodayMeals,
        // targetsForToday(in:), FuelDayScheduleViewModel,
        // DashboardViewModel+NutritionFetch). Archived plans' meals fail that
        // filter, so an overlapping-week regen no longer double-renders.
        let existingDescriptor = FetchDescriptor<WeeklyMealPlan>(
            predicate: #Predicate<WeeklyMealPlan> { $0.isActive }
        )
        if let existingPlans = try? modelContext.fetch(existingDescriptor) {
            for existing in existingPlans {
                existing.isActive = false
                existing.isArchived = true
            }
        }

        // Prune archived plans older than the retention window (12 weeks) so
        // the local store stays bounded. Pruning a WeeklyMealPlan cascades to
        // its PlannedMeals + Recipes; MealFeedback (.nullify, denormalized
        // recipeID) survives regardless, so older feedback signal is kept.
        let retentionCutoff = Calendar.current.date(
            byAdding: .weekOfYear, value: -12, to: Date()
        ) ?? Date.distantPast
        let staleDescriptor = FetchDescriptor<WeeklyMealPlan>(
            predicate: #Predicate<WeeklyMealPlan> { plan in
                plan.isArchived && plan.endDate < retentionCutoff
            }
        )
        if let stalePlans = try? modelContext.fetch(staleDescriptor) {
            for stale in stalePlans {
                modelContext.delete(stale)
            }
        }

        // Create the plan
        let weeklyPlan = WeeklyMealPlan(
            startDate: startDate,
            endDate: endDate,
            dayTypeAssignments: dayTypeAssignments,
            isActive: true
        )
        if !supplementDecisions.isEmpty {
            weeklyPlan.supplementDecisions = supplementDecisions
        }
        modelContext.insert(weeklyPlan)

        // Create PlannedMeal records
        for day in plan.days {
            let dayDate = calendar.date(byAdding: .day, value: day.dayIndex, to: startDate)!

            for meal in day.meals {
                let foods = meal.foods.map { food in
                    PlannedFood(
                        name: food.name,
                        quantityGrams: food.quantityGrams,
                        calories: food.calories,
                        proteinG: food.proteinG,
                        carbsG: food.carbsG,
                        fatG: food.fatG
                    )
                }

                let totalCal = foods.reduce(0.0) { $0 + $1.calories }
                let totalProt = foods.reduce(0.0) { $0 + $1.proteinG }
                let totalCarbs = foods.reduce(0.0) { $0 + $1.carbsG }
                let totalFat = foods.reduce(0.0) { $0 + $1.fatG }

                let plannedMeal = PlannedMeal(
                    dayDate: dayDate,
                    mealNumber: meal.mealNumber,
                    mealName: meal.mealName,
                    scheduledTime: meal.scheduledTime,
                    foods: foods,
                    totalCalories: totalCal,
                    totalProtein: totalProt,
                    totalCarbs: totalCarbs,
                    totalFat: totalFat,
                    status: .planned,
                    mealPlan: weeklyPlan
                )

                modelContext.insert(plannedMeal)
            }
        }

        try modelContext.save()
        return weeklyPlan
    }
}

// MARK: - ParsedWeeklyPlan

private struct ParsedWeeklyPlan: Codable {
    let days: [ParsedDay]
}

// MARK: - ParsedDay

private struct ParsedDay: Codable {
    let dayIndex: Int
    let dayType: String
    let meals: [ParsedMealData]
    /// Per-day supplement take/skip decisions. Optional — only present when the
    /// user owns supplements (a <supplement_shelf> was in the prompt). Captured
    /// here so the persistence layer (Piece 2d) can surface "today: take X,
    /// skip Y". nil when the user owns no supplements.
    let supplements: [ParsedSupplementDecision]?
}

// MARK: - ParsedSupplementDecision

private struct ParsedSupplementDecision: Codable {
    let name: String
    let take: Bool
    let timing: String?
    let reason: String?
}

// MARK: - ParsedMealData

private struct ParsedMealData: Codable {
    let mealNumber: Int
    let mealName: String
    let scheduledTime: String
    let foods: [ParsedFoodData]
}

// MARK: - ParsedFoodData

private struct ParsedFoodData: Codable {
    let name: String
    let quantityGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

// MARK: - ParsedRecipe

struct ParsedRecipe: Codable, Sendable {
    let name: String
    let description: String?
    let cuisine: String?
    let servings: Int
    let prepTimeMinutes: Int
    let cookTimeMinutes: Int
    let difficulty: String
    let equipment: [String]?
    let dietaryTags: [String]?
    let ingredients: [ParsedRecipeIngredient]
    let steps: [ParsedRecipeStep]
    let macrosPerServing: ParsedMacros
}

// MARK: - ParsedRecipeIngredient

struct ParsedRecipeIngredient: Codable, Sendable {
    let name: String
    let displayName: String
    let quantityGrams: Double
    let displayQuantity: String?
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let storageLocation: String
    let defrostLeadTimeHours: Int
}

// MARK: - ParsedRecipeStep

struct ParsedRecipeStep: Codable, Sendable {
    let order: Int
    let instruction: String
    let durationMinutes: Int?
}

// MARK: - ParsedMacros

struct ParsedMacros: Codable, Sendable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

// MARK: - MealPlanGeneratorError

enum MealPlanGeneratorError: Error, LocalizedError {
    case generationFailed(Error)
    case parsingFailed(String)
    case validationFailed(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .generationFailed(error):
            if let apiError = error as? APIError {
                switch apiError {
                case .unauthorized:
                    "Sign-in expired. Please log in again."
                case .rateLimited:
                    "AI rate limit reached. Wait a moment and try again."
                case .timeout:
                    "AI request timed out. Check your internet connection and try again."
                case let .networkError(msg):
                    "Network error: \(msg)"
                case .serverError, .unknown:
                    "AI service temporarily unavailable. Try again in a moment."
                default:
                    "AI generation failed. Please try again."
                }
            } else {
                "AI generation failed. Please try again."
            }
        case .parsingFailed:
            "Could not parse the meal plan response. Try generating again."
        case let .validationFailed(msg):
            "Meal plan validation failed: \(msg)"
        case let .persistenceFailed(msg):
            "Could not save meal plan: \(msg)"
        }
    }
}

// MARK: - Chunked helper

extension Array {
    /// Splits the array into sub-arrays of at most `size` elements,
    /// preserving order. Used by attachRecipes to throttle the
    /// concurrent Haiku fan-out.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
