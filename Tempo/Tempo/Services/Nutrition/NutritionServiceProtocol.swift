//
// NutritionServiceProtocol.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - NutritionServiceProtocol

// Composes food search, meal logging, and photo analysis sub-services.

protocol NutritionServiceProtocol: Sendable {
    var foodSearch: any FoodSearchServiceProtocol { get }
    var mealLogging: any MealLoggingServiceProtocol { get }
    var photoAnalysis: any PhotoAnalysisServiceProtocol { get }

    func activeTarget(context: ModelContext) -> ActiveNutritionTarget?
    func remainingBudget(context: ModelContext) -> MacroBudget
}

// MARK: - NutritionService

@Observable
final class NutritionService: NutritionServiceProtocol, @unchecked Sendable {
    let foodSearch: any FoodSearchServiceProtocol
    let mealLogging: any MealLoggingServiceProtocol
    let photoAnalysis: any PhotoAnalysisServiceProtocol

    init(
        foodSearch: any FoodSearchServiceProtocol,
        mealLogging: any MealLoggingServiceProtocol,
        photoAnalysis: any PhotoAnalysisServiceProtocol
    ) {
        self.foodSearch = foodSearch
        self.mealLogging = mealLogging
        self.photoAnalysis = photoAnalysis
    }

    // MARK: - Active Target

    // Reads from DailySnapshot targets (set during onboarding or profile settings).

    func activeTarget(context: ModelContext) -> ActiveNutritionTarget? {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<DailySnapshot> { snapshot in
            snapshot.date == startOfDay
        }
        let descriptor = FetchDescriptor<DailySnapshot>(predicate: predicate)

        guard let snapshot = try? context.fetch(descriptor).first else {
            return nil
        }

        guard let calTarget = snapshot.calorieTarget,
              let proTarget = snapshot.proteinTarget,
              let carbTarget = snapshot.carbsTarget,
              let fatTarget = snapshot.fatTarget
        else {
            return nil
        }

        return ActiveNutritionTarget(
            calories: Double(calTarget),
            proteinGrams: proTarget,
            carbsGrams: carbTarget,
            fatGrams: fatTarget,
            mealsPerDay: snapshot.mealsPlanned
        )
    }

    // MARK: - Remaining Budget

    func remainingBudget(context: ModelContext) -> MacroBudget {
        guard let target = activeTarget(context: context) else {
            return .empty
        }

        let summary = mealLogging.todaySummary(context: context)

        return MacroBudget(
            caloriesRemaining: target.calories - summary.totalCalories,
            proteinRemaining: target.proteinGrams - summary.totalProtein,
            carbsRemaining: target.carbsGrams - summary.totalCarbs,
            fatRemaining: target.fatGrams - summary.totalFat,
            calorieTarget: target.calories,
            proteinTarget: target.proteinGrams,
            carbsTarget: target.carbsGrams,
            fatTarget: target.fatGrams
        )
    }

    // MARK: - Factory

    static func live(healthKit: any HealthKitServiceProtocol, apiClient: APIClient) -> NutritionService {
        let foodSearch = FoodSearchService()
        let mealLogging = MealLoggingService(healthKit: healthKit)
        // Per INTELLIGENCE_REMEDIATION_PLAN.md §3 — photo analysis now proxies
        // through the backend instead of calling Anthropic directly.
        let photoAnalysis = PhotoAnalysisService(foodSearch: foodSearch, apiClient: apiClient)
        return NutritionService(
            foodSearch: foodSearch,
            mealLogging: mealLogging,
            photoAnalysis: photoAnalysis
        )
    }
}
