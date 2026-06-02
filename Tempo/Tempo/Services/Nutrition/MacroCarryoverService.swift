//
// MacroCarryoverService.swift
// Tempo
//
// Bridges the MacroCarryover SwiftData model to the daily-reset and
// target-calculator hooks. Two callers:
//
//   - DailyResetCoordinator finalizes yesterday → calls
//     `captureCarryoverIfNeeded(for:in:onMissedLog:)` to create a row
//     when yesterday ended in a real, small DEFICIT.
//   - NutritionTargetCalculator.targetsForToday reads
//     `activeAdjustmentForToday(in:)` to bump today's targets by the
//     single active refund.
//
// §4 behavior (2026-06-02) — CONSERVATIVE single-day refund + missed-log
// gate. This replaced the old 5-day deficit spread (two overlapping
// deficit systems was a bug factory). The rules, in order:
//
//   1. MISSED-LOG GATE (before anything else): if the day logged < 50%
//      of its target calories AND ≥1 planned meal is still unmarked
//      (.planned), it is a PROBABLE MISSED LOG, not a real deficit
//      (e.g. logged breakfast + dinner, forgot lunch → looks like a
//      ~2000 fake deficit). Fire the `onMissedLog` notification hook
//      and carry NOTHING. This is the partial-log case the old
//      zero-logs-only guard sailed past.
//   2. SURPLUS → never carried. Only nudge up, never down — a surplus
//      is surfaced as info elsewhere, not subtracted from tomorrow.
//   3. DEFICIT → capped. A genuine small shortfall refunds at most
//      `maxRefundCalories` onto the NEXT day only (spreadDays 1), with
//      macros scaled proportionally so the refund stays internally
//      consistent.
//
// All operations are pure functions over SwiftData fetches (plus an
// injectable notification closure) — keeps the behavior testable in
// isolation with no NotificationService dependency.
//

import Foundation
import SwiftData

@MainActor
enum MacroCarryoverService {
    /// Minimum deficit before a refund row is created. Below this the
    /// imbalance is rounding error — don't pollute tomorrow with it.
    static let kcalThreshold: Double = 200
    static let proteinThreshold: Double = 15

    /// Hard ceiling on the calorie refund applied to the next day. A
    /// genuine shortfall nudges tomorrow up by at most this much; we do
    /// NOT dump the full delta forward (the behavior Nicola rejected).
    /// When the raw deficit exceeds this, every macro is scaled by the
    /// same ratio so the refund stays internally consistent.
    static let maxRefundCalories: Double = 150

    /// Below this fraction of target calories — combined with ≥1
    /// unmarked planned meal — the day reads as a probable MISSED LOG
    /// rather than a real deficit, so nothing is carried.
    static let missedLogFraction: Double = 0.5

    /// §4: a refund lands on a single day. (Field retained on the model
    /// for generality; every row created today uses 1.)
    static let refundSpreadDays: Int = 1

    /// Per-day macro share aggregated across all currently-active
    /// carryover rows. Add to today's base targets to get the
    /// rebalance-adjusted targets.
    struct DailyAdjustment: Equatable {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        /// True when a refund row contributed to today's targets. Sole
        /// consumer today is NutritionTargetCalculator's guard (skip the
        /// add when false). No UI copy reads this — and any future copy
        /// must describe a SINGLE-DAY refund, not a multi-day spread
        /// (the 5-day spread was removed in §4).
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
        in context: ModelContext,
        onMissedLog: (() -> Void)? = nil
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
        // the next day's target. (Preserved from the original guard.)
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
            // No plan = no target to compare against. Same as no-log.
            tickActiveCarryovers(in: context)
            return
        }
        let dietaryDesc = FetchDescriptor<DietaryProfile>()
        let dietaryProfile = (try? context.fetch(dietaryDesc))?.first
        let targets = NutritionTargetCalculator.targetsForToday(
            todayMeals: plannedMeals,
            dietaryProfile: dietaryProfile
        )

        // §4 MISSED-LOG GATE — the key piece. A day that logged less
        // than half its target calories WHILE still having ≥1 planned
        // meal unmarked is almost certainly a forgotten log (e.g.
        // logged breakfast + dinner, forgot lunch), not a real deficit.
        // Notify and carry nothing — this is exactly the partial-log
        // case the old zero-logs-only guard let through.
        let hasUnmarkedMeal = plannedMeals.contains { $0.status == .planned }
        let targetCalories = Double(targets.calories)
        let implausiblyLow = targetCalories > 0
            && actual.calories < missedLogFraction * targetCalories
        if implausiblyLow && hasUnmarkedMeal {
            tickActiveCarryovers(in: context)
            onMissedLog?()
            return
        }

        let delta = MacroSnapshot(
            calories: Double(targets.calories) - actual.calories,
            protein: Double(targets.protein) - actual.protein,
            carbs: Double(targets.carbs) - actual.carbs,
            fat: Double(targets.fat) - actual.fat
        )

        // Tick BEFORE inserting the new row so today's targets see the
        // newly-created refund as ticks-applied=0 (full share today).
        tickActiveCarryovers(in: context)

        // §4 CONSERVATIVE rules:
        //   - Only carry a real DEFICIT (under-ate). Surpluses are never
        //     subtracted from tomorrow — only nudge up, never down.
        //   - The deficit must clear the threshold (else it's noise).
        //   - The calorie deficit must be strictly positive: a
        //     protein-only shortfall shouldn't produce a zero/negative
        //     calorie refund.
        guard delta.calories >= kcalThreshold
            || delta.protein >= proteinThreshold
        else {
            return
        }
        guard delta.calories > 0 else {
            return
        }

        // Cap the calorie refund and scale every macro by the same ratio
        // so the refund stays internally consistent (capped kcal implies
        // proportionally capped P/C/F).
        let scale = delta.calories > maxRefundCalories
            ? maxRefundCalories / delta.calories
            : 1.0
        let row = MacroCarryover(
            sourceDate: dayStart,
            calories: delta.calories * scale,
            protein: max(0, delta.protein) * scale,
            carbs: max(0, delta.carbs) * scale,
            fat: max(0, delta.fat) * scale,
            spreadDays: refundSpreadDays
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
