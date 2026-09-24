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
}
