//
// MacroCarryoverService.swift
// Tempo
//
// Bridges the MacroCarryover SwiftData model to the daily-reset and
// target-calculator hooks. Two callers:
//
//   - DailyResetCoordinator finalizes yesterday → calls
//     `captureCarryoverIfNeeded(for:in:)` to create a row when
//     yesterday's (target − actual) is over the threshold.
//   - NutritionTargetCalculator.targetsForToday reads
//     `activeAdjustmentForToday(in:)` to bump targets by the sum of
//     today's per-day shares.
//
// All operations are pure functions over SwiftData fetches — keeps
// the carryover behavior testable in isolation.
//

import Foundation
import SwiftData

@MainActor
enum MacroCarryoverService {
    /// Minimum deficit/surplus before a carryover row is created.
    /// Below these, the imbalance is rounding error — don't pollute
    /// future days with it.
    static let kcalThreshold: Double = 200
    static let proteinThreshold: Double = 15

    /// Default spread window. 5 days = 20%/day adjustment. Picked
    /// because a 500-kcal deficit becomes a +100-kcal/day bump —
    /// large enough to matter, small enough to absorb without
    /// reshaping the plan.
    static let defaultSpreadDays: Int = 5

    /// Per-day macro share aggregated across all currently-active
    /// carryover rows. Add to today's base targets to get the
    /// rebalance-adjusted targets.
    struct DailyAdjustment: Equatable {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        /// True when at least one row contributed. Used by the UI to
        /// surface a "rebalancing from earlier this week" subhead.
        var hasActiveCarryover: Bool

        static let zero = DailyAdjustment(
            calories: 0, protein: 0, carbs: 0, fat: 0,
            hasActiveCarryover: false
        )
    }

    // MARK: - Capture (called from DailyResetCoordinator)

    /// Computes yesterday's (target − actual) and creates a
    /// MacroCarryover row when the deltas cross threshold. Idempotent:
    /// returns early if a row already exists for the same sourceDate.
    /// Also bumps `daysApplied` and expires any currently-active row
    /// that has reached its spreadDays.
    static func captureCarryoverIfNeeded(
        for closedOutDate: Date,
        in context: ModelContext
    ) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: closedOutDate)

        // Idempotency guard.
        let existingDesc = FetchDescriptor<MacroCarryover>(
            predicate: #Predicate { row in
                row.sourceDate == dayStart
            }
        )
        if let existing = try? context.fetch(existingDesc), !existing.isEmpty {
            tickActiveCarryovers(in: context)
            return
        }

        // Compute yesterday's actual macros from MealLog.
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            tickActiveCarryovers(in: context)
            return
        }
        let mealDesc = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { log in
                log.dayDate >= dayStart && log.dayDate < dayEnd
            }
        )
        let logs = (try? context.fetch(mealDesc)) ?? []
        // Skip when the day had nothing logged — that's a "missed
        // tracking" day, not a real deficit. Pulling 2000 kcal forward
        // from a Sunday the user simply didn't track would corrupt
        // the next week's plan.
        guard !logs.isEmpty else {
            tickActiveCarryovers(in: context)
            return
        }
        let actual = MacroSnapshot(
            calories: logs.reduce(0.0) { $0 + $1.totalCalories },
            protein: logs.reduce(0.0) { $0 + $1.totalProtein },
            carbs: logs.reduce(0.0) { $0 + $1.totalCarbs },
            fat: logs.reduce(0.0) { $0 + $1.totalFat }
        )

        // Read the day's target by re-running the calculator on the
        // plan that existed yesterday. (PlannedMeals stay around, so
        // their summed macros are a faithful reproduction.)
        let plannedDesc = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= dayStart && meal.dayDate < dayEnd
            }
        )
        let plannedMeals = (try? context.fetch(plannedDesc)) ?? []
        guard !plannedMeals.isEmpty else {
            // Same as no-log: no plan = no target to compare against.
            tickActiveCarryovers(in: context)
            return
        }
        let dietaryDesc = FetchDescriptor<DietaryProfile>()
        let dietaryProfile = (try? context.fetch(dietaryDesc))?.first
        let targets = NutritionTargetCalculator.targetsForToday(
            todayMeals: plannedMeals,
            dietaryProfile: dietaryProfile
        )

        let delta = MacroSnapshot(
            calories: Double(targets.calories) - actual.calories,
            protein: Double(targets.protein) - actual.protein,
            carbs: Double(targets.carbs) - actual.carbs,
            fat: Double(targets.fat) - actual.fat
        )

        // Tick BEFORE inserting the new row so today's targets see the
        // newly-created carryover as ticks-applied=0 (full share today).
        tickActiveCarryovers(in: context)

        // Only persist when the deltas matter. Below threshold, the
        // user effectively hit their target.
        guard abs(delta.calories) >= kcalThreshold
            || abs(delta.protein) >= proteinThreshold
        else {
            return
        }
        let row = MacroCarryover(
            sourceDate: dayStart,
            calories: delta.calories,
            protein: delta.protein,
            carbs: delta.carbs,
            fat: delta.fat,
            spreadDays: defaultSpreadDays
        )
        context.insert(row)
        try? context.save()
    }

    // MARK: - Read (called from NutritionTargetCalculator)

    /// Returns the aggregate per-day adjustment for today by summing
    /// the per-day shares of every still-active carryover row. Safe
    /// to call without a daily-reset run; expired rows contribute
    /// zero.
    static func activeAdjustmentForToday(in context: ModelContext) -> DailyAdjustment {
        let desc = FetchDescriptor<MacroCarryover>(
            predicate: #Predicate<MacroCarryover> { row in
                !row.isExpired
            }
        )
        guard let rows = try? context.fetch(desc), !rows.isEmpty else {
            return .zero
        }
        var agg = DailyAdjustment.zero
        for row in rows where row.daysRemaining > 0 {
            agg.calories += row.perDayCalories
            agg.protein += row.perDayProtein
            agg.carbs += row.perDayCarbs
            agg.fat += row.perDayFat
            agg.hasActiveCarryover = true
        }
        return agg
    }

    // MARK: - Private helpers

    /// Advances every currently-active carryover by one day. Expires
    /// rows that have applied their full spread. Called from
    /// captureCarryoverIfNeeded so each daily-reset tick exactly
    /// once.
    private static func tickActiveCarryovers(in context: ModelContext) {
        let desc = FetchDescriptor<MacroCarryover>(
            predicate: #Predicate<MacroCarryover> { row in
                !row.isExpired
            }
        )
        guard let rows = try? context.fetch(desc) else { return }
        for row in rows {
            row.daysApplied += 1
            if row.daysApplied >= row.spreadDays {
                row.isExpired = true
            }
        }
        try? context.save()
    }

    private struct MacroSnapshot {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
}
