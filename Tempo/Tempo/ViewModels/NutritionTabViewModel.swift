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

    func markMealEaten(_ meal: PlannedMeal, modelContext: ModelContext) {
        meal.status = .eaten
        try? modelContext.save()
        HapticManager.notification(.success)
        refreshTodayMeals(modelContext: modelContext)
    }

    func markMealSkipped(_ meal: PlannedMeal, modelContext: ModelContext) {
        meal.status = .skipped
        try? modelContext.save()
        HapticManager.lightImpact()
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

    func generatePlan(modelContext: ModelContext, whoop: any WhoopServiceProtocol) {
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
                    modelContext: modelContext
                )

                weeklyPlan = plan
                isGeneratingPlan = false
                HapticManager.notification(.success)
                loadToday(modelContext: modelContext)
            } catch {
                isGeneratingPlan = false
                planGenerationError = error.localizedDescription
                HapticManager.notification(.error)
            }
        }
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
