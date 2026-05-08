//
// TDEECalculator.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation

// MARK: - MacroTargets

struct MacroTargets {
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int

    /// Verify the macro invariant: P*4 + C*4 + F*9 = calories (within rounding tolerance).
    var macroCalories: Int {
        proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9
    }
}

// MARK: - TDEEResult

struct TDEEResult {
    let tdee: Double
    let bmr: Double
    let leanMassKg: Double?
    let adjustedCalories: Int // after goal adjustment
    let macroTargets: MacroTargets
    let dayTypeTargets: [DayType: MacroTargets]
}

// MARK: - TDEECalculator

enum TDEECalculator {
    // MARK: - Main Calculation

    /// Calculate TDEE, adjusted calories, and per-day-type macro targets.
    ///
    /// Uses Mifflin-St Jeor as baseline, Katch-McArdle when body fat is known (averages both),
    /// and blends with Whoop TDEE when available (with 0.9 correction for wrist HR overestimation).
    static func calculate(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        biologicalSex: BiologicalSex,
        bodyFatPercent: Double?,
        trainingFrequency: Int,
        whoopAverageTDEE: Double?,
        goal: DietaryGoal
    ) -> TDEEResult {
        // ── Step 1: BMR ──────────────────────────────────────────

        let mifflinBMR = mifflinStJeor(
            weightKg: weightKg,
            heightCm: heightCm,
            age: age,
            biologicalSex: biologicalSex
        )

        var leanMassKg: Double?
        let bmr: Double

        if let bf = bodyFatPercent, bf > 0, bf < 60 {
            let lean = weightKg * (1.0 - bf / 100.0)
            leanMassKg = lean
            let katchBMR = katchMcArdle(leanMassKg: lean)
            bmr = (mifflinBMR + katchBMR) / 2.0
        } else {
            bmr = mifflinBMR
        }

        // ── Step 2: TDEE from activity multiplier ────────────────

        let activityMultiplier = activityFactor(trainingFrequency: trainingFrequency)
        let calculatedTDEE = bmr * activityMultiplier

        // ── Step 3: Whoop blend ──────────────────────────────────

        let tdee: Double
        if let whoopTDEE = whoopAverageTDEE, whoopTDEE > 0 {
            let correctedWhoop = whoopTDEE * 0.9 // wrist HR overestimation correction
            tdee = 0.6 * correctedWhoop + 0.4 * calculatedTDEE
        } else {
            tdee = calculatedTDEE
        }

        // ── Step 4: Goal adjustment with safety rails ────────────

        let adjustedCalories = applyGoalAdjustment(
            tdee: tdee,
            goal: goal,
            bodyFatPercent: bodyFatPercent
        )

        // ── Step 5: Macro targets per day type ───────────────────

        let referenceWeight = leanMassKg ?? weightKg
        var dayTypeTargets: [DayType: MacroTargets] = [:]

        for dayType in DayType.allCases {
            let proteinPerKg = proteinMultiplier(for: dayType)
            let targets = buildMacroTargets(
                calories: adjustedCalories,
                proteinPerKg: proteinPerKg,
                referenceWeight: referenceWeight,
                bodyWeightKg: weightKg
            )
            dayTypeTargets[dayType] = targets
        }

        // Default macro targets use strength day as the primary target
        // (conservative: higher protein is safer than lower)
        let defaultTargets = dayTypeTargets[.strength]!

        return TDEEResult(
            tdee: tdee,
            bmr: bmr,
            leanMassKg: leanMassKg,
            adjustedCalories: adjustedCalories,
            macroTargets: defaultTargets,
            dayTypeTargets: dayTypeTargets
        )
    }

    // MARK: - BMR Formulas

    /// Mifflin-St Jeor equation: 10*W + 6.25*H - 5*A + sexOffset
    private static func mifflinStJeor(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        biologicalSex: BiologicalSex
    ) -> Double {
        let sexOffset: Double = biologicalSex == .male ? 5.0 : -161.0
        return 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(age) + sexOffset
    }

    /// Katch-McArdle equation: 370 + 21.6 * leanMass
    private static func katchMcArdle(leanMassKg: Double) -> Double {
        370.0 + 21.6 * leanMassKg
    }

    // MARK: - Activity Factor

    /// Maps weekly training frequency to activity multiplier.
    private static func activityFactor(trainingFrequency: Int) -> Double {
        switch trainingFrequency {
        case 0: 1.2 // sedentary
        case 1 ... 2: 1.375 // lightly active
        case 3 ... 4: 1.55 // moderately active
        case 5 ... 6: 1.725 // very active
        default: 1.9 // extra active (7+)
        }
    }

    // MARK: - Goal Adjustment

    /// Apply calorie adjustment based on dietary goal, with safety limits.
    /// - Cut: -300 to -500 based on BF% (higher BF = larger deficit allowed)
    /// - Maintain: no change
    /// - Lean Gain: +200 to +350 based on BF% (lower BF = larger surplus allowed)
    /// Safety: max 25% deficit, max 15% surplus
    private static func applyGoalAdjustment(
        tdee: Double,
        goal: DietaryGoal,
        bodyFatPercent: Double?
    ) -> Int {
        let rawAdjustment: Double = switch goal {
        case .cut:
            // Higher body fat -> larger deficit is safe
            if let bf = bodyFatPercent {
                if bf > 20 {
                    -500
                } else if bf > 15 {
                    -400
                } else {
                    -300 // lean individuals: conservative cut
                }
            } else {
                -400 // default moderate cut
            }

        case .maintain:
            0

        case .leanGain:
            // Lower body fat -> can afford a larger surplus (less fat gain risk)
            if let bf = bodyFatPercent {
                if bf < 12 {
                    350
                } else if bf < 18 {
                    250
                } else {
                    200 // higher BF: conservative surplus
                }
            } else {
                250 // default moderate surplus
            }
        }

        let adjusted = tdee + rawAdjustment

        // Safety rails
        let maxDeficit = tdee * 0.75 // no more than 25% deficit
        let maxSurplus = tdee * 1.15 // no more than 15% surplus

        let clamped = max(maxDeficit, min(maxSurplus, adjusted))
        return Int(clamped.rounded())
    }

    // MARK: - Protein Multiplier per Day Type

    /// Protein target in g/kg of lean body mass (or body weight if no BF%).
    private static func proteinMultiplier(for dayType: DayType) -> Double {
        switch dayType {
        case .rest: 1.6
        case .cardio: 1.8
        case .strength: 2.0
        case .soccer: 2.0
        case .double: 2.2
        }
    }

    // MARK: - Macro Target Builder

    /// Build macro targets ensuring the invariant: P*4 + C*4 + F*9 = calories.
    /// - Protein: based on day type multiplier * reference weight
    /// - Fat: minimum 0.5g/kg body weight, then fill ~25% of remaining calories
    /// - Carbs: fill remaining calories
    private static func buildMacroTargets(
        calories: Int,
        proteinPerKg: Double,
        referenceWeight: Double,
        bodyWeightKg: Double
    ) -> MacroTargets {
        // Protein
        let proteinGrams = Int((proteinPerKg * referenceWeight).rounded())
        let proteinCalories = proteinGrams * 4

        // Fat — minimum 0.5g/kg, aim for ~25% of total calories but respect minimum
        let fatMinimum = Int((0.5 * bodyWeightKg).rounded())
        let fatFromPercent = Int((Double(calories) * 0.25 / 9.0).rounded())
        let fatGrams = max(fatMinimum, fatFromPercent)
        let fatCalories = fatGrams * 9

        // Carbs — fill remaining calories
        let remainingCalories = max(0, calories - proteinCalories - fatCalories)
        let carbsGrams = remainingCalories / 4

        // Recalculate calories to enforce the invariant exactly
        let finalCalories = proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9

        return MacroTargets(
            calories: finalCalories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams
        )
    }
}
