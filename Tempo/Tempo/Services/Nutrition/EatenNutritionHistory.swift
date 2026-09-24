//
// EatenNutritionHistory.swift
// Tempo
//
// Real per-day nutrition history built from EATEN PlannedMeals — the one
// canonical "eaten" source (MealLog is legacy). Powers the 7-day calorie
// trend + weekly averages on the Fuel detail and the Daily Nutrition
// summary, which used to render hardcoded / Int.random bars.
//

import Foundation
import SwiftData

// MARK: - DailyEatenTotals

struct DailyEatenTotals: Identifiable, Equatable {
    /// Start of the calendar day.
    let date: Date
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let mealsEaten: Int

    var id: Date {
        date
    }

    /// False for a day with nothing marked eaten — the chart renders it as
    /// "no data", not as a real 0 kcal day.
    var hasData: Bool {
        mealsEaten > 0
    }
}

// MARK: - EatenNutritionHistory

enum EatenNutritionHistory {
    /// One entry per calendar day for the `days` days ending on `today`
    /// (oldest first). Days with no eaten meals come back with `hasData == false`.
    ///
    /// Meals are filtered by `EatenMealHistory.canonical`: today uses the
    /// canonical filter (active plan or unbound) so today's bar is the exact
    /// number the Dashboard Fuel card shows; past days also count archived
    /// plans (a weekly regen archives the previous plan), one row per slot.
    @MainActor
    static func dailyTotals(
        in context: ModelContext,
        days: Int = 7,
        endingOn today: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyEatenTotals] {
        guard days > 0 else {
            return []
        }
        let todayStart = calendar.startOfDay(for: today)
        guard let firstDay = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart),
              let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else {
            return []
        }
        let eatenRaw = MealStatus.eaten.rawValue
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= firstDay && meal.dayDate < tomorrowStart && meal.statusRaw == eatenRaw
            }
        )
        let meals = (try? context.fetch(descriptor)) ?? []
        return totals(from: meals, days: days, endingOn: todayStart, calendar: calendar)
    }

    /// Pure aggregation (unit-tested). `meals` may contain anything; only
    /// eaten meals inside the window are counted.
    static func totals(
        from meals: [PlannedMeal],
        days: Int,
        endingOn today: Date,
        calendar: Calendar = .current
    ) -> [DailyEatenTotals] {
        let todayStart = calendar.startOfDay(for: today)
        var byDay: [Date: [PlannedMeal]] = [:]
        // Same history rule as the Progress Report / RecoverIQ: today =
        // active plan or unbound; past days = any plan, one row per slot.
        for meal in EatenMealHistory.canonical(meals, now: todayStart, calendar: calendar) {
            byDay[calendar.startOfDay(for: meal.dayDate), default: []].append(meal)
        }
        return (0 ..< max(days, 0)).reversed().compactMap { offset -> DailyEatenTotals? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else {
                return nil
            }
            let eaten = byDay[day] ?? []
            return DailyEatenTotals(
                date: day,
                calories: Int(eaten.reduce(0.0) { $0 + $1.totalCalories }),
                protein: Int(eaten.reduce(0.0) { $0 + $1.totalProtein }),
                carbs: Int(eaten.reduce(0.0) { $0 + $1.totalCarbs }),
                fat: Int(eaten.reduce(0.0) { $0 + $1.totalFat }),
                mealsEaten: eaten.count
            )
        }
    }

    /// Average calories / protein over the days that have data. Nil when no
    /// day in the window has an eaten meal.
    static func averages(of history: [DailyEatenTotals]) -> (calories: Int, protein: Int, daysWithData: Int)? {
        let logged = history.filter(\.hasData)
        guard !logged.isEmpty else {
            return nil
        }
        let cal = logged.reduce(0) { $0 + $1.calories } / logged.count
        let prot = logged.reduce(0) { $0 + $1.protein } / logged.count
        return (cal, prot, logged.count)
    }
}
