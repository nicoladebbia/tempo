//
// MacroCarryover.swift
// Tempo
//
// Per-day record of a day's macro deficit/surplus, used to spread the
// imbalance across the next N days instead of dumping it all on the
// next day. Created at daily-reset time when the closed-out day's
// logged macros diverge from its target by enough to matter.
//
// Lifecycle:
//   1. DailyResetCoordinator finalizes yesterday → writes one row
//      capturing (target − actual) for kcal/P/C/F.
//   2. NutritionTargetCalculator.targetsForToday reads any unexpired
//      carryovers and adds 1/spreadDays of each to today's targets.
//   3. Each day a row applies, daysApplied increments. When it hits
//      spreadDays the row is marked expired and stops contributing.
//
// We keep the per-day decay deterministic (1/N flat) rather than
// geometric so the math is obvious and the user can predict the
// rebalance trajectory.
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
    /// How many days to spread the delta across. Default 5; one row
    /// per source day so the value is captured immutably even if the
    /// global default changes.
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
        spreadDays: Int = 5
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

    /// Per-day share when applied to today's targets. Flat 1/N split
    /// — predictable for the user, no surprise jumps.
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
