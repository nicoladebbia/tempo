//
// MealShiftPlanner.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import Foundation

// MARK: - MealShiftResult

/// One adjusted meal time produced by `MealShiftPlanner.computeShift`.
/// The caller writes `newScheduledTime` back to `PlannedMeal.scheduledTime`.
struct MealShiftResult: Equatable {
    let mealID: UUID
    let originalScheduledTime: String
    let newScheduledTime: String
    let newScheduledDate: Date
}

// MARK: - MealShiftPlanner

/// Pure, deterministic shift of the remaining meals in a day after one meal
/// is eaten off-schedule. Preserves the original gaps between meals; if the
/// last shifted meal would exceed `bedtimeCap`, compresses the gaps
/// proportionally so all remaining meals fit before the cap.
///
/// AI was considered for this. The shift problem is deterministic — no
/// judgment call, just arithmetic — so we use a pure function. Latency and
/// non-determinism of an AI call buy nothing here. AI belongs in *plan
/// generation*, where we feed actual eating patterns as input to anchor
/// future plans to the user's real rhythm.
enum MealShiftPlanner {
    /// Minimum delta (seconds) before a shift is applied. Eating exactly at
    /// the scheduled time, or within 15 minutes, doesn't disturb the rest of
    /// the day.
    static let minShiftThresholdSeconds: TimeInterval = 15 * 60

    /// Default bedtime cap. Dinner (and any later meal) won't be scheduled
    /// past this hour:minute. Compression kicks in if it would.
    static let defaultBedtimeCap: (hour: Int, minute: Int) = (22, 0)

    /// Compute new times for meals scheduled AFTER `eatenMealID`. Returns
    /// an empty array when no shift is needed (delta < threshold) or when
    /// no remaining meals exist.
    ///
    /// - Parameters:
    ///   - todaysMeals: all of today's `PlannedMeal`s, in any order.
    ///   - eatenMealID: the meal the user just marked eaten.
    ///   - actualEatTime: when the user actually ate it.
    ///   - bedtimeCap: latest time any meal may be scheduled. Defaults to 22:00.
    ///   - calendar: injected for testability.
    static func computeShift(
        todaysMeals: [PlannedMeal],
        eatenMealID: UUID,
        actualEatTime: Date,
        bedtimeCap: (hour: Int, minute: Int) = defaultBedtimeCap,
        calendar: Calendar = .current
    ) -> [MealShiftResult] {
        // Order by mealNumber so "after" is well-defined.
        let ordered = todaysMeals.sorted { $0.mealNumber < $1.mealNumber }
        guard let eatenIndex = ordered.firstIndex(where: { $0.id == eatenMealID }) else {
            return []
        }
        let eatenMeal = ordered[eatenIndex]
        let scheduledDate = MealScheduleHelpers.scheduledDate(for: eatenMeal, calendar: calendar)
        let delta = actualEatTime.timeIntervalSince(scheduledDate)
        guard abs(delta) >= minShiftThresholdSeconds else {
            return []
        }

        // Only shift meals AFTER the eaten one that aren't already eaten/skipped.
        let remaining = Array(ordered[(eatenIndex + 1)...])
            .filter { $0.status == .planned }
        guard !remaining.isEmpty else {
            return []
        }

        // Compute provisional shifted times by adding `delta` to each.
        var shifted: [(meal: PlannedMeal, date: Date)] = remaining.map { meal in
            let original = MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar)
            return (meal, original.addingTimeInterval(delta))
        }

        // Cap check: if the last meal exceeds today's bedtime cap, compress.
        // Anchor = end of eating the just-eaten meal (its actualEatTime +
        // its eat duration). Available = cap − anchor. Required = original
        // span between (anchor) and (last meal's original time).
        if let last = shifted.last {
            let dayStart = calendar.startOfDay(for: actualEatTime)
            let capDate = calendar.date(
                bySettingHour: bedtimeCap.hour,
                minute: bedtimeCap.minute,
                second: 0,
                of: dayStart
            ) ?? last.date

            if last.date > capDate {
                let anchor = actualEatTime.addingTimeInterval(
                    Double(eatenMeal.eatDurationMinutes) * 60.0
                )
                let lastOriginal = MealScheduleHelpers.scheduledDate(
                    for: last.meal,
                    calendar: calendar
                )
                let originalAnchor = scheduledDate.addingTimeInterval(
                    Double(eatenMeal.eatDurationMinutes) * 60.0
                )
                let originalSpan = lastOriginal.timeIntervalSince(originalAnchor)
                let available = capDate.timeIntervalSince(anchor)

                if originalSpan > 0, available > 0, available < originalSpan {
                    let compression = available / originalSpan
                    shifted = shifted.map { entry in
                        let original = MealScheduleHelpers.scheduledDate(
                            for: entry.meal,
                            calendar: calendar
                        )
                        let originalOffset = original.timeIntervalSince(originalAnchor)
                        let newOffset = originalOffset * compression
                        return (entry.meal, anchor.addingTimeInterval(newOffset))
                    }
                } else if available <= 0 {
                    // No room left in the day for any further meals.
                    // Pin them all to the cap; the user will see "Portable
                    // only" or overdue badges and decide.
                    shifted = shifted.map { ($0.meal, capDate) }
                }
            }
        }

        // Build results with HH:mm strings.
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return shifted.map { entry in
            MealShiftResult(
                mealID: entry.meal.id,
                originalScheduledTime: entry.meal.scheduledTime,
                newScheduledTime: formatter.string(from: entry.date),
                newScheduledDate: entry.date
            )
        }
    }


    /// Generic anchor-based shift. Used by the Coach agent when an arbitrary
    /// event (soccer match, study sprint, calendar block) makes a meal need
    /// to land at a specific wall-clock time — without that meal having
    /// actually been eaten yet.
    ///
    /// The math is identical to `computeShift`: pin a chosen meal to
    /// `anchorTime`, propagate the delta forward to subsequent planned
    /// meals, then compress under the bedtime cap. The only thing that
    /// changes is the anchor: there is no `eatenMealID` and no real eat
    /// duration to add to the anchor when compressing — we use 0.
    ///
    /// - Parameters:
    ///   - todaysMeals: today's PlannedMeals, any order. Filtered + sorted internally.
    ///   - anchorTime: wall-clock time the anchor meal should sit at.
    ///   - anchorMealNumber: which meal in the day (by `mealNumber`, 1-indexed)
    ///     is being pinned to `anchorTime`. Subsequent meals (mealNumber > this)
    ///     are shifted; earlier meals are untouched.
    ///   - bedtimeCap: latest a meal can land. Defaults to 22:00.
    ///   - calendar: for date arithmetic. Defaults to `.current`.
    /// - Returns: shifts for every still-planned meal AFTER the anchor.
    ///   Empty when the anchor meal isn't found, when nothing needs to
    ///   shift (delta below threshold), or when no later planned meals exist.
    static func computeShiftFromAnchor(
        todaysMeals: [PlannedMeal],
        anchorTime: Date,
        anchorMealNumber: Int,
        bedtimeCap: (hour: Int, minute: Int) = defaultBedtimeCap,
        calendar: Calendar = .current
    ) -> [MealShiftResult] {
        let ordered = todaysMeals.sorted { $0.mealNumber < $1.mealNumber }
        guard let anchorIndex = ordered.firstIndex(where: { $0.mealNumber == anchorMealNumber }) else {
            return []
        }
        let anchorMeal = ordered[anchorIndex]
        let anchorOriginal = MealScheduleHelpers.scheduledDate(for: anchorMeal, calendar: calendar)
        let delta = anchorTime.timeIntervalSince(anchorOriginal)
        guard abs(delta) >= minShiftThresholdSeconds else {
            return []
        }

        let remaining = Array(ordered[(anchorIndex + 1)...])
            .filter { $0.status == .planned }
        guard !remaining.isEmpty else {
            return []
        }

        var shifted: [(meal: PlannedMeal, date: Date)] = remaining.map { meal in
            let original = MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar)
            return (meal, original.addingTimeInterval(delta))
        }

        // Bedtime cap compression — same as computeShift but with the
        // anchor itself as the post-meal pivot (eat duration = 0 since
        // this is a synthetic anchor, not an eaten meal).
        if let last = shifted.last {
            let dayStart = calendar.startOfDay(for: anchorTime)
            let capDate = calendar.date(
                bySettingHour: bedtimeCap.hour,
                minute: bedtimeCap.minute,
                second: 0,
                of: dayStart
            ) ?? last.date

            if last.date > capDate {
                let anchorPivot = anchorTime
                let lastOriginal = MealScheduleHelpers.scheduledDate(
                    for: last.meal,
                    calendar: calendar
                )
                let originalSpan = lastOriginal.timeIntervalSince(anchorOriginal)
                let available = capDate.timeIntervalSince(anchorPivot)

                if originalSpan > 0, available > 0, available < originalSpan {
                    let compression = available / originalSpan
                    shifted = shifted.map { entry in
                        let original = MealScheduleHelpers.scheduledDate(
                            for: entry.meal,
                            calendar: calendar
                        )
                        let originalOffset = original.timeIntervalSince(anchorOriginal)
                        let newOffset = originalOffset * compression
                        return (entry.meal, anchorPivot.addingTimeInterval(newOffset))
                    }
                } else if available <= 0 {
                    shifted = shifted.map { ($0.meal, capDate) }
                }
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return shifted.map { entry in
            MealShiftResult(
                mealID: entry.meal.id,
                originalScheduledTime: entry.meal.scheduledTime,
                newScheduledTime: formatter.string(from: entry.date),
                newScheduledDate: entry.date
            )
        }
    }
}
