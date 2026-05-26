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
    /// Last-7-days kcal totals (one entry per day, today inclusive,
    /// chronologically ordered). Empty when no MealLog rows exist.
    /// Drives the Fuel quadrant trend chart — replaces the previous
    /// hardcoded `[2250, 2100, 2500, ...]` stub.
    var caloriesLast7Days: [(date: Date, calories: Int)] = []
    /// Average daily kcal across days that had >=1 logged meal in the
    /// 7-day window. Nil when the window is fully empty.
    var weeklyAverageCalories: Int?
    /// Average daily protein (g) across the same non-empty days.
    var weeklyAverageProtein: Int?
    /// % of non-empty days where logged kcal landed in 80–120% of the
    /// target. Nil when no logged days exist in the window.
    var weeklyCompliancePercent: Int?
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
        }

        // 7-day kcal trend + weekly averages from MealLog. Reads the
        // actual history (MealLog rows survive plan regens — PlannedMeal
        // doesn't, so we can't aggregate from there). Empty days are
        // included as (date, 0) so the chart bars line up across the week
        // even on days the user didn't eat.
        let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let weekDescriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { log in
                log.dayDate >= weekStart && log.dayDate < tomorrowStart
            }
        )
        if let weekLogs = try? context.fetch(weekDescriptor) {
            // Group by dayDate (already normalized to midnight in MealLog.init).
            var byDay: [Date: (cal: Double, prot: Double)] = [:]
            for log in weekLogs {
                let day = Calendar.current.startOfDay(for: log.dayDate)
                byDay[day, default: (0, 0)].cal += log.totalCalories
                byDay[day, default: (0, 0)].prot += log.totalProtein
            }

            var trend: [(date: Date, calories: Int)] = []
            for offset in (-6 ... 0) {
                if let day = Calendar.current.date(byAdding: .day, value: offset, to: todayStart) {
                    let kcal = Int(byDay[day]?.cal ?? 0)
                    trend.append((date: day, calories: kcal))
                }
            }
            totals.caloriesLast7Days = trend

            let nonEmpty = byDay.values.filter { $0.cal > 0 }
            // Require >=4 logged days before showing weekly aggregates.
            // A "weekly average" from 1 day is misleading; drill-sergeant
            // tone favors honest "—" over a confident-wrong number.
            if nonEmpty.count >= 4 {
                let avgCal = nonEmpty.reduce(0.0) { $0 + $1.cal } / Double(nonEmpty.count)
                let avgProt = nonEmpty.reduce(0.0) { $0 + $1.prot } / Double(nonEmpty.count)
                totals.weeklyAverageCalories = Int(avgCal)
                totals.weeklyAverageProtein = Int(avgProt)

                // Compliance = (days in 80–120% of target) / 7. Missed
                // days count as failures, not "neutral non-events" — this
                // matches the app's accountability tone. Per-day targets
                // aren't versioned yet, so today's target is the reference
                // for all 7 days in the window.
                if totals.calorieTarget > 0 {
                    let lower = Double(totals.calorieTarget) * 0.8
                    let upper = Double(totals.calorieTarget) * 1.2
                    let compliant = nonEmpty.filter { $0.cal >= lower && $0.cal <= upper }.count
                    totals.weeklyCompliancePercent = Int(Double(compliant) / 7.0 * 100)
                }
            }
        }

        return totals
    }
}
