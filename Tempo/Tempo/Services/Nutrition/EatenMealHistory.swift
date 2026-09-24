//
// EatenMealHistory.swift
// Tempo
//
// Canonical "eaten meals" over a MULTI-DAY window (Progress Report, RecoverIQ
// yesterday/weekly context).
//
// Today's canonical rule is `PlannedMeal.status == .eaten` on the active plan
// or unbound (`DashboardViewModel+NutritionFetch`). That rule alone is wrong
// for history: every plan regeneration archives the previous plan
// (`MealPlanGeneratorService`), so last week's eaten meals all live on
// archived plans and would silently drop to zero.
//
// Rule here:
//   - Today (and later): exact canonical rule — active plan or unbound — so
//     today's count always matches Dashboard / Nutrition Today.
//   - Past days: eaten meals from ANY plan. Regeneration never copies eaten
//     status, so archived meals are real history. If two plans both have the
//     same slot (dayDate + mealNumber) marked eaten — a mid-day regen where
//     the user re-marked the same meal — it counts once, preferring the
//     active plan's row.
//   - Unbound meals (Quick Log without a plan) always count.
//
// `MealLog` is legacy and intentionally not read.
//

import Foundation
import SwiftData

enum EatenMealHistory {
    /// Canonical eaten meals with `dayDate` in `[start, end)`.
    @MainActor
    static func fetch(
        from start: Date,
        to end: Date,
        in context: ModelContext,
        now: Date = Date()
    ) -> [PlannedMeal] {
        let eatenRaw = MealStatus.eaten.rawValue
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= start && meal.dayDate < end && meal.statusRaw == eatenRaw
            },
            sortBy: [SortDescriptor(\.dayDate), SortDescriptor(\.mealNumber)]
        )
        let fetched = (try? context.fetch(descriptor)) ?? []
        return canonical(fetched, now: now)
    }

    /// Applies the history rule (see file header) to already-fetched meals.
    /// Order of the input is preserved for the meals that are kept.
    static func canonical(
        _ meals: [PlannedMeal],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlannedMeal] {
        let todayStart = calendar.startOfDay(for: now)

        struct Slot: Hashable {
            let day: Date
            let mealNumber: Int
        }
        // Winning row id per plan-bound past slot: active plan beats archived.
        var winner: [Slot: (id: UUID, isActive: Bool)] = [:]
        for meal in meals where meal.status == .eaten && meal.mealPlan != nil {
            let day = calendar.startOfDay(for: meal.dayDate)
            guard day < todayStart else {
                continue
            }
            let slot = Slot(day: day, mealNumber: meal.mealNumber)
            let isActive = meal.mealPlan?.isActive == true
            if let current = winner[slot], current.isActive || !isActive {
                continue
            }
            winner[slot] = (meal.id, isActive)
        }

        return meals.filter { meal in
            guard meal.status == .eaten else {
                return false
            }
            guard let plan = meal.mealPlan else {
                return true
            }
            let day = calendar.startOfDay(for: meal.dayDate)
            if day >= todayStart {
                return plan.isActive
            }
            return winner[Slot(day: day, mealNumber: meal.mealNumber)]?.id == meal.id
        }
    }
}
