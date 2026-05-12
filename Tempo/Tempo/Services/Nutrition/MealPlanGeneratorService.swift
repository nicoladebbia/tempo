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
/// Per AI_INTELLIGENCE_ENGINE.md:
/// - Sonnet for deep analysis (meal plan generation)
/// - Circuit breaker via ClaudeAPIClient
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

    private let claude: ClaudeAPIClient
    private let logger = Logger.nutrition

    // MARK: - Retry Configuration

    private let maxRetries = 2
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Init

    init(claude: ClaudeAPIClient = ClaudeAPIClient()) {
        self.claude = claude
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
        modelContext: ModelContext,
        intake: MealPlanIntake? = nil,
        onStatus: ((GenerationState) -> Void)? = nil
    ) async throws -> WeeklyMealPlan {
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
            goal: profile.primaryGoal
        )

        logger.info("TDEE calculated: \(Int(tdeeResult.tdee)) kcal, adjusted: \(tdeeResult.adjustedCalories) kcal")

        // Step 2: Build dietary restrictions from profile
        let restrictions = MealPlanPrompts.DietaryRestrictions(from: profile)

        // Step 3: Build prompt and call Claude Sonnet
        setState(.generating)

        let preferences = buildPreferences(from: profile)
        let (systemPrompt, userPrompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: tdeeResult.dayTypeTargets,
            restrictions: restrictions,
            preferences: preferences
        )

        let response = try await sendWithRetry(
            system: systemPrompt,
            prompt: userPrompt,
            feature: "meal_plan_generation"
        )

        // Step 4: Parse JSON response
        setState(.validating)

        let parsedPlan = try parseWeeklyPlanJSON(response)

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

        return weeklyPlan
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
        let exclusions = intake?.temporaryExclusions ?? []
        let requests: [MealRequest] = meals.map { meal in
            MealRequest(mealID: meal.id, mealName: meal.mealName, foods: meal.foods)
        }

        // Fan out — capped concurrency would be safer for rate limits, but
        // 21 parallel Haiku requests are well within Anthropic's per-key limit.
        let results = await withTaskGroup(of: (UUID, ParsedRecipe?).self) { group in
            for request in requests {
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
            var collected: [UUID: ParsedRecipe] = [:]
            for await (id, parsed) in group {
                if let parsed {
                    collected[id] = parsed
                }
            }
            return collected
        }

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

    /// Single Haiku call for one meal. Returns nil on failure (logged) so the
    /// fan-out can finish without aborting the whole plan.
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
            let response = try await claude.sendMessage(
                model: .haiku,
                system: systemPrompt,
                userMessage: userPrompt,
                maxTokens: 2048,
                temperature: 0.4
            )
            return try parseRecipeJSON(response)
        } catch {
            logger.warning("Recipe generation failed for '\(mealName)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Decode the Haiku JSON envelope. Tolerates markdown/text wrap by extracting
    /// the first `{...}` block.
    private nonisolated func parseRecipeJSON(_ response: String) throws -> ParsedRecipe {
        let decoder = JSONDecoder()
        if let data = response.data(using: .utf8),
           let direct = try? decoder.decode(ParsedRecipe.self, from: data)
        {
            return direct
        }
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8) {
                return try decoder.decode(ParsedRecipe.self, from: data)
            }
        }
        throw MealPlanGeneratorError.parsingFailed("Could not parse recipe JSON")
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
    private func buildPreferences(from profile: DietaryProfile) -> String {
        var prefs: [String] = []
        prefs.append("Training frequency: \(profile.trainingFrequency)x/week")
        prefs.append("Goal: \(profile.primaryGoal.displayName)")
        prefs.append("Skill level: \(profile.skillLevel.displayName)")
        prefs.append("Cooking skill: \(profile.cookingSkill.displayName)")
        return prefs.joined(separator: ". ")
    }

    /// Send a Claude Sonnet request with retry logic.
    private func sendWithRetry(
        system: String,
        prompt: String,
        feature: String
    ) async throws -> String {
        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let response = try await claude.sendMessage(
                    model: .sonnet,
                    system: system,
                    userMessage: prompt,
                    maxTokens: 8192,
                    temperature: 0.3
                )
                logger.info("[\(feature)] Claude response received (attempt \(attempt))")
                return response
            } catch let error as ClaudeAPIError {
                lastError = error
                logger.warning("[\(feature)] Claude API error (attempt \(attempt)): \(String(describing: error))")

                guard error.isRetryable, attempt < maxRetries else {
                    break
                }

                let delay: TimeInterval = if case let .rateLimited(retryAfter) = error, let after = retryAfter {
                    min(after, 8.0)
                } else {
                    baseRetryDelay * pow(2.0, Double(attempt))
                }

                try await Task.sleep(for: .seconds(delay))
            } catch {
                lastError = error
                logger.error("[\(feature)] Unexpected error: \(error.localizedDescription)")
                break
            }
        }

        state = .failed("AI generation failed")
        throw MealPlanGeneratorError.generationFailed(
            lastError as? ClaudeAPIError ?? .networkError("Unknown error")
        )
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
                meals: correctedMeals
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
        guard totalCal > 0 else {
            return meals
        }

        let targetCal = Double(target.calories)
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

        // Find next Monday as start date
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilMonday = weekday == 2 ? 0 : (9 - weekday) % 7
        let startDate = calendar.date(byAdding: .day, value: daysUntilMonday, to: today)!
        let endDate = calendar.date(byAdding: .day, value: 6, to: startDate)!

        // Build day type assignments (weekday number -> day type)
        var dayTypeAssignments: [Int: String] = [:]
        for day in plan.days {
            // dayIndex 0 = Monday -> weekday 2, dayIndex 6 = Sunday -> weekday 1
            let weekdayNumber = day.dayIndex == 6 ? 1 : day.dayIndex + 2
            dayTypeAssignments[weekdayNumber] = day.dayType
        }

        // Deactivate any existing active plans
        let existingDescriptor = FetchDescriptor<WeeklyMealPlan>(
            predicate: #Predicate<WeeklyMealPlan> { $0.isActive }
        )
        if let existingPlans = try? modelContext.fetch(existingDescriptor) {
            for existing in existingPlans {
                existing.isActive = false
            }
        }

        // Create the plan
        let weeklyPlan = WeeklyMealPlan(
            startDate: startDate,
            endDate: endDate,
            dayTypeAssignments: dayTypeAssignments,
            isActive: true
        )
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
    case generationFailed(ClaudeAPIError)
    case parsingFailed(String)
    case validationFailed(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .generationFailed(apiError):
            switch apiError {
            case .authError:
                "API key not configured. Add your Anthropic API key in Secrets.xcconfig."
            case .circuitOpen:
                "AI service temporarily unavailable. Too many recent failures — try again in 30 minutes."
            case .rateLimited:
                "AI rate limit reached. Wait a moment and try again."
            case .timeout:
                "AI request timed out. Check your internet connection and try again."
            case let .networkError(msg):
                "Network error: \(msg)"
            default:
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
