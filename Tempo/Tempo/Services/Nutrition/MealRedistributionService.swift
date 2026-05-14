//
// MealRedistributionService.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import Foundation
import os

// MARK: - MealRedistributionResult

/// Result returned to the caller after a skip is redistributed. Carries
/// the AI's reasoning so the UI can surface it to the user ("snack +200
/// kcal because recovery is high and lunch is too far away to absorb it
/// all").
struct MealRedistributionResult: Sendable {
    struct PerMeal: Sendable {
        let mealNumber: Int
        let addCalories: Double
        let addProtein: Double
        let addCarbs: Double
        let addFat: Double
    }
    let perMeal: [PerMeal]
    let totalDroppedCalories: Double
    let reasoning: String
    let source: Source

    enum Source: Sendable {
        case ai
        case fallback
    }
}

// MARK: - MealRedistributionService

/// Calls Claude Haiku to redistribute the macros of a skipped meal across
/// the remaining planned meals of the day. Falls back to a deterministic
/// proportional split when the API isn't reachable, so skipping never
/// fails silently.
@MainActor
final class MealRedistributionService {
    /// Backend proxy for Claude calls. Per INTELLIGENCE_REMEDIATION_PLAN.md §3.
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "app.tempo", category: "MealRedistribution")
    private let maxRetries = 1

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Redistribute the macros of `skipped` across `remaining`. Caller
    /// applies the result via `applyMealRedistribution`.
    func redistribute(
        skipped: PlannedMeal,
        remaining: [PlannedMeal],
        recoveryScore: Double?,
        sleepHours: Double?,
        strain: Double?,
        dayType: String,
        timeOfDay: String? = nil
    ) async -> MealRedistributionResult {
        let plannedRemaining = remaining.filter { $0.status == .planned }
        guard !plannedRemaining.isEmpty else {
            return MealRedistributionResult(
                perMeal: [],
                totalDroppedCalories: skipped.totalCalories,
                reasoning: "No remaining planned meals — calories drop today.",
                source: .fallback
            )
        }

        let inputs = plannedRemaining.map { meal in
            RemainingMealInput(
                mealNumber: meal.mealNumber,
                name: meal.mealName,
                scheduledTime: meal.scheduledTime,
                status: meal.status.rawValue,
                calories: Int(meal.totalCalories),
                protein: Int(meal.totalProtein),
                carbs: Int(meal.totalCarbs),
                fat: Int(meal.totalFat)
            )
        }

        let resolvedTimeOfDay = timeOfDay ?? Self.timeOfDay(for: Date())

        let prompt = MealRedistributionPrompts.redistributePrompt(
            skippedMealName: skipped.mealName,
            skippedMealNumber: skipped.mealNumber,
            skippedCalories: Int(skipped.totalCalories),
            skippedProtein: Int(skipped.totalProtein),
            skippedCarbs: Int(skipped.totalCarbs),
            skippedFat: Int(skipped.totalFat),
            remainingMeals: inputs,
            timeOfDay: resolvedTimeOfDay,
            recoveryScore: recoveryScore,
            sleepHours: sleepHours,
            strain: strain,
            dayType: dayType
        )

        do {
            let response = try await sendWithRetry(prompt: prompt)
            let parsed = try parseResponse(response)
            // Enforce hard caps in code so a hallucinated 200% boost can't
            // slip through. Caps mirror the prompt rules.
            let clamped = clampAdjustments(
                parsed,
                remaining: plannedRemaining,
                skippedCalories: skipped.totalCalories,
                skippedProtein: skipped.totalProtein,
                skippedCarbs: skipped.totalCarbs,
                skippedFat: skipped.totalFat
            )
            return clamped
        } catch {
            logger.warning("AI redistribution failed (\(error.localizedDescription)) — falling back to proportional split")
            return fallbackProportional(
                skipped: skipped,
                remaining: plannedRemaining
            )
        }
    }

    // MARK: - Private

    private func sendWithRetry(prompt: String) async throws -> String {
        var lastError: Error?
        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "haiku",
                    system: MealRedistributionPrompts.systemPrompt,
                    userMessage: prompt,
                    maxTokens: 600,
                    temperature: 0.3,
                    caller: "meal_redistribution"
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                return response.text
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        throw lastError ?? NSError(
            domain: "MealRedistribution",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "AI call failed"]
        )
    }

    private func parseResponse(_ raw: String) throws -> MealRedistributionResponse {
        // Strip any accidental code fences the model wraps around JSON.
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "MealRedistribution", code: -2)
        }
        return try JSONDecoder().decode(MealRedistributionResponse.self, from: data)
    }

    /// Enforce the prompt's hard caps in code as a defence-in-depth.
    /// Cap each meal's add* at 30% above its original target.
    private func clampAdjustments(
        _ response: MealRedistributionResponse,
        remaining: [PlannedMeal],
        skippedCalories: Double,
        skippedProtein: Double,
        skippedCarbs: Double,
        skippedFat: Double
    ) -> MealRedistributionResult {
        let byNumber = Dictionary(uniqueKeysWithValues: remaining.map { ($0.mealNumber, $0) })
        var perMeal: [MealRedistributionResult.PerMeal] = []
        var appliedCal: Double = 0

        for adjustment in response.adjustments {
            guard let target = byNumber[adjustment.mealNumber] else { continue }
            let calCap = target.totalCalories * 0.3
            let proteinCap = target.totalProtein * 0.3
            // Carbs/fat get the same 30% rule.
            let carbsCap = target.totalCarbs * 0.3
            let fatCap = target.totalFat * 0.3

            let addCal = min(max(0, adjustment.addCalories), calCap)
            let addProtein = min(max(0, adjustment.addProtein), proteinCap)
            let addCarbs = min(max(0, adjustment.addCarbs), carbsCap)
            let addFat = min(max(0, adjustment.addFat), fatCap)

            perMeal.append(.init(
                mealNumber: adjustment.mealNumber,
                addCalories: addCal,
                addProtein: addProtein,
                addCarbs: addCarbs,
                addFat: addFat
            ))
            appliedCal += addCal
        }

        return MealRedistributionResult(
            perMeal: perMeal,
            totalDroppedCalories: max(0, skippedCalories - appliedCal),
            reasoning: response.reasoning,
            source: .ai
        )
    }

    /// Safety net: split skipped macros proportionally to remaining meals'
    /// existing calorie targets, capped at 30% above each meal's original.
    private func fallbackProportional(
        skipped: PlannedMeal,
        remaining: [PlannedMeal]
    ) -> MealRedistributionResult {
        let totalRemainingCal = remaining.reduce(0.0) { $0 + $1.totalCalories }
        guard totalRemainingCal > 0 else {
            return MealRedistributionResult(
                perMeal: [],
                totalDroppedCalories: skipped.totalCalories,
                reasoning: "Fallback: remaining meals have zero target — nothing to add to.",
                source: .fallback
            )
        }

        var perMeal: [MealRedistributionResult.PerMeal] = []
        var appliedCal: Double = 0
        for meal in remaining {
            let share = meal.totalCalories / totalRemainingCal
            let calCap = meal.totalCalories * 0.3
            let proteinCap = meal.totalProtein * 0.3
            let carbsCap = meal.totalCarbs * 0.3
            let fatCap = meal.totalFat * 0.3

            let addCal = min(skipped.totalCalories * share, calCap)
            let addProtein = min(skipped.totalProtein * share, proteinCap)
            let addCarbs = min(skipped.totalCarbs * share, carbsCap)
            let addFat = min(skipped.totalFat * share, fatCap)

            perMeal.append(.init(
                mealNumber: meal.mealNumber,
                addCalories: addCal,
                addProtein: addProtein,
                addCarbs: addCarbs,
                addFat: addFat
            ))
            appliedCal += addCal
        }
        return MealRedistributionResult(
            perMeal: perMeal,
            totalDroppedCalories: max(0, skipped.totalCalories - appliedCal),
            reasoning: "Fallback: proportional split.",
            source: .fallback
        )
    }

    private static func timeOfDay(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 11 { return "morning" }
        if hour < 15 { return "afternoon" }
        if hour < 19 { return "evening" }
        return "night"
    }
}
