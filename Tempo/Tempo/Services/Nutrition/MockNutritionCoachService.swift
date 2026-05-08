//
// MockNutritionCoachService.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation

// MARK: - Mock Nutrition Coach Service

/// Mock implementation returning realistic canned responses for previews, testing, and fallback.
/// Each response matches the drill-sergeant voice per UX_COPY_BIBLE.md Section 1.1.
final class MockNutritionCoachService: NutritionCoachServiceProtocol, @unchecked Sendable {
    /// Simulated latency to mimic real API calls in UI previews.
    var simulatedDelay: TimeInterval = 0.3

    /// Set to true to simulate API failures.
    var shouldFail = false

    /// Tracks which methods were called (for unit tests).
    var callLog: [String] = []

    // MARK: - Meal Feedback

    func mealFeedback(
        meal: MealLog,
        todaySummary: DailyNutritionSummary,
        target: ActiveNutritionTarget,
        recoveryZone: String?,
        trainingToday: String?
    ) async throws -> String {
        try await simulateCall("mealFeedback")

        let proteinRemaining = Int(target.proteinGrams - todaySummary.totalProtein)
        let caloriesRemaining = Int(target.calories - todaySummary.totalCalories)
        let mealsLeft = target.mealsPerDay - todaySummary.mealsLogged

        if proteinRemaining > 40, mealsLeft <= 1 {
            return "\(Int(meal.totalProtein))g protein in that \(meal.mealType.displayName.lowercased()). Not bad, but you're still \(proteinRemaining)g short with \(mealsLeft) meal left. Next meal needs to be protein-heavy. Think chicken or Greek yogurt."
        }

        if caloriesRemaining < 0 {
            return "\(Int(meal.totalCalories)) kcal logged. You're \(abs(caloriesRemaining)) kcal over target for the day. \(Int(meal.totalProtein))g protein is solid, but watch the total. Keep the next meal light if there is one."
        }

        return "\(Int(meal.totalProtein))g protein, \(Int(meal.totalCalories)) kcal. Solid. \(caloriesRemaining) kcal remaining across \(mealsLeft) meals. Protein tracking at \(Int(todaySummary.totalProtein))g of \(Int(target.proteinGrams))g. On pace."
    }

    // MARK: - Daily Summary

    func dailySummary(
        meals: [MealLog],
        summary: DailyNutritionSummary,
        target: ActiveNutritionTarget,
        recovery: WhoopRecoveryData?,
        tomorrowTraining: String?
    ) async throws -> String {
        try await simulateCall("dailySummary")

        let calDelta = Int(summary.totalCalories - target.calories)
        let protDelta = Int(summary.totalProtein - target.proteinGrams)
        let hitProtein = summary.totalProtein >= target.proteinGrams

        var result = ""

        if hitProtein, abs(calDelta) <= Int(target.calories * 0.1) {
            result = "Clean day. \(Int(summary.totalCalories)) kcal against a \(Int(target.calories)) target. Protein at \(Int(summary.totalProtein))g -- target hit. \(summary.mealsLogged) meals logged, all accounted for."
        } else if !hitProtein {
            result = "\(Int(summary.totalProtein))g protein. Target was \(Int(target.proteinGrams))g. That's \(abs(protDelta))g short. \(summary.mealsLogged < target.mealsPerDay ? "You logged \(summary.mealsLogged) of \(target.mealsPerDay) meals. The missed meal is where the protein went." : "All meals logged but the protein density was low.")"
        } else {
            result = "\(Int(summary.totalCalories)) kcal today. That's \(calDelta > 0 ? "\(calDelta) over" : "\(abs(calDelta)) under") target. Protein hit at \(Int(summary.totalProtein))g. \(calDelta > 100 ? "Watch the calorie surplus -- fat was \(Int(summary.totalFat))g, higher than usual." : "Acceptable range.")"
        }

        if let training = tomorrowTraining {
            result += " Tomorrow is \(training). Front-load carbs at breakfast."
        }

        return result
    }

    // MARK: - Weekly Review

    func weeklyReview(
        dailyData: [DailyNutritionSummary],
        targets: ActiveNutritionTarget,
        trainingDays: Int,
        prevWeekAdherence: Double?
    ) async throws -> WeeklyNutritionReview {
        try await simulateCall("weeklyReview")

        let proteinHitDays = dailyData.count(where: { $0.totalProtein >= targets.proteinGrams })
        let avgProtein = dailyData.isEmpty ? 0 : Int(dailyData.map(\.totalProtein).reduce(0, +) / Double(dailyData.count))
        let avgCalories = dailyData.isEmpty ? 0 : Int(dailyData.map(\.totalCalories).reduce(0, +) / Double(dailyData.count))

        return WeeklyNutritionReview(
            verdict: "\(proteinHitDays) of \(dailyData.count) days hit protein. \(proteinHitDays >= 5 ? "Acceptable." : "That's a pattern, not a bad day.")",
            analysis: "Average daily intake: \(avgCalories) kcal, \(avgProtein)g protein. Protein target of \(Int(targets.proteinGrams))g was hit on \(proteinHitDays) of \(dailyData.count) days. \(trainingDays) training days this week required higher fuel -- the misses clustered on training days where meal count dropped to 3. Calorie consistency was better than protein consistency, suggesting the issue is food selection, not meal frequency.",
            fix: "Add a 40g protein source to every training day post-workout. Greek yogurt with a scoop of whey is 45g in 2 minutes. That single change closes the gap on \(dailyData.count - proteinHitDays) of your miss days. \(prevWeekAdherence.map { "Last week adherence was \(Int($0 * 100))%. This fix targets the exact shortfall." } ?? "Track this change next week.")"
        )
    }

    // MARK: - Recovery Nutrition Guidance

    func recoveryNutritionGuidance(
        recovery: WhoopRecoveryData,
        sleep: WhoopSleepData?,
        todaySummary: DailyNutritionSummary,
        trainingToday: String?
    ) async throws -> String {
        try await simulateCall("recoveryNutritionGuidance")

        let zone = recovery.score >= 67 ? "green" : (recovery.score >= 34 ? "yellow" : "red")
        let caloriesConsumed = Int(todaySummary.totalCalories)
        let calorieTarget = Int(todaySummary.calorieTarget ?? 2400)

        if zone == "red" {
            return "Recovery at \(Int(recovery.score))%. Red zone. Your body is rebuilding. Hit \(calorieTarget + 200) kcal today -- that's 200 above normal target. You're at \(caloriesConsumed) kcal so far. Prioritize omega-3s and carbs in your next meal. \(trainingToday != nil ? "Training today should be light or skipped entirely." : "Rest day is the right call.")"
        }

        return "Recovery at \(Int(recovery.score))%. Yellow zone. HRV is \(Int(recovery.hrvRmssd))ms. Hit your full calorie target today -- you're at \(caloriesConsumed) of \(calorieTarget) kcal. Protein is priority for tissue repair. \(sleep.map { "Sleep was \(String(format: "%.1f", $0.totalHours))h. Adequate hydration will help compensate." } ?? "")"
    }

    // MARK: - Pre-Training Alert

    func preTrainingAlert(
        hoursUntilTraining: Double,
        workoutType: String,
        carbsConsumed: Double,
        carbTarget: Double,
        lastMealTime: Date?
    ) async throws -> String {
        try await simulateCall("preTrainingAlert")

        let carbDeficit = Int(carbTarget * 0.5 - carbsConsumed)
        let hoursString = String(format: "%.1f", hoursUntilTraining)

        if hoursUntilTraining < 2 {
            return "\(workoutType) in \(hoursString)h. Carbs at \(Int(carbsConsumed))g -- \(carbDeficit)g short of pre-workout minimum. Grab a banana and 2 rice cakes now. That's 60g of fast-digesting carbs. Eat it, wait 20 min, then train."
        }

        return "\(workoutType) in \(hoursString)h. You've consumed \(Int(carbsConsumed))g carbs against a \(Int(carbTarget))g daily target. Eat a bowl of rice with chicken now -- 200g rice gives you 56g carbs plus 30g protein. That fuels the session and hits two targets."
    }

    // MARK: - Meal Suggestions

    func mealSuggestions(
        remainingBudget: MacroBudget,
        timeOfDay: String,
        isTrainingDay: Bool
    ) async throws -> [MealSuggestion] {
        try await simulateCall("mealSuggestions")

        var suggestions: [MealSuggestion] = []

        if remainingBudget.proteinRemaining > 30 {
            suggestions.append(MealSuggestion(
                name: "Chicken Rice Bowl",
                calories: 520,
                protein: 42,
                carbs: 55,
                fat: 12,
                prepTime: "12 min",
                description: "200g chicken breast with 150g white rice. Covers 42g protein and 55g carbs."
            ))
        }

        if remainingBudget.caloriesRemaining > 300 {
            suggestions.append(MealSuggestion(
                name: "Greek Yogurt Power Bowl",
                calories: 340,
                protein: 35,
                carbs: 28,
                fat: 8,
                prepTime: "3 min",
                description: "250g Greek yogurt with a banana and 30g oats. Fast, high-protein, no cooking."
            ))
        }

        if isTrainingDay, remainingBudget.carbsRemaining > 40 {
            suggestions.append(MealSuggestion(
                name: "Pasta with Ground Beef",
                calories: 620,
                protein: 38,
                carbs: 72,
                fat: 18,
                prepTime: "15 min",
                description: "100g pasta with 150g lean ground beef. Training day carb loader."
            ))
        }

        // Always provide at least one suggestion
        if suggestions.isEmpty {
            suggestions.append(MealSuggestion(
                name: "Protein Snack Plate",
                calories: 220,
                protein: 28,
                carbs: 8,
                fat: 10,
                prepTime: "2 min",
                description: "2 boiled eggs plus 100g cottage cheese. Pure protein, minimal calories."
            ))
        }

        return suggestions
    }

    // MARK: - Helpers

    private func simulateCall(_ method: String) async throws {
        callLog.append(method)

        if shouldFail {
            throw NutritionCoachError.apiFailed(.serverError(statusCode: 500))
        }

        if simulatedDelay > 0 {
            try await Task.sleep(for: .seconds(simulatedDelay))
        }
    }
}
