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
    /// Most recent eat-time across today's `MealLog.loggedAt` and
    /// `PlannedMeal.actualEatenAt`. Drives the "Last meal Xh ago" line
    /// in the Fuel card (Phase 5). Nil when nothing eaten today.
    var lastEatenAt: Date?
    /// `false` when no `ModelContext` has been bound yet (zeros are
    /// "not connected", not "no consumption"). Views can use this to
    /// differentiate empty-state UI from "0 consumed" UI.
    var isConnected: Bool = false
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
        totals.isConnected = true
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
            totals.lastEatenAt = logs.map(\.loggedAt).max()
        }

        // Targets come from NutritionTargetCalculator — the SAME helper
        // Nutrition Today uses — so the two surfaces never disagree on the
        // calorie / macro target. Previously this read NutritionTarget (a
        // SwiftData record left over from an earlier architecture, holding
        // onboarding-time defaults like 2,400), while Nutrition Today
        // summed PlannedMeal.totalCalories from the active plan (~3,536).
        // Same user, same day, two different numbers. Fixed by the shared
        // calculator.
        let targets = NutritionTargetCalculator.targetsForToday(in: context)
        totals.calorieTarget = targets.calories
        totals.proteinTarget = targets.protein
        totals.carbsTarget = targets.carbs
        totals.fatTarget = targets.fat
        // mealsPlanned stays from NutritionTarget for now — it's an
        // onboarding setting, not a derived value, and no other surface
        // sources it. If we ever rebuild meal-count-per-day from the plan
        // itself, switch this too.
        let mealsPerDayDescriptor = FetchDescriptor<NutritionTarget>(
            predicate: #Predicate<NutritionTarget> { t in t.isActive == true },
            sortBy: [SortDescriptor(\.effectiveFrom, order: .reverse)]
        )
        if let target = (try? context.fetch(mealsPerDayDescriptor))?.first {
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
            // Roll planned-meal actualEatenAt into the last-eaten signal —
            // Mark Eaten taps land on PlannedMeal, not MealLog, so without
            // this the Fuel card would say "—" right after the user marked
            // breakfast as eaten.
            let plannedLast = plannedMeals.compactMap(\.actualEatenAt).max()
            if let plannedLast {
                totals.lastEatenAt = max(totals.lastEatenAt ?? plannedLast, plannedLast)
            }
        }

        return totals
    }
}
