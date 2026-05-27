//
// MealRebalancer.swift
// Tempo
//
// Pure macro rebalancer for the same-day remaining-meal flow.
//
// When a meal is marked eaten — especially with a substitute, an "ate
// something else" note, or any path that zeroes the planned macros —
// the day's remaining `.planned` meals can be off-target. This helper
// computes the per-meal macro deltas needed to bring the day back to
// its original total, distributed proportionally across the remaining
// meals.
//
// Pure inputs → pure outputs so the math is testable in isolation.
// Caller (NutritionTabViewModel.markMealEaten) applies the result by
// adding the delta to each remaining meal's stored macros.
//

import Foundation

enum MealRebalancer {
    /// Thresholds — small misses are noise. ±100 kcal or ±10g protein
    /// is the floor for firing a rebalance. Below these we leave the
    /// remaining meals alone (the user can hit their target loosely
    /// without us juggling every meal by 12 kcal).
    static let kcalThreshold: Double = 100
    static let proteinThreshold: Double = 10

    /// One meal's adjustment after rebalance. Apply by adding each
    /// field to the corresponding stored macro on the PlannedMeal.
    struct Adjustment: Equatable {
        let mealID: UUID
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double

        /// True when nothing needs to change for this meal.
        var isZero: Bool {
            calories == 0 && protein == 0 && carbs == 0 && fat == 0
        }
    }

    /// Inputs:
    /// - `dayTargets`: the day's full macro targets (the totals the
    ///   plan was built to hit).
    /// - `consumed`: macros across .eaten + .skipped meals so far.
    ///   Skipped meals count as 0 consumed; their planned macros are
    ///   already removed from the remaining list by the caller.
    /// - `remaining`: the .planned meals still to eat today.
    ///
    /// Returns one Adjustment per remaining meal (zero-valued when the
    /// residual delta is below threshold). Caller checks `isZero` to
    /// skip writes.
    static func rebalance(
        dayTargets: Targets,
        consumed: Macros,
        remaining: [PlannedMealMacros]
    ) -> [Adjustment] {
        guard !remaining.isEmpty else { return [] }

        // Macros the remaining meals were originally going to deliver.
        let plannedRemaining = remaining.reduce(into: Macros.zero) { acc, m in
            acc.calories += m.calories
            acc.protein += m.protein
            acc.carbs += m.carbs
            acc.fat += m.fat
        }

        // What the day still needs = total target − already consumed.
        let stillNeeded = Macros(
            calories: dayTargets.calories - consumed.calories,
            protein: dayTargets.protein - consumed.protein,
            carbs: dayTargets.carbs - consumed.carbs,
            fat: dayTargets.fat - consumed.fat
        )

        // Residual = what's missing from the remaining meals to hit the
        // still-needed totals. Positive = need to bump remaining meals
        // up; negative = need to trim them down.
        let residual = Macros(
            calories: stillNeeded.calories - plannedRemaining.calories,
            protein: stillNeeded.protein - plannedRemaining.protein,
            carbs: stillNeeded.carbs - plannedRemaining.carbs,
            fat: stillNeeded.fat - plannedRemaining.fat
        )

        // Skip noise: only fire when one of the macro deltas crosses
        // its threshold. Once one fires, all four get redistributed so
        // we don't leave the macro mix lopsided.
        guard abs(residual.calories) >= kcalThreshold
            || abs(residual.protein) >= proteinThreshold
        else {
            return remaining.map {
                Adjustment(mealID: $0.id, calories: 0, protein: 0, carbs: 0, fat: 0)
            }
        }

        // Distribute the residual proportionally to each remaining
        // meal's share of plannedRemaining. Falls back to even split
        // when plannedRemaining is zero (e.g. all remaining macros
        // already zeroed by prior substitutes).
        return remaining.map { meal in
            let share = shareFraction(
                meal: meal,
                planned: plannedRemaining,
                fallback: 1.0 / Double(remaining.count)
            )
            return Adjustment(
                mealID: meal.id,
                calories: (residual.calories * share).rounded(),
                protein: (residual.protein * share).rounded(),
                carbs: (residual.carbs * share).rounded(),
                fat: (residual.fat * share).rounded()
            )
        }
    }

    /// Per-meal weight in the redistribution. Uses calories as the
    /// dominant axis when planned macros are non-zero; falls back to
    /// even split when the remaining meals carry no planned calories
    /// (e.g. all already zeroed). Keeps the math defensible without
    /// over-engineering.
    private static func shareFraction(
        meal: PlannedMealMacros,
        planned: Macros,
        fallback: Double
    ) -> Double {
        if planned.calories > 0 {
            return meal.calories / planned.calories
        }
        return fallback
    }

    // MARK: - Value types

    /// The day's full macro target — same shape NutritionTargetCalculator
    /// returns. Re-declared here so MealRebalancer has no dependency on
    /// upstream types and tests can construct it freely.
    struct Targets: Equatable {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    struct Macros: Equatable {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double

        static let zero = Macros(calories: 0, protein: 0, carbs: 0, fat: 0)
    }

    /// Subset of PlannedMeal fields needed for the rebalance math —
    /// keeps the API testable without SwiftData in the loop.
    struct PlannedMealMacros: Equatable {
        let id: UUID
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
}
