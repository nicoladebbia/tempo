//
// MealRedistributionPrompts.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import Foundation

// MARK: - MealRedistributionPrompts

/// Prompts for the AI skip-redistribution call. Claude Haiku produces a
/// per-meal macro adjustment for the remaining meals when one meal is
/// skipped. Deterministic shift (`MealShiftPlanner`) handles *time*; this
/// handles *macros*, where the right answer depends on recovery context,
/// time of day, and which meals are still ahead — judgment territory the
/// model is good at.
enum MealRedistributionPrompts {
    static let systemPrompt = """
    You are the nutrition arm of Tempo, a drill-sergeant life operating system for student-athletes. \
    You decide how to redistribute the macros of a SKIPPED meal across the remaining planned meals \
    of the day. You optimise for total daily-target compliance, recovery state, and meal-spacing realism.

    <voice>
    - No fluff. Numbers and one-sentence reasoning.
    - You are not a chef. You are a programmer of fuel.
    </voice>

    <hard_rules>
    - Never raise any single meal more than 30% above its original calorie target.
    - Never raise any single meal more than 30% above its original protein target.
    - When recovery is RED (<34) or sleep <6h, prefer LESS redistribution — favour leaving the day under target rather than forcing a single oversized dinner.
    - When recovery is GREEN (≥67) AND it's pre-dinner, redistribute MORE — body can use it.
    - Snack absorbs preferentially when:
      * Skipped meal was breakfast and lunch already happened.
      * Recovery is poor (smaller, more frequent intake aids gut comfort).
    - Dinner cannot absorb more than 50% of the skipped meal alone.
    - If a meal has already been eaten (status=eaten), it CANNOT receive redistribution — its targets are locked.
    - Output ONLY valid JSON. No markdown, no preamble.
    </hard_rules>
    """

    /// Build the user prompt for a redistribution call.
    static func redistributePrompt(
        skippedMealName: String,
        skippedMealNumber: Int,
        skippedCalories: Int,
        skippedProtein: Int,
        skippedCarbs: Int,
        skippedFat: Int,
        remainingMeals: [RemainingMealInput],
        timeOfDay: String,
        recoveryScore: Double?,
        sleepHours: Double?,
        strain: Double?,
        dayType: String
    ) -> String {
        let remainingBlock = remainingMeals.map { meal in
            """
            - mealNumber \(meal.mealNumber) (\(meal.name), status=\(meal.status), scheduled \(meal.scheduledTime)): \
            cal=\(meal.calories), p=\(meal.protein)g, c=\(meal.carbs)g, f=\(meal.fat)g
            """
        }.joined(separator: "\n")

        let recoveryStr = recoveryScore.map { "\(Int($0))" } ?? "unknown"
        let sleepStr = sleepHours.map { String(format: "%.1f", $0) } ?? "unknown"
        let strainStr = strain.map { String(format: "%.1f", $0) } ?? "unknown"

        return """
        The user just SKIPPED a meal. Redistribute its macros intelligently across the meals that are still PLANNED today.

        <skipped_meal>
        - Name: \(skippedMealName)
        - mealNumber: \(skippedMealNumber)
        - Macros: \(skippedCalories) kcal, \(skippedProtein)g P, \(skippedCarbs)g C, \(skippedFat)g F
        </skipped_meal>

        <remaining_meals>
        \(remainingBlock)
        </remaining_meals>

        <context>
        - Time of day: \(timeOfDay)
        - Day type: \(dayType)
        - Recovery score: \(recoveryStr) (0-100, higher = better)
        - Sleep last night: \(sleepStr) hours
        - Yesterday strain: \(strainStr) (0-21)
        </context>

        Decide how to distribute the skipped macros. You may leave some macros UN-redistributed when:
        - Recovery is poor and oversized portions risk discomfort.
        - The remaining meals are too few/late to absorb the load.

        Return ONLY this JSON shape (start with {, no markdown):
        {
            "adjustments": [
                {
                    "mealNumber": 2,
                    "addCalories": 150,
                    "addProtein": 12,
                    "addCarbs": 18,
                    "addFat": 4
                }
            ],
            "totalDropped": {
                "calories": 0,
                "protein": 0,
                "carbs": 0,
                "fat": 0
            },
            "reasoning": "One sentence on why this distribution."
        }

        Rules:
        - Only include mealNumbers that appear in <remaining_meals> with status=planned.
        - The sum of addCalories + totalDropped.calories must equal \(skippedCalories) (same for each macro).
        - All add* values must be ≥ 0.
        - "reasoning" must be one sentence, under 120 chars.
        """
    }
}

// MARK: - RemainingMealInput

/// Lightweight snapshot of a planned meal used to feed the redistribution
/// prompt. Decoupled from `PlannedMeal` so the service stays testable.
struct RemainingMealInput: Sendable {
    let mealNumber: Int
    let name: String
    let scheduledTime: String
    let status: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
}

// MARK: - Decoded response

/// JSON shape the AI returns. Maps each remaining meal's additive delta.
struct MealRedistributionResponse: Codable, Sendable {
    struct Adjustment: Codable, Sendable {
        let mealNumber: Int
        let addCalories: Double
        let addProtein: Double
        let addCarbs: Double
        let addFat: Double
    }

    struct Dropped: Codable, Sendable {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    let adjustments: [Adjustment]
    let totalDropped: Dropped
    let reasoning: String
}
