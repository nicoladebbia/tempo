//
// PlannedMealTimingMatcher.swift
// Tempo
//
// Shared utilities for matching real-world eat-times against a day's
// PlannedMeal.scheduledTime values. Used by:
//
//   - NutritionTodayView (Phase 1) — skip the MarkEatenSheet when the
//     tap lands within ±15 min of the planned time (common case).
//   - NaturalLanguageLoggingService (Phase 2) — when the NL parser
//     returns a meal_type and/or eaten_at, find the best PlannedMeal
//     to attach the log to.
//   - CoachContextAssembler (Phase 6) — compute the per-meal
//     planned-vs-actual delta for the today-live block.
//   - RecoveryAIInsightService (Phase 7) — detect late-meal deviations
//     for the conditional late-meal line.
//
// All functions are pure (no SwiftData/HealthKit dependencies); callers
// pass in the meals they already have. Times are interpreted in the
// current calendar timezone.
//

import Foundation

enum PlannedMealTimingMatcher {
    /// How close `now` must be to `meal.scheduledTime` to count as
    /// "on time" — used by the smart-default that bypasses the
    /// MarkEatenSheet for routine on-schedule taps.
    static let onTimeWindow: TimeInterval = 15 * 60

    /// Returns true when `now` is within ±`onTimeWindow` of the meal's
    /// scheduled time today. False when the scheduledTime can't be
    /// parsed — falling through to the sheet is the safe default.
    static func isNearScheduled(meal: PlannedMeal, now: Date) -> Bool {
        guard let scheduled = scheduledDate(for: meal, on: now) else {
            return false
        }
        return abs(now.timeIntervalSince(scheduled)) <= onTimeWindow
    }

    /// Resolves `meal.scheduledTime` ("HH:mm") into a full Date anchored
    /// to the calendar day of `reference`. Returns nil for malformed
    /// time strings.
    static func scheduledDate(for meal: PlannedMeal, on reference: Date) -> Date? {
        let parts = meal.scheduledTime.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return nil
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: reference)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)
    }

    /// Finds the best PlannedMeal in `candidates` for a parsed log
    /// entry. Match precedence:
    ///   1. If `mealType` is non-nil, narrow to PlannedMeals whose
    ///      mealName matches (case-insensitive).
    ///   2. Among the narrowed set (or all candidates if mealType was
    ///      nil), prefer the meal whose scheduled time is closest to
    ///      `eatenAt` (or `now` if eatenAt is nil).
    ///   3. Tie-break by mealNumber ascending.
    /// Returns nil when candidates is empty or no scheduledTime parses.
    static func bestMatch(
        for candidates: [PlannedMeal],
        mealType: String?,
        eatenAt: Date?,
        now: Date
    ) -> PlannedMeal? {
        guard !candidates.isEmpty else { return nil }

        let narrowed: [PlannedMeal]
        if let type = mealType?.lowercased(),
           !type.isEmpty
        {
            let filtered = candidates.filter { $0.mealName.lowercased() == type }
            // If the type filter empties the set, fall back to the
            // full list — the user may have typed "snack" but the
            // plan calls it "Afternoon snack".
            narrowed = filtered.isEmpty ? candidates : filtered
        } else {
            narrowed = candidates
        }

        let anchor = eatenAt ?? now
        return narrowed.min { lhs, rhs in
            let l = scheduledDate(for: lhs, on: anchor).map {
                abs($0.timeIntervalSince(anchor))
            } ?? .greatestFiniteMagnitude
            let r = scheduledDate(for: rhs, on: anchor).map {
                abs($0.timeIntervalSince(anchor))
            } ?? .greatestFiniteMagnitude
            if l == r { return lhs.mealNumber < rhs.mealNumber }
            return l < r
        }
    }

    /// Delta in minutes: actual − planned. Positive = ate late, negative
    /// = ate early. Returns nil when actualEatenAt is nil or
    /// scheduledTime is malformed.
    static func minutesLate(for meal: PlannedMeal) -> Int? {
        guard let actual = meal.actualEatenAt,
              let scheduled = scheduledDate(for: meal, on: actual)
        else {
            return nil
        }
        return Int(actual.timeIntervalSince(scheduled) / 60)
    }
}
