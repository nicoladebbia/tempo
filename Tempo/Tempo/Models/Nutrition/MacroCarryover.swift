//
// MacroCarryover.swift
// Tempo
//
// Per-day record of a day's macro DEFICIT, used to gently refund a
// portion of an under-eaten day onto the NEXT day only. Created at
// daily-reset time when the closed-out day's logged macros fall short
// of its target by enough to matter.
//
// §4 semantics (2026-06-02): this is a CONSERVATIVE single-day refund,
// NOT a 5-day spread. `spreadDays` defaults to 1 so a row applies its
// full (capped) share once and expires the next tick. The legacy
// 5-day spread was removed — two overlapping deficit systems was a bug
// factory, and dumping a stale deficit forward over many days is
// exactly the behavior Nicola rejected. Surpluses are never carried
// (only-nudge-up), and the calorie refund is capped (see
// MacroCarryoverService) so a big logged shortfall can't balloon the
// next day's target. The field name "carryover" is now a slight
// misnomer kept to avoid a persisted-model migration.
//
// Lifecycle:
//   1. DailyResetCoordinator finalizes yesterday → MacroCarryoverService
//      writes at most one row capturing the capped (target − actual)
//      deficit for kcal/P/C/F, with spreadDays = 1.
//   2. NutritionTargetCalculator.targetsForToday reads any unexpired
//      carryover and adds its per-day share (= full delta at
//      spreadDays 1) to today's targets.
//   3. On the next daily-reset tick daysApplied reaches spreadDays and
//      the row expires, so the refund lands on exactly one day.
//
// The 1/N split math is retained (perDay* properties) so the field
// stays general, but in practice N == 1 for every row created today.
//

import Foundation
import SwiftData

@Model
final class MacroCarryover {
    @Attribute(.unique) var id: UUID
    /// Calendar day this carryover was generated FROM (i.e. the day
    /// that finished with the deficit/surplus). Stored at startOfDay.
    var sourceDate: Date
    /// Total macro delta = target − actual. Positive = under-ate
    /// (eat more on follow-up days), negative = over-ate (eat less).
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// How many days the delta is applied over. Default 1 (§4: a
    /// single-day conservative refund). One row per source day so the
    /// value is captured immutably even if the global default changes.
    var spreadDays: Int
    /// Counter incremented by each daily-reset run while the row is
    /// still active. When daysApplied == spreadDays the row stops
    /// contributing.
    var daysApplied: Int
    /// True once daysApplied reaches spreadDays. Hard delete is
    /// avoided so the Coach context can still reference recent
    /// rebalances historically.
    var isExpired: Bool

    init(
        sourceDate: Date,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        spreadDays: Int = 1
    ) {
        self.id = UUID()
        self.sourceDate = Calendar.current.startOfDay(for: sourceDate)
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.spreadDays = max(1, spreadDays)
        self.daysApplied = 0
        self.isExpired = false
    }

    /// Per-day share when applied to today's targets. Flat 1/N split;
    /// with the §4 default of spreadDays == 1 this is the identity
    /// (the full delta lands on the one day).
    var perDayCalories: Double { calories / Double(spreadDays) }
    var perDayProtein: Double { protein / Double(spreadDays) }
    var perDayCarbs: Double { carbs / Double(spreadDays) }
    var perDayFat: Double { fat / Double(spreadDays) }

    /// Remaining days the row will contribute. Used by the rebalance
    /// service to know how many ticks are left before expiry.
    var daysRemaining: Int {
        max(0, spreadDays - daysApplied)
    }
}
