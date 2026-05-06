import Foundation
import SwiftData
import SwiftUI

// MARK: - Nutrition Section

enum NutritionSection: String, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case plan = "Plan"
    case log = "Log"
    case coach = "Coach"

    var id: String { rawValue }
}

// MARK: - Nutrition Load State

enum NutritionLoadState: Sendable {
    case loading
    case loaded
    case error(String)
}

// MARK: - Nutrition Tab ViewModel

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
        guard let profile = dietaryProfile else { return 2400 }
        // Base estimate from Mifflin-St Jeor + activity
        let bmr: Double
        if profile.biologicalSex == .male {
            bmr = 10 * profile.currentWeightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) + 5
        } else {
            bmr = 10 * profile.currentWeightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) - 161
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
        guard let profile = dietaryProfile else { return 180 }
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
        return Int(Double(todayCalorieTarget) * 0.45 / 4.0)
    }

    var todayFatConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalFat) }
    }

    var todayFatTarget: Int {
        // ~25% of calories from fat
        return Int(Double(todayCalorieTarget) * 0.25 / 9.0)
    }

    var calorieProgress: Double {
        guard todayCalorieTarget > 0 else { return 0 }
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
        guard let profile = dietaryProfile else { return }

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
        let timeOfDay: String
        if hour < 11 { timeOfDay = "morning" }
        else if hour < 15 { timeOfDay = "afternoon" }
        else if hour < 19 { timeOfDay = "evening" }
        else { timeOfDay = "night" }

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
        guard let score = recoveryScore else { return nil }
        if score >= 67 { return "green" }
        else if score >= 34 { return "yellow" }
        else { return "red" }
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
}
