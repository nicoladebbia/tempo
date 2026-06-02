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
    func fetchNutritionTotalsForToday(whoopAvgTDEE: Double? = nil) -> NutritionTotalsToday {
        guard let context = fuelContext else {
            return NutritionTotalsToday()
        }
        var totals = NutritionTotalsToday()
        totals.isConnected = true
        let todayStart = Calendar.current.startOfDay(for: Date())
        let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        // CONSUMED macros come from EATEN PlannedMeals — the exact same
        // source the Nutrition tab's todayCaloriesConsumed uses. Previously
        // the Dashboard summed MealLog.totalCalories instead, which diverged
        // from the tab: Mark Eaten flips PlannedMeal.status = .eaten without
        // creating a MealLog, so a marked-eaten meal counted on the tab but
        // not the Dashboard. Macro rebalance + 5-day carryover also write
        // PlannedMeal, never MealLog — three systems on PlannedMeal, the
        // Dashboard was the lone outlier. Now all surfaces agree.
        // (See the targets comment below — this closes the consumed half of
        // that same "two surfaces, two numbers" bug.)
        // The eaten-meal sum + lastEatenAt are computed in the PlannedMeal
        // fetch block below.

        // Targets come from NutritionTargetCalculator — the SAME helper
        // Nutrition Today uses — so the two surfaces never disagree on the
        // calorie / macro target. Previously this read NutritionTarget (a
        // SwiftData record left over from an earlier architecture, holding
        // onboarding-time defaults like 2,400), while Nutrition Today
        // summed PlannedMeal.totalCalories from the active plan (~3,536).
        // Same user, same day, two different numbers. Fixed by the shared
        // calculator.
        let targets = NutritionTargetCalculator.targetsForToday(in: context, whoopAvgTDEE: whoopAvgTDEE)
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

            // Consumed macros = eaten PlannedMeals (matches the Nutrition
            // tab exactly). A Quick Log without an active plan still creates
            // a synthetic .eaten PlannedMeal, so plan-less logs are counted
            // here too.
            let eaten = plannedMeals.filter { $0.status == .eaten }
            totals.mealsLogged = eaten.count
            totals.calories = Int(eaten.reduce(0.0) { $0 + $1.totalCalories })
            totals.protein = Int(eaten.reduce(0.0) { $0 + $1.totalProtein })
            totals.carbs = Int(eaten.reduce(0.0) { $0 + $1.totalCarbs })
            totals.fat = Int(eaten.reduce(0.0) { $0 + $1.totalFat })

            // Last-eaten timestamp from PlannedMeal.actualEatenAt (Mark
            // Eaten + Quick Log both set it).
            totals.lastEatenAt = eaten.compactMap(\.actualEatenAt).max()
        }

        return totals
    }
}
