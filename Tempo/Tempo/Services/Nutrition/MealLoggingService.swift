//
// MealLoggingService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - MealLoggingServiceProtocol

// Legacy MealLog service. Its write paths (logMeal / updateMeal / deleteMeal
// / HealthKit sync) had no callers and were removed — every log now goes
// through EatenMealRecorder onto PlannedMeal. What's left is `todaySummary`,
// kept ONLY because NutritionService.remainingBudget (itself uncalled) still
// references it; it reads DailySnapshot targets nothing writes. Delete this
// whole service together with remainingBudget/activeTarget.

protocol MealLoggingServiceProtocol: Sendable {
    func todaySummary(context: ModelContext) -> DailyNutritionSummary
}

// MARK: - MealLoggingService

@Observable
final class MealLoggingService: MealLoggingServiceProtocol, @unchecked Sendable {
    private let logger = Logger.nutrition

    /// `healthKit` is accepted for source compatibility with
    /// `NutritionService.live`; nothing here writes to HealthKit any more.
    init(healthKit _: any HealthKitServiceProtocol) {}

    // MARK: - Today Summary

    func todaySummary(context: ModelContext) -> DailyNutritionSummary {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<MealLog> { meal in
            meal.dayDate == startOfDay
        }
        let meals: [MealLog]
        do {
            meals = try context.fetch(FetchDescriptor<MealLog>(predicate: predicate))
        } catch {
            logger.error("Failed to fetch meals: \(error.localizedDescription)")
            meals = []
        }

        let totalCal = meals.reduce(0.0) { $0 + $1.totalCalories }
        let totalPro = meals.reduce(0.0) { $0 + $1.totalProtein }
        let totalCarbs = meals.reduce(0.0) { $0 + $1.totalCarbs }
        let totalFat = meals.reduce(0.0) { $0 + $1.totalFat }

        // Fetch targets from DailySnapshot if available
        let snapshotPredicate = #Predicate<DailySnapshot> { snapshot in
            snapshot.date == startOfDay
        }
        let snapshotDescriptor = FetchDescriptor<DailySnapshot>(predicate: snapshotPredicate)
        let snapshot = try? context.fetch(snapshotDescriptor).first

        return DailyNutritionSummary(
            date: startOfDay,
            totalCalories: totalCal,
            totalProtein: totalPro,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            mealsLogged: meals.count,
            calorieTarget: snapshot?.calorieTarget.map { Double($0) },
            proteinTarget: snapshot?.proteinTarget,
            carbsTarget: snapshot?.carbsTarget,
            fatTarget: snapshot?.fatTarget
        )
    }
}
