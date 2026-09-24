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

enum NutritionCoachError: LocalizedError {
    /// Backend Claude proxy call failed (network, auth, rate limit, upstream API).
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §3 — Claude is reached via
    /// /v1/nutrition/ai/proxy/text, not directly from iOS.
    case apiFailed(Error)
    /// Response was empty or could not be parsed.
    case invalidResponse(String)
    /// JSON parsing failed after extraction attempt.
    case jsonParsingFailed(String)
    /// Circuit breaker is open -- using fallback.
    case circuitOpen
    /// Feature not available (e.g., no API key).
    case unavailable(String)
}

extension NutritionCoachError {
    /// User-facing copy. Views show `error.localizedDescription`, which for a
    /// plain `Error` enum is the useless "The operation couldn't be completed
    /// (Tempo.NutritionCoachError error 0.)". Backend failures unwrap to
    /// `APIError.userMessage` so "Pro subscription required" / "Check your
    /// connection" reach the user verbatim.
    var errorDescription: String? {
        switch self {
        case let .apiFailed(underlying):
            if let api = underlying as? APIError {
                return api.userMessage
            }
            if let localized = underlying as? LocalizedError, let description = localized.errorDescription {
                return description
            }
            return "Coach unavailable. Try again."
        case .invalidResponse, .jsonParsingFailed:
            return "Coach sent back something unreadable. Try again."
        case .circuitOpen:
            return "Coach is cooling down. Try again in a minute."
        case let .unavailable(reason):
            return reason
        }
    }

    /// True when the failure means "AI is off for this user" (no Pro, no AI
    /// consent) rather than a real error — callers fall back to the offline
    /// templates silently instead of showing an error.
    var isEntitlementGate: Bool {
        guard case let .apiFailed(underlying) = self, let api = underlying as? APIError else {
            return false
        }
        switch api {
        case .subscriptionRequired, .aiConsentRequired: return true
        default: return false
        }
    }
}
