//
// MealOrdering.swift
// Tempo
//
// Clock-order helpers for a day's meals, kept free of any view model so
// services (MealOutcomeService, PlanRebuild) don't depend on UI state.
//

import Foundation

enum MealOrdering {
    /// Parse a "HH:mm" (or "H:mm") string into minutes-since-midnight.
    /// nil for anything unreadable so malformed values sort to the end.
    /// Locale-independent: split on ":" and parse integers directly.
    static func minutesOfDay(from hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0 ..< 24).contains(hour),
              (0 ..< 60).contains(minute)
        else {
            return nil
        }
        return hour * 60 + minute
    }

    /// Today's meal order: parsed "HH:mm" minutes-of-day, then meal number.
    /// Malformed times sort to the end.
    static func chronological(_ meals: [PlannedMeal]) -> [PlannedMeal] {
        meals.sorted { lhs, rhs in
            let lhsMinutes = minutesOfDay(from: lhs.scheduledTime) ?? Int.max
            let rhsMinutes = minutesOfDay(from: rhs.scheduledTime) ?? Int.max
            if lhsMinutes != rhsMinutes {
                return lhsMinutes < rhsMinutes
            }
            return lhs.mealNumber < rhs.mealNumber
        }
    }
}
