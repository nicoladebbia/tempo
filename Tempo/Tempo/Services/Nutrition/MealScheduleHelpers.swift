//
// MealScheduleHelpers.swift
// Tempo
//
// Created by Tempo on 12/05/2026.
//
//

import Foundation
import OSLog

/// Schedule arithmetic for `PlannedMeal`. Converts the meal's `scheduledTime`
/// ("HH:mm") + `dayDate` into a real `Date` and computes prep-start / eat-finish
/// windows used by `NextMealCardView` and `MealDetailView`.
enum MealScheduleHelpers {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let logger = Logger(subsystem: "com.tempo.nutrition", category: "MealScheduleHelpers")

    /// The full Date that the meal is scheduled to be eaten. Combines
    /// the meal's calendar day with its "HH:mm" time-of-day string.
    /// Falls back to the day's start at midnight on parse failure.
    static func scheduledDate(for meal: PlannedMeal, calendar: Calendar = .current) -> Date {
        guard let time = timeFormatter.date(from: meal.scheduledTime) else {
            // Malformed scheduledTime means we'll display midnight; log so the
            // bug surfaces in a debug session instead of looking like a UI typo.
            logger.warning("Malformed scheduledTime '\(meal.scheduledTime, privacy: .public)' on meal \(meal.id, privacy: .public); falling back to dayDate.")
            return meal.dayDate
        }
        let comps = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            second: 0,
            of: meal.dayDate
        ) ?? meal.dayDate
    }

    /// When the user should start prepping. `meal-time − (prep + cook)`.
    static func prepStartDate(for meal: PlannedMeal, calendar: Calendar = .current) -> Date {
        let meal_time = scheduledDate(for: meal, calendar: calendar)
        let prep = meal.recipe?.prepMinutes ?? 0
        let cook = meal.recipe?.cookMinutes ?? 0
        let leadMinutes = prep + cook
        return calendar.date(byAdding: .minute, value: -leadMinutes, to: meal_time) ?? meal_time
    }

    /// When the user should be done eating. `meal-time + eatDurationMinutes`.
    static func eatFinishDate(for meal: PlannedMeal, calendar: Calendar = .current) -> Date {
        let meal_time = scheduledDate(for: meal, calendar: calendar)
        return calendar.date(byAdding: .minute, value: meal.eatDurationMinutes, to: meal_time) ?? meal_time
    }

    /// Find the next meal in `meals` that the user has neither eaten nor skipped
    /// and whose prep-start has not yet elapsed (or whose scheduled time is in
    /// the future). Returns nil if no upcoming meal exists.
    static func nextUpcomingMeal(
        in meals: [PlannedMeal],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PlannedMeal? {
        // Build (meal, scheduledDate) tuples once so the sort doesn't recompute.
        let upcoming: [(meal: PlannedMeal, date: Date)] = meals
            .filter { $0.status == .planned }
            .map { ($0, scheduledDate(for: $0, calendar: calendar)) }
            .filter { $0.date >= now }
        return upcoming.min(by: { $0.date < $1.date })?.meal
    }

    /// How early (in minutes) before `prepStart` we consider a meal "imminent".
    /// Used by the Dashboard Fuel tap router: within this window the tap
    /// jumps straight to the meal's recipe so the user can start cooking.
    static let imminentLeadMinutes: Int = 30

    /// True when `now` falls in the meal's prep-to-eat window:
    /// `[prepStart - imminentLeadMinutes, eatFinish]`. Outside this window
    /// the user is not actively engaged with the meal yet.
    static func isImminent(
        meal: PlannedMeal,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let prepStart = prepStartDate(for: meal, calendar: calendar)
        let eatFinish = eatFinishDate(for: meal, calendar: calendar)
        let imminentStart = calendar.date(
            byAdding: .minute,
            value: -imminentLeadMinutes,
            to: prepStart
        ) ?? prepStart
        return now >= imminentStart && now <= eatFinish
    }
}
