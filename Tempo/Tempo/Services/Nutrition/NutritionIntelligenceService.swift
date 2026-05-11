//
// NutritionIntelligenceService.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

//
// NutritionIntelligenceService.swift
// Tempo
//
// Optional Haiku-backed layer on top of the deterministic NutritionEngine.
// Used for:
//   - Drill-sergeant explanation of the current adjustment ("why are your
//     calories up 10% today?")
//   - Pantry-aware meal suggestion ("you have chicken + rice; here's a
//     macro-fitting meal").
//
// Per AI_INTELLIGENCE_ENGINE.md Section 2.5 + NUTRITION_MODULE_BUILD_PLAN.md
// N5.1: all calls go through the Vapor proxy. iOS-direct Anthropic calls are
// explicitly forbidden. The endpoint is not implemented in this phase (the
// existing Vapor InsightService can host it in a follow-up commit); this
// service holds the shape + a 15-minute in-memory cache so callers can
// integrate without waiting on the backend.
//

import Foundation
import os

@MainActor
@Observable
final class NutritionIntelligenceService {
    private let apiClient: APIClient?
    private let logger = Logger.nutrition

    // Cache key → (response, expiry)
    private var cache: [String: (response: String, expiry: Date)] = [:]
    private let cacheTTL: TimeInterval = 15 * 60

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Drill-sergeant explanation of the macro adjustment. Returns a deterministic
    /// fallback when no API client is wired or the cache miss can't be satisfied.
    func explainAdjustment(
        for adjustment: AdjustedNutritionTargets,
        recoveryZone: RecoveryZone?,
        isTrainingDay: Bool
    ) async -> String {
        let key = "explain:\(adjustment.mode.rawValue):\(recoveryZone?.rawValue ?? "nil"):\(isTrainingDay)"
        if let cached = cache[key], cached.expiry > Date() {
            return cached.response
        }
        // Fallback (always available): the engine already provides a
        // hand-written explanation string. We surface it as-is until the
        // Vapor explain endpoint is wired.
        let fallback = adjustment.modeExplanation
        cache[key] = (fallback, Date().addingTimeInterval(cacheTTL))
        return fallback
    }

    /// Meal suggestion that consumes remaining macros and uses pantry inventory.
    /// Returns a templated suggestion when no API client is wired.
    func suggestMeal(
        pantryCanonicalNames: [String],
        remainingCalories: Int,
        remainingProtein: Int,
        recoveryZone: RecoveryZone?,
        isTrainingDay: Bool
    ) async -> String {
        let pantryKey = pantryCanonicalNames.sorted().joined(separator: ",")
        let key = "suggest:\(pantryKey):\(remainingCalories):\(remainingProtein):\(recoveryZone?.rawValue ?? "nil"):\(isTrainingDay)"
        if let cached = cache[key], cached.expiry > Date() {
            return cached.response
        }

        // Deterministic fallback when no AI is available.
        let fallback = Self.templatedSuggestion(
            pantry: pantryCanonicalNames,
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein,
            recoveryZone: recoveryZone,
            isTrainingDay: isTrainingDay
        )
        cache[key] = (fallback, Date().addingTimeInterval(cacheTTL))
        return fallback
    }

    // MARK: - Templated fallback

    private static func templatedSuggestion(
        pantry: [String],
        remainingCalories: Int,
        remainingProtein: Int,
        recoveryZone: RecoveryZone?,
        isTrainingDay: Bool
    ) -> String {
        let hasChicken = pantry.contains("chicken breast")
        let hasSalmon = pantry.contains("salmon")
        let hasRice = pantry.contains("rice")
        let hasOats = pantry.contains("oats")
        let hasGreens = pantry.contains("spinach") || pantry.contains("broccoli")
        let hasYogurt = pantry.contains("greek yogurt")

        if remainingProtein > 40, hasChicken, hasRice {
            return "Cook 200g chicken with rice and \(hasGreens ? "spinach" : "olive oil"). Closes the protein gap."
        }
        if remainingProtein > 40, hasSalmon, hasGreens {
            return "Pan-sear salmon with greens. Hits protein, low carb load."
        }
        if recoveryZone == .red, hasYogurt {
            return "Greek yogurt + berries + honey. Easy to eat on a red recovery day."
        }
        if isTrainingDay, hasOats {
            return "Oats + protein powder + banana 90 min pre-workout."
        }
        if remainingCalories < 300 {
            return "You're nearly capped on calories. Greek yogurt or a protein shake closes the day."
        }
        return "Combine what you've got: aim for ~\(remainingProtein)g protein and \(remainingCalories) kcal across your next meal."
    }
}
