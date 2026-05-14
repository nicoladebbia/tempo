//
// NutritionCoachService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os

// MARK: - NutritionCoachServiceProtocol

protocol NutritionCoachServiceProtocol: Sendable {
    func mealFeedback(
        meal: MealLog,
        todaySummary: DailyNutritionSummary,
        target: ActiveNutritionTarget,
        recoveryZone: String?,
        trainingToday: String?
    ) async throws -> String
    func dailySummary(
        meals: [MealLog],
        summary: DailyNutritionSummary,
        target: ActiveNutritionTarget,
        recovery: WhoopRecoveryData?,
        tomorrowTraining: String?
    ) async throws -> String
    func weeklyReview(
        dailyData: [DailyNutritionSummary],
        targets: ActiveNutritionTarget,
        trainingDays: Int,
        prevWeekAdherence: Double?
    ) async throws -> WeeklyNutritionReview
    func recoveryNutritionGuidance(
        recovery: WhoopRecoveryData,
        sleep: WhoopSleepData?,
        todaySummary: DailyNutritionSummary,
        trainingToday: String?
    ) async throws -> String
    func preTrainingAlert(
        hoursUntilTraining: Double,
        workoutType: String,
        carbsConsumed: Double,
        carbTarget: Double,
        lastMealTime: Date?
    ) async throws -> String
    func mealSuggestions(remainingBudget: MacroBudget, timeOfDay: String, isTrainingDay: Bool) async throws -> [MealSuggestion]
}

// MARK: - NutritionCoachService

/// AI nutrition coaching powered by Claude API.
/// Uses Haiku for real-time features (meal feedback, alerts, daily summary)
/// and Sonnet for weekly analysis.
///
/// Per AI_INTELLIGENCE_ENGINE.md:
/// - Direct Claude API calls for sub-second latency
/// - Circuit breaker protects against cascading failures
/// - Fallback to empty/error states when AI is unavailable
///
/// Per UX_COPY_BIBLE.md Section 1.1:
/// - Drill Sergeant voice: commanding, specific, no fluff
/// - Performance nutrition language, not wellness
@Observable
final class NutritionCoachService: NutritionCoachServiceProtocol, @unchecked Sendable {
    // MARK: - Dependencies

    /// All Claude calls proxy through the Tempo backend per
    /// INTELLIGENCE_REMEDIATION_PLAN.md §3 — the Anthropic key never ships in
    /// the app binary.
    private let apiClient: APIClient
    private let logger = Logger.nutrition

    // MARK: - Retry Configuration

    // Per AI_INTELLIGENCE_ENGINE.md Section 2.3

    private let maxRetries = 2
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Init

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Meal Feedback

    /// Analyze a just-logged meal and provide quick feedback (2-3 sentences).
    /// Model: Haiku | Temp: 0.4 | Max tokens: 150 | Timeout: 10s
    func mealFeedback(
        meal: MealLog,
        todaySummary: DailyNutritionSummary,
        target: ActiveNutritionTarget,
        recoveryZone: String?,
        trainingToday: String?
    ) async throws -> String {
        let itemNames = meal.items.map(\.name).joined(separator: ", ")
        let mealItems = itemNames.isEmpty ? meal.mealType.displayName : itemNames

        let prompt = NutritionCoachPrompts.mealFeedbackPrompt(
            mealType: meal.mealType.displayName,
            mealCalories: meal.totalCalories,
            mealProtein: meal.totalProtein,
            mealCarbs: meal.totalCarbs,
            mealFat: meal.totalFat,
            mealItems: mealItems,
            todayCalories: todaySummary.totalCalories,
            todayProtein: todaySummary.totalProtein,
            todayCarbs: todaySummary.totalCarbs,
            todayFat: todaySummary.totalFat,
            todayMealsLogged: todaySummary.mealsLogged,
            calorieTarget: target.calories,
            proteinTarget: target.proteinGrams,
            carbsTarget: target.carbsGrams,
            fatTarget: target.fatGrams,
            mealsPerDay: target.mealsPerDay,
            recoveryZone: recoveryZone,
            trainingToday: trainingToday
        )

        let response = try await sendWithRetry(
            model: "haiku",
            prompt: prompt,
            maxTokens: 150,
            temperature: 0.4,
            feature: "meal_feedback"
        )

        return validateTextResponse(response, minWords: 5, maxWords: 60)
    }

    // MARK: - Daily Summary

    /// End-of-day nutrition summary (3-5 sentences).
    /// Model: Haiku | Temp: 0.4 | Max tokens: 300 | Timeout: 10s
    func dailySummary(
        meals: [MealLog],
        summary: DailyNutritionSummary,
        target: ActiveNutritionTarget,
        recovery: WhoopRecoveryData?,
        tomorrowTraining: String?
    ) async throws -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        let mealTuples = meals.map { meal in
            (
                type: meal.mealType.displayName,
                calories: meal.totalCalories,
                protein: meal.totalProtein,
                carbs: meal.totalCarbs,
                fat: meal.totalFat,
                time: timeFormatter.string(from: meal.loggedAt)
            )
        }

        let recoveryZone: String? = recovery.map { recoveryZoneLabel(score: $0.score) }

        let prompt = NutritionCoachPrompts.dailySummaryPrompt(
            meals: mealTuples,
            totalCalories: summary.totalCalories,
            totalProtein: summary.totalProtein,
            totalCarbs: summary.totalCarbs,
            totalFat: summary.totalFat,
            calorieTarget: target.calories,
            proteinTarget: target.proteinGrams,
            carbsTarget: target.carbsGrams,
            fatTarget: target.fatGrams,
            mealsLogged: summary.mealsLogged,
            mealsPlanned: target.mealsPerDay,
            recoveryScore: recovery?.score,
            recoveryZone: recoveryZone,
            tomorrowTraining: tomorrowTraining
        )

        let response = try await sendWithRetry(
            model: "haiku",
            prompt: prompt,
            maxTokens: 300,
            temperature: 0.4,
            feature: "daily_summary"
        )

        return validateTextResponse(response, minWords: 15, maxWords: 100)
    }

    // MARK: - Weekly Review

    /// Weekly nutrition analysis with structured output.
    /// Model: Sonnet | Temp: 0.3 | Max tokens: 500 | Timeout: 30s
    func weeklyReview(
        dailyData: [DailyNutritionSummary],
        targets: ActiveNutritionTarget,
        trainingDays: Int,
        prevWeekAdherence: Double?
    ) async throws -> WeeklyNutritionReview {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "E, MMM d"

        let dataForPrompt = dailyData.map { day in
            (
                date: dayFormatter.string(from: day.date),
                calories: day.totalCalories,
                protein: day.totalProtein,
                carbs: day.totalCarbs,
                fat: day.totalFat,
                mealsLogged: day.mealsLogged,
                mealsPlanned: targets.mealsPerDay
            )
        }

        let prompt = NutritionCoachPrompts.weeklyReviewPrompt(
            dailyData: dataForPrompt,
            calorieTarget: targets.calories,
            proteinTarget: targets.proteinGrams,
            carbsTarget: targets.carbsGrams,
            fatTarget: targets.fatGrams,
            trainingDays: trainingDays,
            prevWeekAdherence: prevWeekAdherence
        )

        let response = try await sendWithRetry(
            model: "sonnet",
            prompt: prompt,
            maxTokens: 500,
            temperature: 0.3,
            feature: "weekly_review"
        )

        return try parseJSON(response, as: WeeklyNutritionReview.self, feature: "weekly_review")
    }

    // MARK: - Recovery Nutrition Guidance

    /// Recovery-aware nutrition guidance when Whoop recovery is yellow/red.
    /// Model: Haiku | Temp: 0.3 | Max tokens: 200 | Timeout: 10s
    func recoveryNutritionGuidance(
        recovery: WhoopRecoveryData,
        sleep: WhoopSleepData?,
        todaySummary: DailyNutritionSummary,
        trainingToday: String?
    ) async throws -> String {
        let zone = recoveryZoneLabel(score: recovery.score)

        let prompt = NutritionCoachPrompts.recoveryNutritionPrompt(
            recoveryScore: recovery.score,
            recoveryZone: zone,
            hrvRmssd: recovery.hrvRmssd,
            restingHeartRate: recovery.restingHeartRate,
            sleepHours: sleep?.totalHours,
            sleepScore: sleep.map(\.sleepScore),
            todayCalories: todaySummary.totalCalories,
            todayProtein: todaySummary.totalProtein,
            todayCarbs: todaySummary.totalCarbs,
            todayFat: todaySummary.totalFat,
            calorieTarget: todaySummary.calorieTarget ?? 2400,
            proteinTarget: todaySummary.proteinTarget ?? 180,
            trainingToday: trainingToday
        )

        let response = try await sendWithRetry(
            model: "haiku",
            prompt: prompt,
            maxTokens: 200,
            temperature: 0.3,
            feature: "recovery_nutrition"
        )

        return validateTextResponse(response, minWords: 15, maxWords: 80)
    }

    // MARK: - Pre-Training Alert

    /// Pre-training nutrition alert when carbs are low before a workout.
    /// Model: Haiku | Temp: 0.3 | Max tokens: 150 | Timeout: 10s
    func preTrainingAlert(
        hoursUntilTraining: Double,
        workoutType: String,
        carbsConsumed: Double,
        carbTarget: Double,
        lastMealTime: Date?
    ) async throws -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let lastMealString = lastMealTime.map { timeFormatter.string(from: $0) }

        let prompt = NutritionCoachPrompts.preTrainingAlertPrompt(
            hoursUntilTraining: hoursUntilTraining,
            workoutType: workoutType,
            carbsConsumed: carbsConsumed,
            carbTarget: carbTarget,
            proteinConsumed: 0, // Caller can extend; carbs are the priority here
            proteinTarget: 0,
            caloriesConsumed: 0,
            calorieTarget: 0,
            lastMealTime: lastMealString
        )

        let response = try await sendWithRetry(
            model: "haiku",
            prompt: prompt,
            maxTokens: 150,
            temperature: 0.3,
            feature: "pre_training_alert"
        )

        return validateTextResponse(response, minWords: 10, maxWords: 60)
    }

    // MARK: - Meal Suggestions

    /// Suggest meals based on remaining macro budget.
    /// Model: Haiku | Temp: 0.5 | Max tokens: 500 | Timeout: 10s
    func mealSuggestions(
        remainingBudget: MacroBudget,
        timeOfDay: String,
        isTrainingDay: Bool
    ) async throws -> [MealSuggestion] {
        // Estimate meals remaining based on calorie budget
        let mealsRemaining = max(1, min(3, Int(remainingBudget.caloriesRemaining / 500)))

        let prompt = NutritionCoachPrompts.mealSuggestionsPrompt(
            caloriesRemaining: Int(remainingBudget.caloriesRemaining),
            proteinRemaining: Int(remainingBudget.proteinRemaining),
            carbsRemaining: Int(remainingBudget.carbsRemaining),
            fatRemaining: Int(remainingBudget.fatRemaining),
            timeOfDay: timeOfDay,
            isTrainingDay: isTrainingDay,
            mealsRemainingCount: mealsRemaining
        )

        let response = try await sendWithRetry(
            model: "haiku",
            prompt: prompt,
            maxTokens: 500,
            temperature: 0.5,
            feature: "meal_suggestions"
        )

        let parsed = try parseJSON(response, as: MealSuggestionsResponse.self, feature: "meal_suggestions")
        return parsed.suggestions
    }

    // MARK: - Private Helpers

    /// Send a Claude API request via the backend proxy with retry logic.
    /// Per AI_INTELLIGENCE_ENGINE.md §2.3 + INTELLIGENCE_REMEDIATION_PLAN.md §3.
    /// `model` is the proxy model id — "haiku" or "sonnet".
    private func sendWithRetry(
        model: String,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        feature: String
    ) async throws -> String {
        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: model,
                    system: NutritionCoachPrompts.systemPrompt,
                    userMessage: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    caller: feature
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                logger.info("[\(feature)] Claude response received via backend (attempt \(attempt))")
                return response.text
            } catch let error as APIError {
                lastError = error
                logger.warning("[\(feature)] Backend proxy error (attempt \(attempt)): \(String(describing: error))")

                guard error.isRetryable, attempt < maxRetries else {
                    break
                }

                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch {
                lastError = error
                logger.error("[\(feature)] Unexpected error: \(error.localizedDescription)")
                break
            }
        }

        throw NutritionCoachError.apiFailed(lastError ?? APIError.unknown(statusCode: -1))
    }

    /// Parse a JSON response from Claude, with extraction fallback.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 2.3: try to extract JSON between { and }.
    /// Preserves the first decode error so the log captures *why* the parse
    /// failed (missing key, type mismatch) instead of a generic message.
    private func parseJSON<T: Decodable>(_ response: String, as type: T.Type, feature: String) throws -> T {
        let decoder = JSONDecoder()
        var firstDecodeError: Error?

        // First attempt: parse directly
        if let data = response.data(using: .utf8) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                firstDecodeError = error
            }
        }

        // Second attempt: extract JSON between first { and last }
        // Per AI_INTELLIGENCE_ENGINE.md: Claude sometimes wraps JSON in markdown code blocks
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8) {
                if let result = try? decoder.decode(T.self, from: data) {
                    logger.info("[\(feature)] JSON extracted from wrapped response")
                    return result
                }
            }
        }

        // Also try array extraction for array responses
        if let startIndex = response.firstIndex(of: "["),
           let endIndex = response.lastIndex(of: "]")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8) {
                if let result = try? decoder.decode(T.self, from: data) {
                    logger.info("[\(feature)] JSON array extracted from wrapped response")
                    return result
                }
            }
        }

        let errDetail = firstDecodeError.map { String(describing: $0) } ?? "no decode attempt produced an error"
        logger.error("[\(feature)] Failed to parse JSON response: \(response.prefix(200)) | underlying: \(errDetail, privacy: .public)")
        throw NutritionCoachError.jsonParsingFailed("Could not parse \(feature) response as \(T.self): \(errDetail)")
    }

    /// Validate and clean a text response.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 3.1 Response Parsing.
    private func validateTextResponse(_ response: String, minWords: Int, maxWords: Int) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")

        // If under minimum, return as-is (something is better than nothing)
        if words.count < minWords {
            logger.warning("Response too short (\(words.count) words, min \(minWords))")
            return trimmed
        }

        // If over maximum, truncate at last complete sentence within limit
        if words.count > maxWords {
            let truncated = words.prefix(maxWords).joined(separator: " ")
            // Find last sentence-ending punctuation
            if let lastPeriod = truncated.lastIndex(where: { $0 == "." || $0 == "!" }) {
                return String(truncated[truncated.startIndex ... lastPeriod])
            }
            return truncated
        }

        return trimmed
    }

    /// Map recovery score to zone label.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 3.5: green (67-100%), yellow (34-66%), red (<34%).
    private func recoveryZoneLabel(score: Double) -> String {
        if score >= 67 {
            "green"
        } else if score >= 34 {
            "yellow"
        } else {
            "red"
        }
    }
}
