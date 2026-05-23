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
        dietaryProfile: DietaryProfile?
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
        return fallbackTargets(profile: dietaryProfile)
    }

    /// Mifflin-St Jeor + activity multiplier + goal adjustment. Used only
    /// when no PlannedMeal exists for today. Falls back to 2,400 kcal /
    /// 180g protein / 270g carbs / 67g fat (45% carbs, 25% fat of calories,
    /// 2g/kg protein at 90kg) when there's no DietaryProfile either —
    /// fresh-install state.
    private static func fallbackTargets(profile: DietaryProfile?) -> Targets {
        guard let profile else {
            return Targets(calories: 2400, protein: 180, carbs: 270, fat: 67)
        }
        let bmr: Double = if profile.biologicalSex == .male {
            10 * profile.currentWeightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) + 5
        } else {
            10 * profile.currentWeightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) - 161
        }
        let activityMultiplier = 1.2 + (Double(profile.trainingFrequency) * 0.05)
        var cals = Int(bmr * activityMultiplier)
        switch profile.primaryGoal {
        case .leanGain: cals += 200
        case .cut: cals -= 400
        case .maintain: break
        }
        let protein = Int(profile.currentWeightKg * 2.0)
        let carbs = Int(Double(cals) * 0.45 / 4.0)
        let fat = Int(Double(cals) * 0.25 / 9.0)
        return Targets(calories: cals, protein: protein, carbs: carbs, fat: fat)
    }

    /// Fetch today's `.eaten` PlannedMeals and DietaryProfile from a
    /// ModelContext, then compute targets. Convenience for Dashboard where
    /// we don't have a NutritionTabViewModel — just a ModelContext via the
    /// fuel-quadrant fetch path.
    @MainActor
    static func targetsForToday(in context: ModelContext) -> Targets {
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

        return targetsForToday(todayMeals: filtered, dietaryProfile: profile)
    }
}
