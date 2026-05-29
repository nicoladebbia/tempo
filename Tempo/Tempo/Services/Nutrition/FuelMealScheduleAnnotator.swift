//
// FuelMealScheduleAnnotator.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import Foundation

// MARK: - BusyBlock

/// A non-all-day calendar event reduced to the fields the annotator needs.
/// Decouples the annotator from EventKit/`CalendarEvent` so it stays pure-testable.
struct BusyBlock: Sendable, Equatable {
    let start: Date
    let end: Date
    let title: String
    /// Event location, if any. Drives the "can I cook through this?"
    /// decision: nil / empty / "home" → not portable-forcing.
    var location: String? = nil

    /// True when this event would force a portable meal — i.e. it's
    /// somewhere the user can't cook. nil/empty location or a location
    /// that reads as home means they CAN cook, so the meal isn't forced
    /// portable just because the times overlap.
    var forcesPortable: Bool {
        guard let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !loc.isEmpty
        else {
            return false // no location → assume home / cookable
        }
        return !loc.lowercased().contains("home")
    }
}

// MARK: - FuelMealRow

/// Annotated display model for a `PlannedMeal` in the Fuel expanded view.
/// Computed from the SwiftData meal + today's actual wake + EventKit busy
/// blocks. The underlying `PlannedMeal` is never mutated — shifts are
/// applied to `displayedTime` only.
struct FuelMealRow: Identifiable {
    let meal: PlannedMeal
    let originalTime: Date
    let displayedTime: Date
    let shiftMinutes: Int
    let isPortableOnly: Bool
    let conflictingEventTitle: String?

    var id: UUID { meal.id }
}

// MARK: - MealScheduleDisplay

/// Resolved time-points for one meal *after* applying any in-memory shifts
/// (Whoop / HealthKit wake-time vs planned wake). The persisted
/// `scheduledTime` is never mutated by this resolver — it's display-only.
/// Used by `MealDetailView` so the schedule block reflects every shift the
/// rest of the app already applies.
struct MealScheduleDisplay: Equatable, Sendable {
    let prepStart: Date
    let mealTime: Date
    let eatFinish: Date
    /// Signed minutes the meal has been shifted from its stored time. Zero
    /// when no wake-time delta exists. Surfaced as a small annotation in the
    /// detail view.
    let shiftMinutes: Int

    var hasShift: Bool { shiftMinutes != 0 }
}

extension FuelMealScheduleAnnotator {
    /// Resolve one meal's display times. Applies the same Whoop-adaptive
    /// shift that the Fuel day list uses (so the two views agree). Any
    /// shift from `MealShiftPlanner` (eating-time) or AI redistribution
    /// has already been persisted to `scheduledTime`, so reading the
    /// helper picks those up automatically; only the wake-time signal is
    /// display-only and needs to be threaded through here.
    static func display(
        for meal: PlannedMeal,
        plannedWakeMinutes: Int,
        actualWakeTime: Date?,
        calendar: Calendar = .current
    ) -> MealScheduleDisplay {
        let shift: TimeInterval = shiftSeconds(
            plannedWakeMinutes: plannedWakeMinutes,
            actualWakeTime: actualWakeTime,
            calendar: calendar
        ) ?? 0
        let prep = MealScheduleHelpers.prepStartDate(for: meal, calendar: calendar)
            .addingTimeInterval(shift)
        let eat = MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar)
            .addingTimeInterval(shift)
        let finish = MealScheduleHelpers.eatFinishDate(for: meal, calendar: calendar)
            .addingTimeInterval(shift)
        return MealScheduleDisplay(
            prepStart: prep,
            mealTime: eat,
            eatFinish: finish,
            shiftMinutes: Int(shift / 60)
        )
    }
}

// MARK: - FuelMealScheduleAnnotator

/// Pure helper that combines today's `PlannedMeal`s with two intelligence
/// layers: Whoop-adaptive shift (actual wake − planned wake, applied
/// uniformly to every meal of the day) and EventKit conflict detection
/// (a meal is flagged "portable only" when its post-shift time falls inside
/// a busy block, or within `edgeThresholdMinutes` of either edge).
enum FuelMealScheduleAnnotator {
    /// Free-time threshold around busy-block edges. A meal scheduled within
    /// this many minutes of the start or end of a busy block is still flagged
    /// because the user can't realistically cook & sit down to eat in less
    /// than 15 minutes adjacent to a meeting.
    static let edgeThresholdMinutes: Int = 15

    /// Computes the shift to apply to every meal today.
    ///
    /// Returns `nil` (treated as zero shift by `annotate`) when there's no
    /// actual wake signal yet (no Whoop sync, no HealthKit reading). The
    /// shift is the signed difference `actualWake − plannedWakeToday`.
    /// Maximum display shift in either direction. A larger raw shift means
    /// HealthKit returned junk (e.g. a nap mistaken for the morning wake),
    /// and applying it uniformly would push meals before wake or past
    /// bedtime. ±3h covers honest jet-lag and early-rise scenarios.
    static let maxDisplayShiftSeconds: TimeInterval = 3 * 3600

    static func shiftSeconds(
        plannedWakeMinutes: Int,
        actualWakeTime: Date?,
        calendar: Calendar = .current
    ) -> TimeInterval? {
        guard let actualWakeTime else { return nil }
        let dayStart = calendar.startOfDay(for: actualWakeTime)
        let plannedWake = calendar.date(
            byAdding: .minute,
            value: plannedWakeMinutes,
            to: dayStart
        ) ?? dayStart
        let raw = actualWakeTime.timeIntervalSince(plannedWake)
        return max(-maxDisplayShiftSeconds, min(maxDisplayShiftSeconds, raw))
    }

    static func annotate(
        meals: [PlannedMeal],
        plannedWakeMinutes: Int,
        actualWakeTime: Date?,
        busyBlocks: [BusyBlock],
        calendar: Calendar = .current
    ) -> [FuelMealRow] {
        let shift: TimeInterval = shiftSeconds(
            plannedWakeMinutes: plannedWakeMinutes,
            actualWakeTime: actualWakeTime,
            calendar: calendar
        ) ?? 0

        let edgeWindow = TimeInterval(edgeThresholdMinutes * 60)

        return meals.map { meal in
            let original = MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar)
            let displayed = original.addingTimeInterval(shift)

            let conflict = busyBlocks.first { block in
                // Only events the user can't cook through force a portable
                // meal. A "Chin Tucks" event at home (or any event with no
                // location) shouldn't flag the meal portable just because
                // the times overlap — the user is home and can cook.
                guard block.forcesPortable else { return false }
                if displayed >= block.start, displayed <= block.end {
                    return true
                }
                // Edge proximity — too tight before/after the block.
                let preGap = block.start.timeIntervalSince(displayed)
                if preGap > 0, preGap < edgeWindow {
                    return true
                }
                let postGap = displayed.timeIntervalSince(block.end)
                if postGap > 0, postGap < edgeWindow {
                    return true
                }
                return false
            }

            return FuelMealRow(
                meal: meal,
                originalTime: original,
                displayedTime: displayed,
                shiftMinutes: Int(shift / 60),
                isPortableOnly: conflict != nil,
                conflictingEventTitle: conflict?.title
            )
        }
    }
}
