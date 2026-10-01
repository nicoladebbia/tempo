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
    /// Floor for a rebuilt meal's baseline, as a share of its generated macros.
    private static let minimumShare = 0.1

    /// A newly generated slot, as far as occupancy matching cares.
    struct Slot {
        let mealNumber: Int
        let mealName: String
        let scheduledTime: String
    }

    /// Indices of `slots` already taken by a meal that survives the rebuild.
    /// One-to-one: every kept meal claims at most ONE new slot, so two kept
    /// "Snack"s drop two new snacks, not all of them, and a kept dish never
    /// swallows an unrelated new one. A kept meal claims, in order of
    /// preference: a free slot of the same name or meal type (closest
    /// scheduled time wins); failing that, the free slot with its meal number
    /// — only when either name carries no meal type ("Meal 3"), so a changed
    /// meal count can't drop a different dish. Ad-hoc logs never claim a slot
    /// — they sit outside the plan.
    static func occupiedSlots(kept: [PlannedMeal], slots: [Slot]) -> Set<Int> {
        var taken = Set<Int>()
        let planKept = MealOrdering.chronological(kept.filter { !$0.isUnplannedLog })
        for meal in planKept {
            let keptName = normalized(meal.mealName)
            let keptType = MealType.inferred(fromName: meal.mealName)
            let keptMinutes = MealOrdering.minutesOfDay(from: meal.scheduledTime)
            let sameDish = slots.indices.filter { index in
                guard !taken.contains(index) else {
                    return false
                }
                let slotName = normalized(slots[index].mealName)
                if slotName == keptName {
                    return true
                }
                if let keptType, MealType.inferred(fromName: slots[index].mealName) == keptType {
                    return true
                }
                return false
            }
            if let best = sameDish.min(by: { lhs, rhs in
                distance(keptMinutes, slots[lhs]) < distance(keptMinutes, slots[rhs])
            }) {
                taken.insert(best)
                continue
            }
            if let byNumber = slots.indices.first(where: { index in
                !taken.contains(index)
                    && slots[index].mealNumber == meal.mealNumber
                    && (keptType == nil || MealType.inferred(fromName: slots[index].mealName) == nil)
            }) {
                taken.insert(byNumber)
            }
        }
        return taken
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func distance(_ keptMinutes: Int?, _ slot: Slot) -> Int {
        guard let keptMinutes, let slotMinutes = MealOrdering.minutesOfDay(from: slot.scheduledTime) else {
            return Int.max
        }
        return abs(keptMinutes - slotMinutes)
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
            // A plan meal never gets an all-zero baseline (that reads as an
            // ad-hoc log and drops it from the day target): when the day is
            // already full it keeps a small share of what was generated.
            meal.planBaselineCalories = max(room.calories * share, meal.totalCalories * minimumShare)
            meal.planBaselineProtein = max(room.protein * share, meal.totalProtein * minimumShare)
            meal.planBaselineCarbs = max(room.carbs * share, meal.totalCarbs * minimumShare)
            meal.planBaselineFat = max(room.fat * share, meal.totalFat * minimumShare)
            meal.isUnplannedLogFlag = false
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
        let byID = Dictionary(adjustments.map { ($0.mealID, $0) }, uniquingKeysWith: { first, _ in first })
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
