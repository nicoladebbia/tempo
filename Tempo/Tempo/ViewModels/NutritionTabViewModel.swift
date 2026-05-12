//
// NutritionTabViewModel.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
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
    // MARK: - State

    private(set) var loadState: NutritionLoadState = .loading
    var selectedTab: NutritionSection = .today

    // MARK: - Data

    private(set) var todayMeals: [PlannedMeal] = []
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
        guard let profile = dietaryProfile else {
            return 2400
        }
        // Base estimate from Mifflin-St Jeor + activity
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
        // ~45% of calories from carbs
        Int(Double(todayCalorieTarget) * 0.45 / 4.0)
    }

    var todayFatConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalFat) }
    }

    var todayFatTarget: Int {
        // ~25% of calories from fat
        Int(Double(todayCalorieTarget) * 0.25 / 9.0)
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

    func loadToday(modelContext: ModelContext) {
        loadState = .loading

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        // Fetch today's PlannedMeals
        do {
            let mealDescriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate<PlannedMeal> { meal in
                    meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
                },
                sortBy: [SortDescriptor(\.mealNumber)]
            )
            todayMeals = try modelContext.fetch(mealDescriptor)

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
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) {
        let mealID = meal.id
        meal.status = .eaten
        try? modelContext.save()
        HapticManager.notification(.success)
        notifications?.cancelDefrostReminders(forMealID: mealID)
        notifications?.cancelPrepStartReminder(forMealID: mealID)
        refreshTodayMeals(modelContext: modelContext)
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
        refreshTodayMeals(modelContext: modelContext)
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
        notifications: (any NotificationServiceProtocol)? = nil,
        intake: MealPlanIntake? = nil
    ) {
        guard let profile = dietaryProfile else {
            return
        }

        isGeneratingPlan = true
        planGenerationError = nil
        HapticManager.lightImpact()

        Task {
            do {
                let generator = MealPlanGeneratorService()

                // Fetch Whoop TDEE if available
                var whoopTDEE: Double?
                if let cycle = try? await whoop.fetchCycle(for: Date()) {
                    whoopTDEE = cycle.caloriesBurned
                }

                let plan = try await generator.generateWeeklyPlan(
                    profile: profile,
                    whoopTDEE: whoopTDEE,
                    modelContext: modelContext,
                    intake: intake,
                    onStatus: { [weak self] state in
                        self?.planGenerationStatusLabel = state.statusLabel
                    }
                )

                weeklyPlan = plan
                if let notifications {
                    scheduleDefrostReminders(for: plan, notifications: notifications)
                }
                pantryGapAlert = computePantryGap(for: plan, modelContext: modelContext)
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

    func getMealSuggestions() {
        isLoadingMealSuggestions = true
        mealSuggestionError = nil
        HapticManager.lightImpact()

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

        Task {
            do {
                let coachService = NutritionCoachService()
                let suggestions = try await coachService.mealSuggestions(
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

        Task {
            do {
                let recovery = try await whoop.fetchRecovery(for: Date())
                todayRecovery = recovery

                let sleep = try? await whoop.fetchSleep(for: Date())
                todaySleep = sleep

                isLoadingRecovery = false
            } catch {
                // Whoop not connected or no data — silent failure
                isLoadingRecovery = false
            }
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
        } catch {
            // Silent refresh failure
        }
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
