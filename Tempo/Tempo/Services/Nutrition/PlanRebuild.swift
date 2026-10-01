//
// PlanRebuild.swift
// Tempo
//
// Rules for rebuilding the CURRENT week's plan from today forward without
// destroying what already happened. The invariant: for any date there is
// exactly one set of canonical meals — the active plan's rows (plus unbound
// manual logs). A rebuild keeps the active plan object, leaves every past day
// untouched, keeps today's eaten / skipped / modified meals, replaces only
// still-`.planned` meals from today on, and fits the new remaining meals to
// what today still needs (via MealRebalancer — no second copy of the maths).
//

import Foundation

enum PlanRebuild {
    /// True when `kept` (a meal that survives the rebuild) already occupies the
    /// slot a newly generated meal would take: same slot number or same name.
    /// Ad-hoc logs (plan baseline 0) never block — they sit outside the plan.
    static func occupies(kept: PlannedMeal, mealNumber: Int, mealName: String) -> Bool {
        guard kept.planBaseline.calories > 0 else {
            return false
        }
        if kept.mealNumber == mealNumber {
            return true
        }
        return kept.mealName.trimmingCharacters(in: .whitespaces).lowercased()
            == mealName.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Fit one day's NEW remaining meals to the day.
    ///
    /// - `dayTarget`: what the freshly built plan allotted the whole day.
    /// - `keptBaseline`: plan baselines of the meals kept (eaten / skipped).
    ///   The day's target is the sum of baselines, so the new meals take what
    ///   is left of `dayTarget` and the total stays put.
    /// - `consumed`: what was actually eaten today (any source). Remaining
    ///   meals are bumped or trimmed to cover the rest (MealRebalancer).
    static func fit(
        remaining: [PlannedMeal],
        dayTarget: MealMacros,
        keptBaseline: MealMacros,
        consumed: MealMacros
    ) {
        guard !remaining.isEmpty else {
            return
        }
        // Baselines first: they use the meals as generated.
        let generatedCalories = remaining.reduce(0.0) { $0 + $1.totalCalories }
        let room = MealMacros(
            calories: max(0, dayTarget.calories - keptBaseline.calories),
            protein: max(0, dayTarget.protein - keptBaseline.protein),
            carbs: max(0, dayTarget.carbs - keptBaseline.carbs),
            fat: max(0, dayTarget.fat - keptBaseline.fat)
        )
        for meal in remaining {
            let share = generatedCalories > 0
                ? meal.totalCalories / generatedCalories
                : 1.0 / Double(remaining.count)
            meal.planBaselineCalories = room.calories * share
            meal.planBaselineProtein = room.protein * share
            meal.planBaselineCarbs = room.carbs * share
            meal.planBaselineFat = room.fat * share
        }

        let adjustments = MealRebalancer.rebalance(
            dayTargets: MealRebalancer.Targets(
                calories: dayTarget.calories,
                protein: dayTarget.protein,
                carbs: dayTarget.carbs,
                fat: dayTarget.fat
            ),
            consumed: MealRebalancer.Macros(
                calories: consumed.calories,
                protein: consumed.protein,
                carbs: consumed.carbs,
                fat: consumed.fat
            ),
            remaining: remaining.map {
                MealRebalancer.PlannedMealMacros(
                    id: $0.id,
                    calories: $0.totalCalories,
                    protein: $0.totalProtein,
                    carbs: $0.totalCarbs,
                    fat: $0.totalFat
                )
            }
        )
        let byID = Dictionary(uniqueKeysWithValues: adjustments.map { ($0.mealID, $0) })
        for meal in remaining {
            guard let adjustment = byID[meal.id], !adjustment.isZero else {
                continue
            }
            let oldCalories = meal.totalCalories
            let newCalories = max(0, oldCalories + adjustment.calories)
            if oldCalories > 0 {
                // Scale the foods with the meal so the list still adds up.
                let ratio = min(3, max(0.2, newCalories / oldCalories))
                meal.foods = meal.foods.map { food in
                    PlannedFood(
                        name: food.name,
                        quantityGrams: (food.quantityGrams * ratio).rounded(),
                        calories: food.calories * ratio,
                        proteinG: food.proteinG * ratio,
                        carbsG: food.carbsG * ratio,
                        fatG: food.fatG * ratio,
                        source: food.source,
                        restaurant: food.restaurant
                    )
                }
            }
            meal.totalCalories = newCalories
            meal.totalProtein = max(0, meal.totalProtein + adjustment.protein)
            meal.totalCarbs = max(0, meal.totalCarbs + adjustment.carbs)
            meal.totalFat = max(0, meal.totalFat + adjustment.fat)
        }
    }
}
