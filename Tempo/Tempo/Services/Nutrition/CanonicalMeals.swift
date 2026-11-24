//
// CanonicalMeals.swift
// Tempo
//
// The ONE definition of "a day's meals" and "eaten" that every nutrition
// surface shares: PlannedMeal rows on that calendar day (start-of-day
// boundary), from the active plan or unbound (manual logs), and eaten means
// `status == .eaten`. MealLog is legacy and deliberately not read here.
//
// The fetch keeps only the date range in #Predicate — SwiftData's parser is
// unreliable on optional-chain to-one relationships — and filters plan
// membership in Swift, same as NutritionTabViewModel.loadToday and the
// Dashboard Fuel fetch.
//

import Foundation
import SwiftData

@MainActor
enum CanonicalMeals {
    /// True when `meal` belongs on today's surfaces: tied to the active plan,
    /// or a manual log that isn't tied to any plan.
    static func isCanonical(_ meal: PlannedMeal) -> Bool {
        meal.mealPlan?.isActive == true || meal.mealPlan == nil
    }

    /// Past-day rule for review/history readers: archived plans hold real
    /// history, so they are kept, but the same slot (day + number + name) that
    /// exists on two plans counts once: the active plan's row, else the one
    /// the user acted on (not still `.planned`), else the first. Input order
    /// is preserved.
    static func historical(_ meals: [PlannedMeal]) -> [PlannedMeal] {
        struct Slot: Hashable {
            let day: Date
            let number: Int
            let name: String
        }
        func rank(_ meal: PlannedMeal) -> Int {
            if meal.mealPlan?.isActive == true || meal.mealPlan == nil { return 2 }
            return meal.status == .planned ? 0 : 1
        }
        var best: [Slot: PlannedMeal] = [:]
        for meal in meals {
            let slot = Slot(day: Calendar.current.startOfDay(for: meal.dayDate), number: meal.mealNumber, name: meal.mealName)
            if let current = best[slot], rank(current) >= rank(meal) { continue }
            best[slot] = meal
        }
        return meals.filter { meal in
            let slot = Slot(day: Calendar.current.startOfDay(for: meal.dayDate), number: meal.mealNumber, name: meal.mealName)
            return best[slot] === meal
        }
    }

    /// Every canonical meal on `day`'s calendar date, any status.
    static func meals(on day: Date, in context: ModelContext) -> [PlannedMeal] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= dayStart && meal.dayDate < dayEnd
            }
        )
        return ((try? context.fetch(descriptor)) ?? []).filter(isCanonical)
    }

    /// Canonical meals on `day` that were actually eaten.
    static func eatenMeals(on day: Date, in context: ModelContext) -> [PlannedMeal] {
        meals(on: day, in: context).filter { $0.status == .eaten }
    }

    /// Summed live macros (what was eaten, for eaten meals).
    static func totals(of meals: [PlannedMeal]) -> MealMacros {
        meals.reduce(MealMacros.zero) { $0 + $1.totals }
    }

    /// Summed plan baselines (what the plan asked for).
    static func planBaseline(of meals: [PlannedMeal]) -> MealMacros {
        meals.reduce(MealMacros.zero) { $0 + $1.planBaseline }
    }

    /// The whole numbers every screen shows for a day: the live totals summed
    /// from the unrounded meals and rounded ONCE, at the end. Rounding (or
    /// truncating) each meal before adding them up drifts by a gram or a kcal
    /// per meal, which is how Fuel, the Log tab and the product page ended up
    /// showing different values for the same day.
    static func roundedTotals(of meals: [PlannedMeal]) -> RoundedMacros {
        totals(of: meals).rounded
    }

    /// `roundedTotals` for the meals that were actually eaten.
    static func eatenRoundedTotals(of meals: [PlannedMeal]) -> RoundedMacros {
        roundedTotals(of: meals.filter { $0.status == .eaten })
    }
}

// MARK: - RoundedMacros

/// A day's macros as whole numbers (kcal and grams). Built only from
/// `MealMacros.rounded` so there is one rounding rule.
struct RoundedMacros: Equatable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    static let zero = RoundedMacros(calories: 0, protein: 0, carbs: 0, fat: 0)
}

extension MealMacros {
    /// Rounds each figure to the nearest whole number. Call it on a SUM, never
    /// on one meal before adding.
    var rounded: RoundedMacros {
        RoundedMacros(
            calories: Int(calories.rounded()),
            protein: Int(protein.rounded()),
            carbs: Int(carbs.rounded()),
            fat: Int(fat.rounded())
        )
    }
}
