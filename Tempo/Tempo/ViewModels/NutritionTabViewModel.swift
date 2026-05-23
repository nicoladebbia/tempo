//
// NutritionTabViewModel.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import os
import SwiftData
import SwiftUI

// MARK: - NutritionSection

enum NutritionSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case log = "Log"
    case coach = "Coach"
    case pantry = "Pantry"

    var id: String {
        rawValue
    }
}

// MARK: - NutritionLoadState

enum NutritionLoadState {
    case loading
    case loaded
    case error(String)
}

// MARK: - PantryGapAlert

/// Surfaced when a freshly-generated meal plan references ingredients the user
/// doesn't have in pantry. Includes the canonical names so the view can decide
/// whether to inline the list or just say "N items missing."
struct PantryGapAlert: Identifiable, Equatable {
    let id = UUID()
    let missingIngredients: [String]

    var summary: String {
        if missingIngredients.count == 1 {
            return "You're missing \(missingIngredients[0]). Add it to pantry?"
        }
        return "You're missing \(missingIngredients.count) ingredients for this plan. Add them to pantry?"
    }
}

// MARK: - NutritionTabViewModel

@Observable
@MainActor
final class NutritionTabViewModel {
    // MARK: - Phase 7 (pantry/grocery/recipe/receipt) — stored directly so
    // the lifetimes match `self`. Previously these lived in a static
    // `ObjectIdentifier`-keyed dictionary which leaked the state objects
    // and their services for every ViewModel instance.

    let pantryState = NutritionPantryState()
    let receiptState = NutritionReceiptState()
    let recipeState = NutritionRecipeState()
    let groceryState = NutritionGroceryState()

    var pantryService: (any PantryServiceProtocol)?
    var receiptService: (any ReceiptServiceProtocol)?
    var recipeService: (any RecipeServiceProtocol)?
    var groceryService: (any GroceryListServiceProtocol)?
    var intelligence: NutritionIntelligenceService?

    // MARK: - Service instances

    /// Held as stored properties so tests can replace them (and so each
    /// call doesn't construct a fresh service object with its own logger
    /// and URLSession underneath). `@ObservationIgnored` is required
    /// because @Observable rejects `lazy`; these aren't view-bindable.
    @ObservationIgnored
    /// Lazily constructed on first use because we need an APIClient (passed
    /// from the View layer) to proxy Claude calls through the backend.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §3.
    private var coachService: NutritionCoachService?
    @ObservationIgnored
    /// Lazily constructed on first use because we need an APIClient (passed
    /// from the View layer) to proxy Claude calls through the backend.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §3.
    private var redistributionService: MealRedistributionService?

    // MARK: - Task lifecycle

    /// Stored handles for in-flight async work. Replacing a task cancels the
    /// prior one so a fast tab-switch or retry doesn't race two writes onto
    /// the same @Observable state.
    private var planGenerationTask: Task<Void, Never>?
    private var mealSuggestionsTask: Task<Void, Never>?
    private var recoveryLoadTask: Task<Void, Never>?

    // No deinit cancel: @MainActor properties can't be touched from a
    // nonisolated deinit. Replacement-cancel inside each launch site
    // covers the practical re-entry case (tab switch / refresh); the
    // remaining edge case (deallocation while a task is in flight) is
    // bounded by the [weak self] capture inside each Task.

    // MARK: - State

    private(set) var loadState: NutritionLoadState = .loading
    var selectedTab: NutritionSection = .today

    // MARK: - Data

    private(set) var todayMeals: [PlannedMeal] = []
    /// Maps `PlannedMeal.id` → true when at least one `MealFeedback` row
    /// exists for it. Drives the "review pending" badge on past meal cards
    /// and the inline edit affordance in the end-of-week review screen.
    private(set) var feedbackPresence: [UUID: Bool] = [:]
    private(set) var weeklyPlan: WeeklyMealPlan?
    private(set) var presets: [MealPreset] = []
    private(set) var dietaryProfile: DietaryProfile?

    // MARK: - Generation

    var isGeneratingPlan: Bool = false
    var planGenerationError: String?

    /// Drill-sergeant phase label shown under the spinner ("Drafting the week…",
    /// "Writing recipes for every meal…", etc). Mirrors
    /// `MealPlanGeneratorService.state.statusLabel` via the onStatus callback.
    var planGenerationStatusLabel: String = ""

    /// Surfaced after `generatePlan` completes when the just-generated plan has
    /// ingredients not present in the user's pantry. Views observe this and
    /// present an alert/banner that deep-links to the Pantry tab.
    var pantryGapAlert: PantryGapAlert?

    // MARK: - Coaching

    var coachMessage: String?
    var isLoadingMealSuggestions: Bool = false
    var mealSuggestions: [MealSuggestion] = []
    var mealSuggestionError: String?

    // MARK: - Recovery (Whoop)

    private(set) var todayRecovery: WhoopRecoveryData?
    private(set) var todaySleep: WhoopSleepData?
    private(set) var recoveryNutritionGuidance: String?
    private(set) var isLoadingRecovery: Bool = false

    // MARK: - Computed

    var todayCaloriesConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalCalories) }
    }

    var todayCalorieTarget: Int {
        // PRIMARY: when an active WeeklyMealPlan exists, today's target IS
        // the sum of its planned meals for today. This guarantees the Today
        // number, the Coach number, and the Plan number all agree — they
        // were diverging because Today/Coach used a local Mifflin-St Jeor
        // calc while Plan used TDEECalculator (with whoopTDEE + body-fat
        // refinements). Same source of truth eliminates the mismatch the
        // user saw on screen (2,687 vs 3,536 vs 2,687).
        if !todayMeals.isEmpty {
            let summed = todayMeals.reduce(into: 0.0) { $0 += $1.totalCalories }
            return Int(summed)
        }

        // FALLBACK: no plan yet — return a Mifflin-St Jeor estimate from
        // the dietary profile so the Today screen still has a number on
        // first launch. Once the plan generates, the PRIMARY branch above
        // takes over and stays consistent with the Plan tab.
        guard let profile = dietaryProfile else {
            return 2400
        }
        let bmr: Double = if profile.biologicalSex == .male {
            10 * profile.currentWeightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) + 5
        } else {
            10 * profile.currentWeightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) - 161
        }
        let activityMultiplier = 1.2 + (Double(profile.trainingFrequency) * 0.05)
        var target = Int(bmr * activityMultiplier)
        switch profile.primaryGoal {
        case .leanGain: target += 200
        case .cut: target -= 400
        case .maintain: break
        }
        return target
    }

    var todayProteinConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalProtein) }
    }

    var todayProteinTarget: Int {
        // Same source-of-truth pattern as todayCalorieTarget: when an
        // active plan exists, sum the day's PlannedMeal proteinG so the
        // Today number agrees with what the Plan tab said it should be.
        if !todayMeals.isEmpty {
            let summed = todayMeals.reduce(into: 0.0) { $0 += $1.totalProtein }
            return Int(summed)
        }
        guard let profile = dietaryProfile else {
            return 180
        }
        // ~2g per kg for training individuals
        return Int(profile.currentWeightKg * 2.0)
    }

    var todayCarbsConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalCarbs) }
    }

    var todayCarbsTarget: Int {
        if !todayMeals.isEmpty {
            let summed = todayMeals.reduce(into: 0.0) { $0 += $1.totalCarbs }
            return Int(summed)
        }
        // Fallback when no plan: ~45% of fallback-calorie target from carbs
        return Int(Double(todayCalorieTarget) * 0.45 / 4.0)
    }

    var todayFatConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalFat) }
    }

    var todayFatTarget: Int {
        if !todayMeals.isEmpty {
            let summed = todayMeals.reduce(into: 0.0) { $0 += $1.totalFat }
            return Int(summed)
        }
        // Fallback when no plan: ~25% of fallback-calorie target from fat
        return Int(Double(todayCalorieTarget) * 0.25 / 9.0)
    }

    // MARK: - Recovery-Adjusted Targets (Phase 4)

    // Whoop strain raises today's energy & carb needs. Recovery-poor days
    // tighten cals slightly to favour rest-day eating.

    /// Multiplier applied to base calorie target based on recovery + yesterday's strain.
    /// Range ~0.95 – 1.15. Falls back to 1.0 when no Whoop data is available.
    var recoveryCalorieMultiplier: Double {
        // Bias up on high strain (>14 = hard day yesterday → restock).
        let strainBoost: Double = if let cal = todayRecovery?.score {
            switch cal {
            case ..<34: -0.05 // poor recovery → eat less
            case 67...: 0.05 // good recovery → fuel a touch more
            default: 0
            }
        } else {
            0
        }
        return 1.0 + strainBoost
    }

    var recoveryAdjustedCalorieTarget: Int {
        Int(Double(todayCalorieTarget) * recoveryCalorieMultiplier)
    }

    /// Carbs absorb the bulk of the strain-driven calorie bump.
    var recoveryAdjustedCarbsTarget: Int {
        let baseCarbsCal = Double(todayCarbsTarget) * 4.0
        let extra = Double(recoveryAdjustedCalorieTarget - todayCalorieTarget)
        return Int((baseCarbsCal + extra) / 4.0)
    }

    /// Human-readable delta for UI (e.g. "+150 kcal for high strain").
    var recoveryAdjustmentLabel: String? {
        let delta = recoveryAdjustedCalorieTarget - todayCalorieTarget
        guard delta != 0 else {
            return nil
        }
        if delta > 0 {
            return "+\(delta) kcal for recovery"
        } else {
            return "\(delta) kcal for low recovery"
        }
    }

    var calorieProgress: Double {
        guard todayCalorieTarget > 0 else {
            return 0
        }
        return Double(todayCaloriesConsumed) / Double(todayCalorieTarget)
    }

    var hasProfile: Bool {
        dietaryProfile != nil
    }

    var sortedPresets: [MealPreset] {
        presets.sorted { $0.useCount > $1.useCount }
    }

    // MARK: - Load

    /// Look up the (single) UserSettings record so Plan generation can read
    /// trainingSplit + footballDays. Returns nil only on fresh installs that
    /// haven't completed onboarding — in which case the generator skips the
    /// schedule injection and falls back to its generic week.
    static func loadUserSettings(modelContext: ModelContext) -> UserSettings? {
        let descriptor = FetchDescriptor<UserSettings>()
        return try? modelContext.fetch(descriptor).first
    }

    func loadToday(modelContext: ModelContext) {
        loadState = .loading

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        // Fetch today's PlannedMeals. The `meal.mealPlan?.isActive == true`
        // clause is defense-in-depth: MealPlanGeneratorService now deletes
        // (not just deactivates) prior plans so cascade wipes their meals,
        // but if any orphan survives a future code path the filter prevents
        // ghost duplicates from polluting the Today view.
        do {
            let mealDescriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate<PlannedMeal> { meal in
                    meal.dayDate >= todayStart
                        && meal.dayDate < tomorrowStart
                        && meal.mealPlan?.isActive == true
                },
                sortBy: [SortDescriptor(\.mealNumber)]
            )
            todayMeals = try modelContext.fetch(mealDescriptor)
            refreshFeedbackPresence(modelContext: modelContext)

            // Fetch active WeeklyMealPlan
            let planDescriptor = FetchDescriptor<WeeklyMealPlan>(
                predicate: #Predicate<WeeklyMealPlan> { plan in
                    plan.isActive == true
                },
                sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
            )
            let plans = try modelContext.fetch(planDescriptor)
            weeklyPlan = plans.first

            // Fetch all presets
            let presetDescriptor = FetchDescriptor<MealPreset>(
                sortBy: [SortDescriptor(\.useCount, order: .reverse)]
            )
            presets = try modelContext.fetch(presetDescriptor)

            // Fetch dietary profile
            let profileDescriptor = FetchDescriptor<DietaryProfile>(
                predicate: #Predicate<DietaryProfile> { profile in
                    profile.isActive == true
                }
            )
            let profiles = try modelContext.fetch(profileDescriptor)
            dietaryProfile = profiles.first

            loadState = .loaded
        } catch {
            loadState = .error("Failed to load nutrition data: \(error.localizedDescription)")
        }
    }

    // MARK: - Meal Actions

    func markMealEaten(
        _ meal: PlannedMeal,
        at eatenAt: Date = Date(),
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) {
        let mealID = meal.id
        meal.status = .eaten
        meal.actualEatenAt = eatenAt

        // Shift any subsequent planned meals to maintain their original
        // gaps. Pure function — see `MealShiftPlanner` for the math and the
        // bedtime-cap compression rule.
        applyMealShift(
            eatenMealID: mealID,
            actualEatTime: eatenAt,
            modelContext: modelContext,
            notifications: notifications
        )

        try? modelContext.save()
        HapticManager.notification(.success)
        notifications?.cancelDefrostReminders(forMealID: mealID)
        notifications?.cancelPrepStartReminder(forMealID: mealID)
        notifications?.cancelOverdueMealReminder(forMealID: mealID)
        refreshTodayMeals(modelContext: modelContext)

        // Notify the day-plan engine: a meal eaten off its scheduled time
        // means subsequent free windows shifted, so the timeline copy
        // (especially meal-timing) is stale. DayPlanScheduler debounces.
        NotificationCenter.default.post(
            name: .tempoDayPlanReplanRequested,
            object: nil,
            userInfo: ["reason": DayPlanReason.mealEatenOffSchedule.rawValue]
        )
    }

    /// Recompute and persist shifted scheduled times for the remaining meals
    /// of the day, then reschedule prep-start / defrost / meal-reminder
    /// notifications for the shifted meals so the user gets accurate pings.
    private func applyMealShift(
        eatenMealID: UUID,
        actualEatTime: Date,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)?
    ) {
        let results = MealShiftPlanner.computeShift(
            todaysMeals: todayMeals,
            eatenMealID: eatenMealID,
            actualEatTime: actualEatTime
        )
        guard !results.isEmpty else {
            return
        }

        // Apply new scheduledTime and reschedule notifications for each shifted meal.
        let resultsByID = Dictionary(uniqueKeysWithValues: results.map { ($0.mealID, $0) })
        for meal in todayMeals {
            guard let r = resultsByID[meal.id] else {
                continue
            }
            meal.scheduledTime = r.newScheduledTime

            // Reschedule the per-meal reminder at the new time. Defrost,
            // prep-start, and overdue reminders are all tied to the meal
            // time; cancel + reschedule.
            notifications?.cancelDefrostReminders(forMealID: meal.id)
            notifications?.cancelPrepStartReminder(forMealID: meal.id)
            notifications?.cancelOverdueMealReminder(forMealID: meal.id)

            if r.newScheduledDate > Date() {
                notifications?.scheduleMealReminder(
                    mealName: meal.mealName,
                    time: r.newScheduledDate.addingTimeInterval(-5 * 60)
                )
                notifications?.scheduleOverdueMealReminder(
                    mealID: meal.id,
                    mealName: meal.mealName,
                    scheduledTime: r.newScheduledDate,
                    lateMinutes: 15
                )
                // Prep-start reminder uses the new meal time minus recipe lead.
                let prep = meal.recipe?.prepMinutes ?? 0
                let cook = meal.recipe?.cookMinutes ?? 0
                let leadMinutes = prep + cook
                if leadMinutes > 0,
                   let prepStart = Calendar.current.date(
                       byAdding: .minute,
                       value: -leadMinutes,
                       to: r.newScheduledDate
                   ),
                   prepStart > Date()
                {
                    notifications?.schedulePrepStartReminder(
                        mealID: meal.id,
                        mealName: meal.mealName,
                        prepStartDate: prepStart
                    )
                }
            }
        }
    }

    func markMealSkipped(
        _ meal: PlannedMeal,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) {
        let mealID = meal.id
        meal.status = .skipped
        try? modelContext.save()
        HapticManager.lightImpact()
        notifications?.cancelDefrostReminders(forMealID: mealID)
        notifications?.cancelPrepStartReminder(forMealID: mealID)
        notifications?.cancelOverdueMealReminder(forMealID: mealID)
        refreshTodayMeals(modelContext: modelContext)
    }

    // MARK: - Skip Redistribution (AI)

    /// Banner copy surfaced after a successful AI redistribution. Cleared
    /// by the view when dismissed. One sentence summarising the model's
    /// reasoning ("snack +200 kcal, dinner +150g protein — recovery is
    /// green, dinner alone can't absorb it").
    var lastRedistributionBanner: String?

    /// True while the redistribution call is in-flight. View shows a small
    /// spinner on the skipped card.
    var isRedistributing: Bool = false

    /// Run the AI redistribution for a just-skipped meal. Applies the
    /// per-meal additive deltas to the remaining `PlannedMeal`s in
    /// `todayMeals`, saves, and surfaces the model's reasoning via
    /// `lastRedistributionBanner`. Falls back to a deterministic
    /// proportional split when Claude is unreachable.
    func redistributeSkippedMacros(
        _ skipped: PlannedMeal,
        modelContext: ModelContext,
        apiClient: APIClient,
        recoveryScore: Double?,
        sleepHours: Double?,
        strain: Double?,
        dayType: String
    ) async {
        isRedistributing = true
        defer { isRedistributing = false }

        if redistributionService == nil {
            redistributionService = MealRedistributionService(apiClient: apiClient)
        }
        guard let redistribution = redistributionService else { return }

        let remaining = todayMeals.filter { $0.id != skipped.id }
        let result = await redistribution.redistribute(
            skipped: skipped,
            remaining: remaining,
            recoveryScore: recoveryScore,
            sleepHours: sleepHours,
            strain: strain,
            dayType: dayType
        )

        // Apply per-meal additive deltas.
        let byNumber = Dictionary(uniqueKeysWithValues: result.perMeal.map { ($0.mealNumber, $0) })
        for meal in todayMeals where meal.status == .planned {
            guard let delta = byNumber[meal.mealNumber] else { continue }
            meal.totalCalories += delta.addCalories
            meal.totalProtein += delta.addProtein
            meal.totalCarbs += delta.addCarbs
            meal.totalFat += delta.addFat
        }
        try? modelContext.save()
        refreshTodayMeals(modelContext: modelContext)

        let sourceTag = result.source == .ai ? "Coach" : "Fallback"
        lastRedistributionBanner = "\(sourceTag): \(result.reasoning)"
        HapticManager.notification(.success)
    }

    // MARK: - Presets

    func savePreset(name: String, items: [PlannedFood], mealType: MealType, modelContext: ModelContext) {
        let foodInputs = items.map { food in
            MealFoodItemInput(
                foodId: UUID().uuidString,
                name: food.name,
                brand: nil,
                servings: 1.0,
                servingSize: food.quantityGrams,
                servingUnit: "g",
                calories: food.calories,
                proteinGrams: food.proteinG,
                carbsGrams: food.carbsG,
                fatGrams: food.fatG,
                source: .manual
            )
        }

        let preset = MealPreset(
            name: name,
            foodItems: foodInputs,
            totalCalories: items.reduce(0) { $0 + $1.calories },
            totalProtein: items.reduce(0) { $0 + $1.proteinG },
            totalCarbs: items.reduce(0) { $0 + $1.carbsG },
            totalFat: items.reduce(0) { $0 + $1.fatG },
            mealType: mealType
        )
        modelContext.insert(preset)
        try? modelContext.save()
        presets.append(preset)
        HapticManager.notification(.success)
    }

    func logFromPreset(_ preset: MealPreset, modelContext: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let meal = PlannedMeal(
            dayDate: today,
            mealNumber: todayMeals.count + 1,
            mealName: preset.mealType.displayName,
            scheduledTime: timeFormatter.string(from: Date()),
            foods: preset.foodItems.map { input in
                PlannedFood(
                    name: input.name,
                    quantityGrams: input.servingSize,
                    calories: input.calories,
                    proteinG: input.proteinGrams,
                    carbsG: input.carbsGrams,
                    fatG: input.fatGrams
                )
            },
            totalCalories: preset.totalCalories,
            totalProtein: preset.totalProtein,
            totalCarbs: preset.totalCarbs,
            totalFat: preset.totalFat,
            status: .eaten,
            mealPlan: weeklyPlan
        )
        modelContext.insert(meal)
        preset.recordUse()
        try? modelContext.save()
        todayMeals.append(meal)
        HapticManager.notification(.success)
    }

    // MARK: - Generate Plan

    func generatePlan(
        modelContext: ModelContext,
        whoop: any WhoopServiceProtocol,
        apiClient: APIClient,
        notifications: (any NotificationServiceProtocol)? = nil,
        intake: MealPlanIntake? = nil
    ) {
        guard let profile = dietaryProfile else {
            return
        }

        isGeneratingPlan = true
        planGenerationError = nil
        HapticManager.lightImpact()

        planGenerationTask?.cancel()
        planGenerationTask = Task {
            do {
                // Per INTELLIGENCE_REMEDIATION_PLAN.md §3 — Claude calls proxy
                // through the backend; the generator needs the auth-attaching
                // APIClient instead of the deleted ClaudeAPIClient.
                let generator = MealPlanGeneratorService(apiClient: apiClient)

                // Fetch Whoop TDEE if available
                var whoopTDEE: Double?
                if let cycle = try? await whoop.fetchCycle(for: Date()) {
                    whoopTDEE = cycle.caloriesBurned
                }

                // Enrich the intake with the user's actual weekly training
                // schedule from UserSettings so the AI generates day-types
                // that match Mon=Upper / Wed=Football reality rather than
                // a generic "Wed strength / Thu cardio" guess.
                var enrichedIntake = intake ?? .default
                if let settings = Self.loadUserSettings(modelContext: modelContext) {
                    enrichedIntake.trainingSchedule = WeeklyTrainingSchedule.make(
                        split: settings.trainingSplit,
                        footballDays: settings.footballDays
                    )
                }

                let plan = try await generator.generateWeeklyPlan(
                    profile: profile,
                    whoopTDEE: whoopTDEE,
                    modelContext: modelContext,
                    intake: enrichedIntake,
                    onStatus: { [weak self] state in
                        self?.planGenerationStatusLabel = state.statusLabel
                    }
                )

                weeklyPlan = plan
                if let notifications {
                    scheduleDefrostReminders(for: plan, notifications: notifications)
                }
                pantryGapAlert = computePantryGap(for: plan, modelContext: modelContext)
                // Auto-build the grocery list now so the user doesn't have to
                // hunt for a Generate button after the plan lands. Non-fatal:
                // failures surface via groceryState.lastError, not the plan UI.
                generateGroceryList()
                isGeneratingPlan = false
                planGenerationStatusLabel = ""
                HapticManager.notification(.success)
                loadToday(modelContext: modelContext)
            } catch {
                isGeneratingPlan = false
                planGenerationStatusLabel = ""
                planGenerationError = error.localizedDescription
                HapticManager.notification(.error)
            }
        }
    }

    /// Compute the set of canonical ingredient names referenced by the plan that
    /// aren't present in the user's pantry. Returns nil when there's nothing
    /// missing — the view should suppress the alert in that case.
    private func computePantryGap(
        for plan: WeeklyMealPlan,
        modelContext: ModelContext
    ) -> PantryGapAlert? {
        // Snapshot pantry canonical names (in-stock items only).
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false && item.quantity > 0
            }
        )
        let pantryNames: Set<String> = ((try? modelContext.fetch(descriptor)) ?? [])
            .map(\.canonicalName)
            .reduce(into: Set<String>()) { acc, name in
                acc.insert(name.lowercased())
            }

        // Collect every distinct ingredient referenced by the plan's recipes.
        var needed: Set<String> = []
        for meal in plan.meals ?? [] {
            for ingredient in meal.recipe?.ingredients ?? [] {
                needed.insert(ingredient.canonicalFoodName.lowercased())
            }
        }

        let missing = needed.subtracting(pantryNames).sorted()
        guard !missing.isEmpty else {
            return nil
        }
        return PantryGapAlert(missingIngredients: missing)
    }

    /// Walk every PlannedMeal in `plan`, find ingredients that require a defrost
    /// reminder, and schedule a Time Sensitive notification at `mealTime − leadTime`.
    ///
    /// Clears EVERY pending defrost reminder first via `cancelCategory` so that
    /// a regenerated plan doesn't leak stale reminders from prior plans whose
    /// meals were deactivated but kept around as historical records (their
    /// PlannedMeal.id values are not in the new plan, so per-meal cancellation
    /// would miss them).
    private func scheduleDefrostReminders(
        for plan: WeeklyMealPlan,
        notifications: any NotificationServiceProtocol
    ) {
        notifications.cancelCategory("DEFROST_REMINDER")
        notifications.cancelCategory("PREP_START_REMINDER")
        notifications.cancelCategory("OVERDUE_MEAL_REMINDER")
        let calendar = Calendar.current
        let now = Date()
        for meal in plan.meals ?? [] {
            let mealTime = MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar)

            // Prep-start reminder — fires when it's time to start cooking.
            let prepStart = MealScheduleHelpers.prepStartDate(for: meal, calendar: calendar)
            if prepStart > now, prepStart != mealTime {
                notifications.schedulePrepStartReminder(
                    mealID: meal.id,
                    mealName: meal.mealName,
                    prepStartDate: prepStart
                )
            }

            // Overdue check-in — fires 15min past mealTime if the meal is still
            // unmarked. Cancelled by markMealEaten/markMealSkipped.
            if mealTime > now {
                notifications.scheduleOverdueMealReminder(
                    mealID: meal.id,
                    mealName: meal.mealName,
                    scheduledTime: mealTime,
                    lateMinutes: 15
                )
            }

            // Defrost reminders — one per freezer ingredient.
            guard let ingredients = meal.recipe?.ingredients else {
                continue
            }
            for ingredient in ingredients where ingredient.requiresDefrostReminder {
                let lead = ingredient.defrostLeadTimeHours
                guard let fireDate = calendar.date(byAdding: .hour, value: -lead, to: mealTime) else {
                    continue
                }
                // Skip reminders that would fire in the past (meal in <leadTime).
                guard fireDate > now else {
                    continue
                }
                notifications.scheduleDefrostReminder(
                    mealID: meal.id,
                    ingredientID: ingredient.id,
                    ingredientName: ingredient.displayName,
                    mealName: meal.mealName,
                    leadTimeHours: lead,
                    fireDate: fireDate
                )
            }
        }
    }

    // MARK: - Wizard Snapshot Builder

    /// Builds the launch snapshot the intake wizard needs to decide which steps to surface.
    /// Pantry state, Whoop yesterday's recovery, and basic profile reference. Never throws —
    /// any failure degrades to a "missing" field rather than blocking the wizard.
    func buildWizardSnapshot(
        modelContext: ModelContext,
        whoop: any WhoopServiceProtocol
    ) async -> WizardLaunchSnapshot {
        // Pantry snapshot
        let pantrySnapshot: PantrySnapshot
        let service = pantryService ?? LocalPantryService(modelContext: modelContext)
        if let items = try? service.fetchAll() {
            let mostRecent = items.map(\.updatedAt).max()
            pantrySnapshot = PantrySnapshot(itemCount: items.count, mostRecentUpdate: mostRecent)
        } else {
            pantrySnapshot = PantrySnapshot(itemCount: 0, mostRecentUpdate: nil)
        }

        // Whoop snapshot — non-throw == connected
        var whoopSnapshot: WhoopSnapshot?
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        if let recovery = try? await whoop.fetchRecovery(for: yesterday) {
            whoopSnapshot = WhoopSnapshot(recoveryScore: recovery.score)
        }

        return WizardLaunchSnapshot(
            pantry: pantrySnapshot,
            whoop: whoopSnapshot
        )
    }

    // MARK: - Meal Suggestions

    func getMealSuggestions(apiClient: APIClient) {
        isLoadingMealSuggestions = true
        mealSuggestionError = nil
        HapticManager.lightImpact()

        if coachService == nil {
            coachService = NutritionCoachService(apiClient: apiClient)
        }

        let remainingCal = Double(max(0, todayCalorieTarget - todayCaloriesConsumed))
        let remainingProtein = Double(max(0, todayProteinTarget - todayProteinConsumed))
        let remainingCarbs = Double(max(0, todayCarbsTarget - todayCarbsConsumed))
        let remainingFat = Double(max(0, todayFatTarget - todayFatConsumed))

        let budget = MacroBudget(
            caloriesRemaining: remainingCal,
            proteinRemaining: remainingProtein,
            carbsRemaining: remainingCarbs,
            fatRemaining: remainingFat,
            calorieTarget: Double(todayCalorieTarget),
            proteinTarget: Double(todayProteinTarget),
            carbsTarget: Double(todayCarbsTarget),
            fatTarget: Double(todayFatTarget)
        )

        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = if hour < 11 {
            "morning"
        } else if hour < 15 {
            "afternoon"
        } else if hour < 19 {
            "evening"
        } else {
            "night"
        }

        // Determine if training day based on today's plan meals count
        let isTrainingDay = !todayMeals.isEmpty

        mealSuggestionsTask?.cancel()
        guard let coach = coachService else {
            isLoadingMealSuggestions = false
            mealSuggestionError = "Coach unavailable"
            return
        }
        mealSuggestionsTask = Task { [coach] in
            do {
                let suggestions = try await coach.mealSuggestions(
                    remainingBudget: budget,
                    timeOfDay: timeOfDay,
                    isTrainingDay: isTrainingDay
                )
                mealSuggestions = suggestions
                isLoadingMealSuggestions = false
                HapticManager.notification(.success)
            } catch {
                isLoadingMealSuggestions = false
                mealSuggestionError = error.localizedDescription
                HapticManager.notification(.error)
            }
        }
    }

    // MARK: - Meal Reminders (Phase 4)

    // Schedule a local notification 5min before each planned meal's
    // scheduled time. Skips meals already eaten/skipped/delayed.

    func scheduleMealReminders(notifications: any NotificationServiceProtocol, calendar: Calendar = .current) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let today = calendar.startOfDay(for: Date())
        for meal in todayMeals where meal.status == .planned {
            guard let time = formatter.date(from: meal.scheduledTime) else {
                continue
            }
            let comps = calendar.dateComponents([.hour, .minute], from: time)
            guard let scheduled = calendar.date(
                bySettingHour: comps.hour ?? 0,
                minute: comps.minute ?? 0,
                second: 0,
                of: today
            )
            else {
                continue
            }
            let fire = scheduled.addingTimeInterval(-5 * 60)
            // Avoid scheduling already-past reminders.
            guard fire > Date() else {
                continue
            }
            notifications.scheduleMealReminder(mealName: meal.mealName, time: fire)
        }
    }

    // MARK: - Recovery Data

    func loadRecoveryData(whoop: any WhoopServiceProtocol) {
        isLoadingRecovery = true

        recoveryLoadTask?.cancel()
        recoveryLoadTask = Task {
            // Fetch recovery and sleep independently so a sleep failure
            // doesn't blank the recovery quadrant. Errors on either path
            // are logged rather than silently mapped to nil.
            do {
                todayRecovery = try await whoop.fetchRecovery(for: Date())
            } catch is CancellationError {
                isLoadingRecovery = false
                return
            } catch {
                Logger.nutrition.warning("Whoop recovery fetch failed: \(error.localizedDescription, privacy: .public)")
                todayRecovery = nil
            }
            do {
                todaySleep = try await whoop.fetchSleep(for: Date())
            } catch is CancellationError {
                isLoadingRecovery = false
                return
            } catch {
                Logger.nutrition.warning("Whoop sleep fetch failed: \(error.localizedDescription, privacy: .public)")
                todaySleep = nil
            }
            isLoadingRecovery = false
        }
    }

    var recoveryScore: Double? {
        todayRecovery?.score
    }

    var recoveryZone: String? {
        guard let score = recoveryScore else {
            return nil
        }
        if score >= 67 {
            return "green"
        } else if score >= 34 {
            return "yellow"
        } else {
            return "red"
        }
    }

    // MARK: - Private

    private func refreshTodayMeals(modelContext: ModelContext) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        do {
            let descriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate<PlannedMeal> { meal in
                    meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
                },
                sortBy: [SortDescriptor(\.mealNumber)]
            )
            todayMeals = try modelContext.fetch(descriptor)
            refreshFeedbackPresence(modelContext: modelContext)
        } catch {
            // Silent refresh failure
        }
    }

    /// Rebuild `feedbackPresence` against the current `todayMeals`. Cheap
    /// (one fetch + dictionary build) and called from both `loadToday` and
    /// `refreshTodayMeals` so the UI always reflects the latest review
    /// state. Internal because the feedback sheet calls it via its
    /// onDismiss to clear the "review pending" badge immediately.
    func refreshFeedbackPresence(modelContext: ModelContext) {
        let mealIDs = Set(todayMeals.map(\.id))
        guard !mealIDs.isEmpty else {
            feedbackPresence = [:]
            return
        }
        // Predicate body can only hold a single expression and can't unwrap
        // optionals inline. Fetching all rows and filtering in-memory is
        // fine here — feedback volume is bounded by meals-per-week.
        let descriptor = FetchDescriptor<MealFeedback>()
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        var presence: [UUID: Bool] = [:]
        for row in rows {
            if let pid = row.plannedMeal?.id, mealIDs.contains(pid) {
                presence[pid] = true
            }
        }
        feedbackPresence = presence
    }

    // MARK: - Test Hooks (Phase 4)

    #if DEBUG
        /// Test-only setter for today's planned meals. NOT for production code.
        func _testSetTodayMeals(_ meals: [PlannedMeal]) {
            todayMeals = meals
        }

        /// Test-only setter for today's Whoop recovery data. NOT for production code.
        func _testSetTodayRecovery(_ recovery: WhoopRecoveryData?) {
            todayRecovery = recovery
        }
    #endif
}
