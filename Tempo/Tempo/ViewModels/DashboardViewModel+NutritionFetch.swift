//
// DashboardViewModel+NutritionFetch.swift
// Tempo
//
// Created by Tempo on 12/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - NutritionTotalsToday

/// Snapshot returned by `DashboardViewModel.fetchNutritionTotalsForToday()`.
/// Carries logged macros + today's targets + the next upcoming `PlannedMeal`
/// used by the Fuel quadrant card.
struct NutritionTotalsToday {
    var calories: Int = 0
    var protein: Int = 0
    var carbs: Int = 0
    var fat: Int = 0
    var mealsLogged: Int = 0
    var mealsPlanned: Int?
    var calorieTarget: Int = 0
    var proteinTarget: Int = 0
    var carbsTarget: Int = 0
    var fatTarget: Int = 0
    var nextMeal: PlannedMeal?
}

// MARK: - DashboardViewModel fetch helper

extension DashboardViewModel {
    /// Pull today's logged macros, active nutrition target, and the next
    /// upcoming `PlannedMeal` from SwiftData. Used by `refresh()` to assemble
    /// the Fuel quadrant. Returns zero-values when no model context is bound.
    func fetchNutritionTotalsForToday() -> NutritionTotalsToday {
        guard let context = fuelContext else {
            return NutritionTotalsToday()
        }
        var totals = NutritionTotalsToday()
        let todayStart = Calendar.current.startOfDay(for: Date())
        let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        let mealDescriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { log in
                log.dayDate >= todayStart && log.dayDate < tomorrowStart
            }
        )
        if let logs = try? context.fetch(mealDescriptor) {
            totals.mealsLogged = logs.count
            totals.calories = Int(logs.reduce(0.0) { $0 + $1.totalCalories })
            totals.protein = Int(logs.reduce(0.0) { $0 + $1.totalProtein })
            totals.carbs = Int(logs.reduce(0.0) { $0 + $1.totalCarbs })
            totals.fat = Int(logs.reduce(0.0) { $0 + $1.totalFat })
        }

        let targetDescriptor = FetchDescriptor<NutritionTarget>(
            predicate: #Predicate<NutritionTarget> { t in t.isActive == true },
            sortBy: [SortDescriptor(\.effectiveFrom, order: .reverse)]
        )
        if let target = (try? context.fetch(targetDescriptor))?.first {
            totals.calorieTarget = target.calorieTarget
            totals.proteinTarget = target.proteinTargetGrams
            totals.carbsTarget = target.carbsTargetGrams
            totals.fatTarget = target.fatTargetGrams
            totals.mealsPlanned = target.mealsPerDay
        }

        let plannedDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
            },
            sortBy: [SortDescriptor(\.mealNumber)]
        )
        if let plannedMeals = try? context.fetch(plannedDescriptor) {
            totals.nextMeal = MealScheduleHelpers.nextUpcomingMeal(in: plannedMeals)
        }

        return totals
    }
}
