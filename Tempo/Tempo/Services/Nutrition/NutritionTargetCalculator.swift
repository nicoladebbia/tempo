//
// NutritionTargetCalculator.swift
// Tempo
//
// Shared today-target logic used by BOTH the Nutrition tab and the
// Dashboard's Fuel quadrant. Without this, each surface computed targets
// independently — Dashboard read NutritionTarget (a SwiftData record that
// stores onboarding-time defaults like 2,400), Nutrition Today summed
// today's PlannedMeal.totalCalories from the active plan (3,536). Same
// user, same day, two different numbers. This calculator is the single
// source of truth they both call.
//

import Foundation
import SwiftData

enum NutritionTargetCalculator {

    /// Per-macro target snapshot for today. Used by every surface that
    /// renders "X / Y kcal" so the Y value is identical across views.
    struct Targets {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }

    /// Compute today's macro targets. PRIMARY branch: when at least one
    /// PlannedMeal exists for today (from the active WeeklyMealPlan), the
    /// targets ARE the sum of those meals' macros — the AI generator's
    /// per-day allocation is the source of truth. FALLBACK branch: no plan
    /// yet (e.g. fresh install before generation completes), so we estimate
    /// from the DietaryProfile via Mifflin-St Jeor + activity multiplier.
    ///
    /// Pass `todayMeals` already filtered to today's date range. The caller
    /// owns the query; this helper just does arithmetic so it stays
    /// trivially callable from any ViewModel.
    static func targetsForToday(
        todayMeals: [PlannedMeal],
        dietaryProfile: DietaryProfile?,
        whoopAvgTDEE: Double? = nil
    ) -> Targets {
        if !todayMeals.isEmpty {
            let cals = todayMeals.reduce(into: 0.0) { $0 += $1.totalCalories }
            let prot = todayMeals.reduce(into: 0.0) { $0 += $1.totalProtein }
            let carbs = todayMeals.reduce(into: 0.0) { $0 += $1.totalCarbs }
            let fat = todayMeals.reduce(into: 0.0) { $0 += $1.totalFat }
            return Targets(
                calories: Int(cals),
                protein: Int(prot),
                carbs: Int(carbs),
                fat: Int(fat)
            )
        }
        return fallbackTargets(profile: dietaryProfile, whoopAvgTDEE: whoopAvgTDEE)
    }

    /// Mifflin-St Jeor + activity multiplier + goal adjustment. Used only
    /// when no PlannedMeal exists for today. Falls back to 2,400 kcal /
    /// 180g protein / 270g carbs / 67g fat (45% carbs, 25% fat of calories,
    /// 2g/kg protein at 90kg) when there's no DietaryProfile either —
    /// fresh-install state.
    /// The data-driven estimate shown when no plan covers today. Routes
    /// through `TDEECalculator` (Mifflin-St Jeor + Katch-McArdle when body fat
    /// is known, blended with a 7-day Whoop expenditure average when supplied)
    /// so the no-plan number is the same precise estimate the plan generator
    /// would start from — NOT a crude hand-rolled Mifflin guess.
    ///
    /// `whoopAvgTDEE` MUST be a multi-day rolling average, never a single
    /// day's burn: the TDEECalculator blend weights Whoop at 60%, so one rest
    /// day would otherwise drag the estimate hundreds of kcal low. Pass nil
    /// when no Whoop window is available — the calculator falls back to the
    /// Mifflin/Katch baseline cleanly.
    ///
    /// Hard fallback (no DietaryProfile at all — fresh install before
    /// onboarding) stays a fixed 2,400 / 180 / 270 / 67.
    /// The data-driven estimate shown when no plan covers today. Routes
    /// through `TDEECalculator` (Mifflin-St Jeor + Katch-McArdle when body fat
    /// is known, blended with a 7-day Whoop expenditure average when supplied)
    /// so the no-plan number is the same precise estimate the plan generator
    /// would start from — NOT a crude hand-rolled Mifflin guess.
    ///
    /// `whoopAvgTDEE` MUST be a multi-day rolling average, never a single
    /// day's burn: the TDEECalculator blend weights Whoop at 60%, so one rest
    /// day would otherwise drag the estimate hundreds of kcal low. Pass nil
    /// when no Whoop window is available — the calculator falls back to the
    /// Mifflin/Katch baseline cleanly.
    ///
    /// Hard fallback (no DietaryProfile at all — fresh install before
    /// onboarding) stays a fixed 2,400 / 180 / 270 / 67.
    private static func fallbackTargets(
        profile: DietaryProfile?,
        whoopAvgTDEE: Double? = nil
    ) -> Targets {
        guard let profile else {
            return Targets(calories: 2400, protein: 180, carbs: 270, fat: 67)
        }
        let result = TDEECalculator.calculate(
            weightKg: profile.currentWeightKg,
            heightCm: profile.heightCm,
            age: profile.age,
            biologicalSex: profile.biologicalSex,
            bodyFatPercent: profile.bodyFatPercent,
            trainingFrequency: profile.trainingFrequency,
            whoopAverageTDEE: whoopAvgTDEE,
            goal: profile.primaryGoal,
            goalWeightKg: profile.goalWeightKg,
            weeklyRateKg: profile.weeklyRateKg
        )
        let macros = result.macroTargets
        return Targets(
            calories: result.adjustedCalories,
            protein: macros.proteinGrams,
            carbs: macros.carbsGrams,
            fat: macros.fatGrams
        )
    }

    /// Fetch today's `.eaten` PlannedMeals and DietaryProfile from a
    /// ModelContext, then compute targets. Convenience for Dashboard where
    /// we don't have a NutritionTabViewModel — just a ModelContext via the
    /// fuel-quadrant fetch path.
    @MainActor
    static func targetsForToday(
        in context: ModelContext,
        whoopAvgTDEE: Double? = nil
    ) -> Targets {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        // Match Nutrition Today's predicate exactly: today's meals from the
        // active plan OR unbound (NL-logged). The predicate is intentionally
        // simple to dodge SwiftData's flaky optional-chain parsing on
        // to-one relationships — we filter in Swift below.
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
            }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let filtered = all.filter { meal in
            // Same filter as NutritionTabViewModel.loadToday — keep meals
            // tied to the active plan and orphans (manual logs).
            meal.mealPlan?.isActive == true || meal.mealPlan == nil
        }

        let profileDescriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate<DietaryProfile> { p in p.isActive == true }
        )
        let profile = (try? context.fetch(profileDescriptor))?.first

        // whoopAvgTDEE flows into the no-plan TDEE estimate so the Dashboard
        // Fuel surface and Nutrition Today (which passes the same shared
        // WhoopService value) show an identical no-plan number. Ignored when
        // today has plan meals — those ARE the target.
        let base = targetsForToday(
            todayMeals: filtered,
            dietaryProfile: profile,
            whoopAvgTDEE: whoopAvgTDEE
        )
        // Layer in the 5-day carryover spread (Phase F). Reads any
        // unexpired MacroCarryover rows and adds their per-day share
        // to today's base targets. Empty when nothing is in flight.
        let adjustment = MacroCarryoverService.activeAdjustmentForToday(in: context)
        guard adjustment.hasActiveCarryover else {
            return base
        }
        return Targets(
            calories: max(0, base.calories + Int(adjustment.calories.rounded())),
            protein: max(0, base.protein + Int(adjustment.protein.rounded())),
            carbs: max(0, base.carbs + Int(adjustment.carbs.rounded())),
            fat: max(0, base.fat + Int(adjustment.fat.rounded()))
        )
    }
}
