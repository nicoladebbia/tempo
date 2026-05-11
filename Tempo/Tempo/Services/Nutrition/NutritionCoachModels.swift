//
// NutritionCoachModels.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation

// MARK: - WeeklyNutritionReview

/// Structured response from the weekly nutrition analysis.
/// Parsed from Claude Sonnet JSON output.
struct WeeklyNutritionReview: Codable {
    /// One-line verdict on the week's nutrition. Max 80 chars.
    let verdict: String
    /// 3-5 sentence analysis with specific numbers and day references.
    let analysis: String
    /// 2-3 specific, actionable fixes. Drill-sergeant voice.
    let fix: String
}

// MARK: - MealSuggestion

/// AI-generated meal suggestion based on remaining macro budget.
struct MealSuggestion: Codable, Identifiable {
    /// Meal name (e.g., "Chicken Rice Bowl").
    let name: String
    /// Estimated total calories.
    let calories: Int
    /// Protein in grams.
    let protein: Int
    /// Carbs in grams.
    let carbs: Int
    /// Fat in grams.
    let fat: Int
    /// Prep time estimate (e.g., "10 min", "5 min", "0 min").
    let prepTime: String
    /// One-sentence description of the meal.
    let description: String

    var id: String {
        name
    }

    enum CodingKeys: String, CodingKey {
        case name
        case calories
        case protein
        case carbs
        case fat
        case prepTime = "prep_time"
        case description
    }
}

// MARK: - MealSuggestionsResponse

/// Wrapper for parsing Claude's JSON array of meal suggestions.
struct MealSuggestionsResponse: Codable {
    let suggestions: [MealSuggestion]
}

// MARK: - NutritionCoachError

enum NutritionCoachError: Error {
    /// Claude API call failed.
    case apiFailed(ClaudeAPIError)
    /// Response was empty or could not be parsed.
    case invalidResponse(String)
    /// JSON parsing failed after extraction attempt.
    case jsonParsingFailed(String)
    /// Circuit breaker is open -- using fallback.
    case circuitOpen
    /// Feature not available (e.g., no API key).
    case unavailable(String)
}
