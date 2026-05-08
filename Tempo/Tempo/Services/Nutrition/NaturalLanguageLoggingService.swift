//
// NaturalLanguageLoggingService.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import os

// MARK: - ParsedFoodItem

/// A food item parsed from natural language input, ready for display and user confirmation.
struct ParsedFoodItem: Identifiable {
    let id: String
    let name: String
    let quantityGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    /// Whether the macros came from the local FoodMacroDatabase (more accurate) vs Claude estimate.
    let isVerified: Bool

    /// Formatted portion string using natural portions when available.
    var formattedPortion: String {
        FoodMacroDatabase.formatPortion(food: name, grams: quantityGrams)
    }
}

// MARK: - NaturalLanguageLoggingService

/// Parses free-text food descriptions into structured food items using Claude Haiku,
/// then cross-references against FoodMacroDatabase for accuracy.
///
/// Per AI_INTELLIGENCE_ENGINE.md:
/// - Haiku for sub-second latency
/// - FoodMacroDatabase as ground truth when available
/// - Claude estimates as fallback for unknown foods
@Observable
final class NaturalLanguageLoggingService: @unchecked Sendable {
    // MARK: - State

    private(set) var isProcessing = false

    // MARK: - Dependencies

    private let claude: ClaudeAPIClient
    private let logger = Logger.nutrition

    // MARK: - Retry Configuration

    private let maxRetries = 2
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Init

    init(claude: ClaudeAPIClient = ClaudeAPIClient()) {
        self.claude = claude
    }

    // MARK: - Parse Natural Language

    /// Parse a free-text food description into structured food items.
    ///
    /// Examples:
    /// - "200g chicken breast with rice and broccoli"
    /// - "2 eggs, toast, and a banana"
    /// - "protein shake with oats and peanut butter"
    ///
    /// Cross-references results against FoodMacroDatabase: if the database has the food,
    /// its macros are used instead of Claude's estimate (more accurate).
    func parseNaturalLanguage(_ text: String) async throws -> [ParsedFoodItem] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NaturalLanguageLoggingError.emptyInput
        }

        isProcessing = true
        defer { isProcessing = false }

        // Build and send prompt
        let response = try await sendParseRequest(text)

        // Parse JSON response
        let rawItems = try parseResponse(response)

        // Cross-reference with FoodMacroDatabase
        let verifiedItems = crossReferenceWithDatabase(rawItems)

        logger.info("Parsed \(verifiedItems.count) food items from: \"\(text.prefix(50))\"")

        return verifiedItems
    }

    // MARK: - Private Helpers

    /// Build the parsing prompt and send to Claude Haiku.
    private func sendParseRequest(_ text: String) async throws -> String {
        let system = """
        You are a food macro parser for a fitness nutrition app. \
        Parse natural language food descriptions into structured JSON with accurate macro data. \
        Use standard USDA/nutritional database values. All quantities in grams (raw/uncooked weight for \
        foods that are cooked). Be precise with portions -- "a chicken breast" is ~150g, "a banana" is ~120g, \
        "a cup of rice" is ~185g raw. Output ONLY valid JSON. No markdown, no code blocks, no preamble.
        """

        let prompt = """
        Parse this food description into structured JSON:

        "\(text)"

        Return ONLY valid JSON (start with [, no markdown, no code blocks) matching this schema:
        [
            {
                "name": "string (food name, lowercase, e.g. 'chicken breast', 'white rice', 'banana')",
                "quantityGrams": number (raw/uncooked weight in grams),
                "calories": number (total for the quantity),
                "proteinG": number (total grams),
                "carbsG": number (total grams),
                "fatG": number (total grams)
            }
        ]

        Rules:
        - Use common food names that match a nutrition database (e.g. "chicken breast" not "grilled chicken").
        - If a quantity is not specified, estimate a reasonable single serving.
        - "A plate of pasta" = ~80g raw pasta. "A bowl of rice" = ~75g raw rice.
        - All macro values must be realistic for the stated quantity.
        - Separate composite foods into individual items (e.g. "chicken and rice" = two items).
        - If the input mentions a brand or prepared food you cannot verify, estimate from the closest generic food.
        """

        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let response = try await claude.sendMessage(
                    model: .haiku,
                    system: system,
                    userMessage: prompt,
                    maxTokens: 500,
                    temperature: 0.2
                )
                logger.info("[nl_parse] Claude response received (attempt \(attempt))")
                return response
            } catch let error as ClaudeAPIError {
                lastError = error
                logger.warning("[nl_parse] Claude API error (attempt \(attempt)): \(String(describing: error))")

                guard error.isRetryable, attempt < maxRetries else {
                    break
                }

                let delay: TimeInterval = if case let .rateLimited(retryAfter) = error, let after = retryAfter {
                    min(after, 8.0)
                } else {
                    baseRetryDelay * pow(2.0, Double(attempt))
                }

                try await Task.sleep(for: .seconds(delay))
            } catch {
                lastError = error
                logger.error("[nl_parse] Unexpected error: \(error.localizedDescription)")
                break
            }
        }

        throw NaturalLanguageLoggingError.parseFailed(
            lastError?.localizedDescription ?? "Unknown error"
        )
    }

    /// Parse Claude's JSON response into raw food items.
    private func parseResponse(_ response: String) throws -> [RawParsedFood] {
        let decoder = JSONDecoder()

        // Try direct parse as array
        if let data = response.data(using: .utf8),
           let result = try? decoder.decode([RawParsedFood].self, from: data)
        {
            return result
        }

        // Extract JSON array between [ and ]
        if let startIndex = response.firstIndex(of: "["),
           let endIndex = response.lastIndex(of: "]")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8),
               let result = try? decoder.decode([RawParsedFood].self, from: data)
            {
                logger.info("[nl_parse] JSON array extracted from wrapped response")
                return result
            }
        }

        // Try as wrapped object with items/foods key
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8) {
                struct Wrapper: Codable {
                    let items: [RawParsedFood]?
                    let foods: [RawParsedFood]?
                }
                if let wrapper = try? decoder.decode(Wrapper.self, from: data),
                   let items = wrapper.items ?? wrapper.foods
                {
                    return items
                }
            }
        }

        logger.error("[nl_parse] Failed to parse JSON: \(response.prefix(200))")
        throw NaturalLanguageLoggingError.parseFailed("Could not parse food items from response")
    }

    /// Cross-reference parsed items against FoodMacroDatabase.
    /// If the database has the food, use its macros (scaled to the parsed quantity) instead of Claude's estimate.
    private func crossReferenceWithDatabase(_ rawItems: [RawParsedFood]) -> [ParsedFoodItem] {
        rawItems.enumerated().map { index, raw in
            if let dbMacros = FoodMacroDatabase.lookup(raw.name) {
                let scaled = dbMacros.scaled(to: raw.quantityGrams)
                logger.info("DB match for '\(raw.name)': using verified macros (\(Int(scaled.calories)) kcal)")

                return ParsedFoodItem(
                    id: "parsed_\(index)_\(raw.name.hashValue)",
                    name: raw.name,
                    quantityGrams: raw.quantityGrams,
                    calories: scaled.calories.rounded(),
                    proteinG: scaled.protein.rounded(),
                    carbsG: scaled.carbs.rounded(),
                    fatG: scaled.fat.rounded(),
                    isVerified: true
                )
            } else {
                logger.info("No DB match for '\(raw.name)': using Claude estimate (\(Int(raw.calories)) kcal)")

                return ParsedFoodItem(
                    id: "parsed_\(index)_\(raw.name.hashValue)",
                    name: raw.name,
                    quantityGrams: raw.quantityGrams,
                    calories: raw.calories,
                    proteinG: raw.proteinG,
                    carbsG: raw.carbsG,
                    fatG: raw.fatG,
                    isVerified: false
                )
            }
        }
    }
}

// MARK: - RawParsedFood

private struct RawParsedFood: Codable {
    let name: String
    let quantityGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

// MARK: - NaturalLanguageLoggingError

enum NaturalLanguageLoggingError: Error {
    case emptyInput
    case parseFailed(String)
    case noFoodsDetected
}
