//
// AdaptiveDietService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - MacroAdjustment

/// Adaptive adjustment to daily macro targets based on recent adherence and biometric data.
struct MacroAdjustment {
    /// Calorie delta (positive = eat more, negative = eat less). Hard cap: [-250, +350].
    let calorieDelta: Int
    /// Protein delta in grams. Hard cap: [0, +35].
    let proteinDelta: Int
    /// Carbs delta in grams. Hard cap: [-25, +60].
    let carbsDelta: Int
    /// Fat delta in grams. Hard cap: [-10, +20].
    let fatDelta: Int
    /// Human-readable explanation of the adjustment. Drill-sergeant voice.
    let explanation: String

    static let zero = MacroAdjustment(
        calorieDelta: 0,
        proteinDelta: 0,
        carbsDelta: 0,
        fatDelta: 0,
        explanation: "No adjustment. Targets unchanged."
    )
}

// MARK: - AdaptiveDietService

/// Pure computation service for daily macro adjustments based on recent adherence and Whoop data.
/// No API calls -- all logic is deterministic.
///
/// Analyzes the last 3 days of actual-vs-planned intake, applies Whoop recovery/strain/sleep
/// modifiers, and returns capped deltas to apply on top of base TDEE targets.
enum AdaptiveDietService {
    private static let logger = Logger.nutrition

    // MARK: - Day Weights (recency-weighted rolling average)

    // Day -1 (yesterday) = 3, Day -2 = 2, Day -3 = 1. Total weight = 6.
    private static let dayWeights: [Double] = [3.0, 2.0, 1.0]
    private static let totalWeight: Double = 6.0

    // MARK: - Hard Caps

    private static let calorieCap = (-250, 350)
    private static let proteinCap = (0, 35)
    private static let carbsCap = (-25, 60)
    private static let fatCap = (-10, 20)

    // MARK: - Calculate Daily Adjustment

    /// Calculate today's macro adjustment based on the last 3 days of adherence and Whoop data.
    ///
    /// - Parameters:
    ///   - modelContext: SwiftData context for querying MealLog and PlannedMeal
    ///   - whoopRecovery: Today's Whoop recovery score (0-100), nil if unavailable
    ///   - whoopStrain: Today's Whoop strain (0-21), nil if unavailable
    ///   - sleepHours: Last night's sleep duration in hours, nil if unavailable
    /// - Returns: A MacroAdjustment with capped deltas and explanation text
    static func calculateDailyAdjustment(
        modelContext: ModelContext,
        whoopRecovery: Double?,
        whoopStrain: Double?,
        sleepHours: Double?
    ) -> MacroAdjustment {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Query last 3 days of data
        var dayDeltas: [(calDelta: Double, protDelta: Double, carbsDelta: Double, fatDelta: Double)] = []

        for dayOffset in 1 ... 3 {
            guard let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }

            let delta = computeDayDelta(for: dayDate, modelContext: modelContext)
            dayDeltas.append(delta)
        }

        guard !dayDeltas.isEmpty else {
            logger.info("No recent meal data found. Returning zero adjustment.")
            return .zero
        }

        // Weighted rolling average
        var weightedCalDelta = 0.0
        var weightedProtDelta = 0.0
        var weightedCarbsDelta = 0.0
        var weightedFatDelta = 0.0

        for (index, delta) in dayDeltas.enumerated() {
            let weight = index < dayWeights.count ? dayWeights[index] : 1.0
            weightedCalDelta += delta.calDelta * weight
            weightedProtDelta += delta.protDelta * weight
            weightedCarbsDelta += delta.carbsDelta * weight
            weightedFatDelta += delta.fatDelta * weight
        }

        weightedCalDelta /= totalWeight
        weightedProtDelta /= totalWeight
        weightedCarbsDelta /= totalWeight
        weightedFatDelta /= totalWeight

        // Start building adjustment
        var calAdj = 0.0
        var protAdj = 0.0
        var carbsAdj = 0.0
        let fatAdj = 0.0
        var explanations: [String] = []

        // ── Surplus Clawback ──────────────────────────────────────
        // If cumulative surplus >400kcal over the window, recover 60% over 3 days (max 200/day)
        let cumulativeSurplus = dayDeltas.reduce(0.0) { $0 + max(0, $1.calDelta) }
        if cumulativeSurplus > 400 {
            let clawback = min(200, (cumulativeSurplus * 0.6) / 3.0)
            calAdj -= clawback
            explanations.append("\(Int(cumulativeSurplus)) kcal surplus over 3 days. Clawing back \(Int(clawback)) kcal today.")
        }

        // ── Deficit Carry-Forward ─────────────────────────────────
        // 30% of yesterday's deficit (max 300kcal, threshold 200kcal)
        if let yesterday = dayDeltas.first, yesterday.calDelta < -200 {
            let deficit = abs(yesterday.calDelta)
            let carryForward = min(300, deficit * 0.30)
            calAdj += carryForward
            explanations.append("Yesterday's \(Int(deficit)) kcal deficit. Adding \(Int(carryForward)) kcal to compensate.")
        }

        // ── Whoop Modifiers ──────────────────────────────────────

        // Low recovery (<33%): cap calorie boost at +100, boost protein +15g
        if let recovery = whoopRecovery, recovery < 33 {
            calAdj = min(calAdj, 100)
            protAdj += 15
            explanations.append("Recovery at \(Int(recovery))%. Capping calorie surplus, adding 15g protein for repair.")
        }

        // High strain (>14): add +25g carbs for glycogen replenishment
        if let strain = whoopStrain, strain > 14 {
            carbsAdj += 25
            explanations.append("High strain (\(String(format: "%.1f", strain))). Adding 25g carbs for glycogen.")
        }

        // Poor sleep (<6h): add +10g protein for recovery support
        if let sleep = sleepHours, sleep < 6 {
            protAdj += 10
            explanations.append("Only \(String(format: "%.1f", sleep))h sleep. Adding 10g protein for recovery.")
        }

        // ── Apply weighted trend adjustments ──────────────────────
        // If consistently under-eating protein, nudge up
        if weightedProtDelta < -10 {
            protAdj += min(15, abs(weightedProtDelta) * 0.5)
            explanations.append("Protein trending \(Int(weightedProtDelta))g below target. Nudging up.")
        }

        // ── Hard Caps ────────────────────────────────────────────
        let finalCal = clamp(Int(calAdj.rounded()), min: calorieCap.0, max: calorieCap.1)
        let finalProt = clamp(Int(protAdj.rounded()), min: proteinCap.0, max: proteinCap.1)
        let finalCarbs = clamp(Int(carbsAdj.rounded()), min: carbsCap.0, max: carbsCap.1)
        let finalFat = clamp(Int(fatAdj.rounded()), min: fatCap.0, max: fatCap.1)

        // Build explanation
        let explanation: String = if explanations.isEmpty {
            "Adherence on track. No adjustment needed."
        } else {
            explanations.joined(separator: " ")
        }

        logger.info("Adaptive adjustment: cal=\(finalCal), prot=\(finalProt), carbs=\(finalCarbs), fat=\(finalFat)")

        return MacroAdjustment(
            calorieDelta: finalCal,
            proteinDelta: finalProt,
            carbsDelta: finalCarbs,
            fatDelta: finalFat,
            explanation: explanation
        )
    }

    // MARK: - Day Delta Computation

    /// Compute actual-vs-planned macro deltas for a single day.
    /// Positive = surplus (ate more than planned), negative = deficit.
    private static func computeDayDelta(
        for dayDate: Date,
        modelContext: ModelContext
    ) -> (calDelta: Double, protDelta: Double, carbsDelta: Double, fatDelta: Double) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: dayDate)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Fetch actual meals logged for this day
        let mealDescriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { meal in
                meal.dayDate >= startOfDay && meal.dayDate < nextDay
            }
        )
        let meals = (try? modelContext.fetch(mealDescriptor)) ?? []

        // Fetch planned meals for this day
        let plannedDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= startOfDay && meal.dayDate < nextDay
            }
        )
        let planned = (try? modelContext.fetch(plannedDescriptor)) ?? []

        // Sum actuals
        let actualCal = meals.reduce(0.0) { $0 + $1.totalCalories }
        let actualProt = meals.reduce(0.0) { $0 + $1.totalProtein }
        let actualCarbs = meals.reduce(0.0) { $0 + $1.totalCarbs }
        let actualFat = meals.reduce(0.0) { $0 + $1.totalFat }

        // Sum planned
        let plannedCal = planned.reduce(0.0) { $0 + $1.totalCalories }
        let plannedProt = planned.reduce(0.0) { $0 + $1.totalProtein }
        let plannedCarbs = planned.reduce(0.0) { $0 + $1.totalCarbs }
        let plannedFat = planned.reduce(0.0) { $0 + $1.totalFat }

        // If no planned meals, cannot compute meaningful delta
        guard plannedCal > 0 else {
            return (calDelta: 0, protDelta: 0, carbsDelta: 0, fatDelta: 0)
        }

        return (
            calDelta: actualCal - plannedCal,
            protDelta: actualProt - plannedProt,
            carbsDelta: actualCarbs - plannedCarbs,
            fatDelta: actualFat - plannedFat
        )
    }

    // MARK: - Utility

    private static func clamp(_ value: Int, min minVal: Int, max maxVal: Int) -> Int {
        max(minVal, min(maxVal, value))
    }
}
