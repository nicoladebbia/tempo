//
// NutritionCoachPrompts.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation

// MARK: - Nutrition Coach Prompts

/// Static prompt templates for each nutrition coaching feature.
/// Per AI_INTELLIGENCE_ENGINE.md Section 3 — all prompts use XML tags for structured context,
/// reference exact numbers, and include safety rails.
/// Voice follows UX_COPY_BIBLE.md Section 1.1: Drill Sergeant default.
enum NutritionCoachPrompts {
    // MARK: - System Prompt

    /// Shared system prompt identity fragment for all nutrition coaching features.
    /// Per AI_INTELLIGENCE_ENGINE.md: system prompt defines persona and safety rules.
    static let systemPrompt = """
    You are the nutrition arm of Tempo, a drill-sergeant life operating system for student-athletes. \
    You analyze meal data and biometric data to deliver direct, actionable nutrition coaching.

    <voice>
    - Commanding, specific, no fluff. Short sentences.
    - Reference exact numbers: "142g protein" not "good protein intake".
    - Praise only when earned, briefly: "Solid." then move on.
    - When wrong, say it directly: "That's 400 kcal short. Fix it."
    - Food as fuel language, not wellness language. Performance nutrition.
    - When recovery is low, nutrition becomes protective -- prioritize anti-inflammatory foods and adequate calories.
    - Use "target" not "goal". Use "hit" not "reach". Use "log" not "record".
    - Never use "please", "maybe", "consider", or "journey".
    - Active voice only. Imperative mood for actions.
    </voice>

    <safety>
    - NEVER suggest below 1,500 kcal/day for any reason.
    - NEVER suggest skipping meals or extended fasting.
    - NEVER recommend specific supplements, brands, or products.
    - NEVER give medical or clinical nutrition advice.
    - NEVER shame food choices -- critique macro impact only.
    - NEVER reference body weight, body fat percentage, or appearance.
    - NEVER use emojis.
    - NEVER diagnose nutrient deficiencies.
    - Output ONLY coaching text. No greetings, no sign-offs, no "Here's my analysis:" preambles.
    - ONLY reference numbers and facts provided in the <data> section. Do not invent statistics.
    </safety>
    """

    // MARK: - Meal Feedback Prompt

    /// Quick feedback on a just-logged meal. 2-3 sentences.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 2.2: Haiku, temp 0.4, max 150 tokens.
    static func mealFeedbackPrompt(
        mealType: String,
        mealCalories: Double,
        mealProtein: Double,
        mealCarbs: Double,
        mealFat: Double,
        mealItems: String,
        todayCalories: Double,
        todayProtein: Double,
        todayCarbs: Double,
        todayFat: Double,
        todayMealsLogged: Int,
        calorieTarget: Double,
        proteinTarget: Double,
        carbsTarget: Double,
        fatTarget: Double,
        mealsPerDay: Int,
        recoveryZone: String?,
        trainingToday: String?
    ) -> String {
        var prompt = """
        Analyze this meal and give 2-3 sentences of feedback. Focus on how it impacts today's macro targets.

        <data>
        <meal>
        - Type: \(mealType)
        - Items: \(mealItems)
        - Calories: \(Int(mealCalories)) kcal
        - Protein: \(Int(mealProtein))g
        - Carbs: \(Int(mealCarbs))g
        - Fat: \(Int(mealFat))g
        </meal>

        <today_so_far>
        - Total calories (including this meal): \(Int(todayCalories)) kcal / \(Int(calorieTarget)) target
        - Total protein: \(Int(todayProtein))g / \(Int(proteinTarget))g target
        - Total carbs: \(Int(todayCarbs))g / \(Int(carbsTarget))g target
        - Total fat: \(Int(todayFat))g / \(Int(fatTarget))g target
        - Meals logged: \(todayMealsLogged) / \(mealsPerDay) planned
        </today_so_far>
        """

        if let zone = recoveryZone {
            prompt += "\n\n<recovery_zone>\(zone)</recovery_zone>"
        }

        if let training = trainingToday {
            prompt += "\n\n<training_today>\(training)</training_today>"
        }

        prompt += """

        </data>

        Rules:
        - 2-3 sentences maximum.
        - Reference specific numbers from the meal and the remaining budget.
        - If protein is tracking ahead, acknowledge briefly. If behind, prescribe what's needed in remaining meals.
        - If this is the last meal of the day, assess the full day.
        - If recovery is yellow/red, emphasize adequate calorie intake.
        - Output ONLY the feedback text. No labels, no preamble.
        """

        return prompt
    }

    // MARK: - Daily Summary Prompt

    /// End-of-day nutrition summary. 3-5 sentences.
    /// Per AI_INTELLIGENCE_ENGINE.md: Haiku, temp 0.4, max 300 tokens.
    static func dailySummaryPrompt(
        meals: [(type: String, calories: Double, protein: Double, carbs: Double, fat: Double, time: String)],
        totalCalories: Double,
        totalProtein: Double,
        totalCarbs: Double,
        totalFat: Double,
        calorieTarget: Double,
        proteinTarget: Double,
        carbsTarget: Double,
        fatTarget: Double,
        mealsLogged: Int,
        mealsPlanned: Int,
        recoveryScore: Double?,
        recoveryZone: String?,
        tomorrowTraining: String?
    ) -> String {
        var mealLines = ""
        for meal in meals {
            mealLines += "- \(meal.type) (\(meal.time)): \(Int(meal.calories)) kcal, \(Int(meal.protein))g P, \(Int(meal.carbs))g C, \(Int(meal.fat))g F\n"
        }

        let calDelta = Int(totalCalories - calorieTarget)
        let protDelta = Int(totalProtein - proteinTarget)

        var prompt = """
        Generate an end-of-day nutrition summary. 3-5 sentences.

        <data>
        <meals>
        \(mealLines)</meals>

        <daily_totals>
        - Calories: \(Int(totalCalories)) kcal / \(Int(calorieTarget)) target (\(calDelta > 0 ? "+" : "")\(calDelta))
        - Protein: \(Int(totalProtein))g / \(Int(proteinTarget))g target (\(protDelta > 0 ? "+" : "")\(protDelta)g)
        - Carbs: \(Int(totalCarbs))g / \(Int(carbsTarget))g target
        - Fat: \(Int(totalFat))g / \(Int(fatTarget))g target
        - Meals logged: \(mealsLogged) / \(mealsPlanned) planned
        </daily_totals>
        """

        if let score = recoveryScore, let zone = recoveryZone {
            prompt += "\n\n<recovery>Score: \(Int(score))% (\(zone))</recovery>"
        }

        if let training = tomorrowTraining {
            prompt += "\n\n<tomorrow>Training: \(training)</tomorrow>"
        }

        prompt += """

        </data>

        Rules:
        - 3-5 sentences. Lead with the verdict: did they hit targets or not?
        - Reference exact calorie and protein deltas.
        - If meals were missed (logged < planned), call it out.
        - If protein target was missed, specify by how much and when the shortfall happened.
        - If tomorrow has training, give one pre-fueling note for tomorrow morning.
        - If recovery is yellow/red, praise adequate calorie intake or critique shortfall.
        - Output ONLY the summary text.
        """

        return prompt
    }

    // MARK: - Weekly Review Prompt

    /// Weekly nutrition analysis. Returns structured JSON.
    /// Per AI_INTELLIGENCE_ENGINE.md: Sonnet, temp 0.3, max 500 tokens.
    static func weeklyReviewPrompt(
        dailyData: [(date: String, calories: Double, protein: Double, carbs: Double, fat: Double, mealsLogged: Int, mealsPlanned: Int)],
        calorieTarget: Double,
        proteinTarget: Double,
        carbsTarget: Double,
        fatTarget: Double,
        trainingDays: Int,
        prevWeekAdherence: Double?
    ) -> String {
        var dataLines = ""
        for day in dailyData {
            let calPct = calorieTarget > 0 ? Int((day.calories / calorieTarget) * 100) : 0
            let protPct = proteinTarget > 0 ? Int((day.protein / proteinTarget) * 100) : 0
            dataLines += "- \(day.date): \(Int(day.calories)) kcal (\(calPct)%), \(Int(day.protein))g P (\(protPct)%), \(Int(day.carbs))g C, \(Int(day.fat))g F, meals \(day.mealsLogged)/\(day.mealsPlanned)\n"
        }

        let avgCalories = dailyData.isEmpty ? 0 : Int(dailyData.map(\.calories).reduce(0, +) / Double(dailyData.count))
        let avgProtein = dailyData.isEmpty ? 0 : Int(dailyData.map(\.protein).reduce(0, +) / Double(dailyData.count))
        let proteinHitDays = dailyData.count(where: { $0.protein >= proteinTarget })
        let calorieHitDays = dailyData.count(where: { abs($0.calories - calorieTarget) <= calorieTarget * 0.1 })

        var prompt = """
        Analyze this week's nutrition data and generate a structured review.

        <data>
        <daily_nutrition>
        \(dataLines)</daily_nutrition>

        <targets>
        - Calories: \(Int(calorieTarget)) kcal/day
        - Protein: \(Int(proteinTarget))g/day
        - Carbs: \(Int(carbsTarget))g/day
        - Fat: \(Int(fatTarget))g/day
        </targets>

        <summary_stats>
        - Days tracked: \(dailyData.count)
        - Avg daily calories: \(avgCalories) kcal
        - Avg daily protein: \(avgProtein)g
        - Protein target hit: \(proteinHitDays)/\(dailyData.count) days
        - Calorie target hit (within 10%): \(calorieHitDays)/\(dailyData.count) days
        - Training days this week: \(trainingDays)
        """

        if let prev = prevWeekAdherence {
            prompt += "\n- Last week's adherence: \(Int(prev * 100))%"
        }

        prompt += """

        </summary_stats>
        </data>

        Return ONLY valid JSON (no markdown wrapping, no code blocks, start with {) matching this schema:
        {
            "verdict": "string (one-line verdict, max 80 chars, drill-sergeant tone)",
            "analysis": "string (3-5 sentences analyzing patterns, referencing specific days and numbers)",
            "fix": "string (2-3 specific actionable fixes, each referencing data)"
        }

        Rules:
        - The verdict is one sentence that captures the week. Example: "4 of 7 days missed protein. That's a pattern, not a bad day."
        - The analysis must reference specific days by name and specific numbers from the data.
        - The fix must be immediately actionable. Not "eat more protein" but "Add a 40g protein shake after every training session -- that closes the gap on 3 of your miss days."
        - If week-over-week data is available, reference the trend.
        - Do not fabricate numbers. Every number must come from the data above.
        """

        return prompt
    }

    // MARK: - Recovery Nutrition Guidance Prompt

    /// Recovery-aware nutrition guidance for yellow/red Whoop recovery days.
    /// Per AI_INTELLIGENCE_ENGINE.md: Haiku, temp 0.3, max 200 tokens.
    static func recoveryNutritionPrompt(
        recoveryScore: Double,
        recoveryZone: String,
        hrvRmssd: Double,
        restingHeartRate: Double,
        sleepHours: Double?,
        sleepScore: Double?,
        todayCalories: Double,
        todayProtein: Double,
        todayCarbs: Double,
        todayFat: Double,
        calorieTarget: Double,
        proteinTarget: Double,
        trainingToday: String?
    ) -> String {
        var prompt = """
        Recovery is \(recoveryZone). Provide nutrition guidance for today. 3-4 sentences.

        <data>
        <recovery>
        - Score: \(Int(recoveryScore))%
        - Zone: \(recoveryZone)
        - HRV: \(Int(hrvRmssd))ms
        - Resting HR: \(Int(restingHeartRate))bpm
        """

        if let sleepH = sleepHours {
            prompt += "- Sleep: \(String(format: "%.1f", sleepH))h"
            if let sleepS = sleepScore {
                prompt += " (score: \(Int(sleepS))%)"
            }
            prompt += "\n"
        }

        prompt += """
        </recovery>

        <nutrition_so_far>
        - Calories consumed: \(Int(todayCalories)) / \(Int(calorieTarget)) target
        - Protein: \(Int(todayProtein))g / \(Int(proteinTarget))g target
        - Carbs: \(Int(todayCarbs))g
        - Fat: \(Int(todayFat))g
        </nutrition_so_far>
        """

        if let training = trainingToday {
            prompt += "\n<training_today>\(training)</training_today>"
        }

        prompt += """

        </data>

        Rules:
        - 3-4 sentences. Recovery is the priority.
        - Yellow zone: emphasize hitting full calorie target, adequate protein, and hydration timing.
        - Red zone: emphasize calorie surplus (100-200 kcal above target), anti-inflammatory food choices (omega-3s, berries, leafy greens), and front-loading carbs.
        - If training is scheduled on a red day, recommend lighter training AND extra pre-workout carbs.
        - Reference exact numbers from the data. "You're at 1,200 kcal with 800 remaining" not "eat more".
        - NEVER suggest skipping meals or reducing intake on low recovery days.
        - Output ONLY the guidance text.
        """

        return prompt
    }

    // MARK: - Pre-Training Alert Prompt

    /// Alert when carb intake is low before an upcoming workout.
    /// Per AI_INTELLIGENCE_ENGINE.md: Haiku, temp 0.3, max 150 tokens.
    static func preTrainingAlertPrompt(
        hoursUntilTraining: Double,
        workoutType: String,
        carbsConsumed: Double,
        carbTarget: Double,
        proteinConsumed: Double,
        proteinTarget: Double,
        caloriesConsumed: Double,
        calorieTarget: Double,
        lastMealTime: String?
    ) -> String {
        let carbDeficit = Int(carbTarget * 0.5 - carbsConsumed) // Pre-workout: want at least 50% of daily carbs
        let hoursFormatted = String(format: "%.1f", hoursUntilTraining)

        var prompt = """
        Training in \(hoursFormatted) hours. Carb intake is low. Give a pre-training nutrition alert. 2-3 sentences.

        <data>
        <training>
        - Type: \(workoutType)
        - Time until session: \(hoursFormatted)h
        </training>

        <nutrition_status>
        - Carbs consumed: \(Int(carbsConsumed))g / \(Int(carbTarget))g daily target
        - Protein consumed: \(Int(proteinConsumed))g / \(Int(proteinTarget))g daily target
        - Calories consumed: \(Int(caloriesConsumed)) kcal / \(Int(calorieTarget)) target
        """

        if let lastMeal = lastMealTime {
            prompt += "\n- Last meal: \(lastMeal)"
        }

        prompt += """

        </nutrition_status>
        </data>

        Rules:
        - 2-3 sentences maximum.
        - Prescribe a specific pre-workout meal or snack with gram amounts.
        - If <2 hours until training: suggest quick-digesting carbs (banana, rice cakes, white bread). Give specific gram amounts.
        - If 2-4 hours: suggest a balanced mini-meal (carbs + moderate protein). Give specific gram amounts.
        - Reference the carb deficit: "\(carbDeficit > 0 ? "\(carbDeficit)g of carbs short" : "carbs on track")".
        - Never suggest training fasted if carbs are low.
        - Output ONLY the alert text.
        """

        return prompt
    }

    // MARK: - Meal Suggestions Prompt

    /// Suggest meals based on remaining macro budget.
    /// Per AI_INTELLIGENCE_ENGINE.md: Haiku, temp 0.5, max 500 tokens.
    static func mealSuggestionsPrompt(
        caloriesRemaining: Int,
        proteinRemaining: Int,
        carbsRemaining: Int,
        fatRemaining: Int,
        timeOfDay: String,
        isTrainingDay: Bool,
        mealsRemainingCount: Int
    ) -> String {
        """
        Suggest \(min(mealsRemainingCount, 3)) meals that fit the remaining macro budget. Return as JSON.

        <data>
        <remaining_budget>
        - Calories: \(caloriesRemaining) kcal
        - Protein: \(proteinRemaining)g
        - Carbs: \(carbsRemaining)g
        - Fat: \(fatRemaining)g
        </remaining_budget>

        <context>
        - Time of day: \(timeOfDay)
        - Training day: \(isTrainingDay ? "yes" : "no")
        - Meals remaining: \(mealsRemainingCount)
        </context>
        </data>

        Return ONLY valid JSON (no markdown, no code blocks, start with {) matching this schema:
        {
            "suggestions": [
                {
                    "name": "string (meal name, max 40 chars)",
                    "calories": number,
                    "protein": number (grams),
                    "carbs": number (grams),
                    "fat": number (grams),
                    "prep_time": "string (e.g. '10 min', '5 min', '0 min')",
                    "description": "string (one sentence, what it is and why it fits)"
                }
            ]
        }

        Rules:
        - Each suggestion must fit within the remaining budget. Total macros across all suggestions should approximate the budget.
        - If \(mealsRemainingCount) meals remain, divide the budget roughly evenly but front-load protein.
        - If it's a training day, suggest higher-carb options.
        - Prioritize simple, student-friendly meals: chicken, rice, eggs, oats, Greek yogurt, canned tuna, pasta, ground beef, sweet potato, banana.
        - Include prep time (most should be under 15 min).
        - If calories remaining is negative, suggest a very light protein-only option and note the surplus.
        - NEVER suggest supplements or branded products.
        - Every number must be realistic. A chicken breast is ~165 kcal and 31g protein per 100g, not 50g protein.
        """
    }
}
