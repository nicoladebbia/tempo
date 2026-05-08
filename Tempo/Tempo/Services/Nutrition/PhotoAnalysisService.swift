//
// PhotoAnalysisService.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import os

// MARK: - PhotoAnalysisServiceProtocol

protocol PhotoAnalysisServiceProtocol: Sendable {
    func analyzeMealPhoto(_ imageData: Data, remainingBudget: MacroBudget?) async throws -> PhotoAnalysisResult
}

// MARK: - PhotoAnalysisService

@Observable
final class PhotoAnalysisService: PhotoAnalysisServiceProtocol, @unchecked Sendable {
    private let foodSearch: any FoodSearchServiceProtocol
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger.nutrition

    /// Claude API key. Reads from Info.plist key ANTHROPIC_API_KEY.
    private let anthropicAPIKey: String?

    init(foodSearch: any FoodSearchServiceProtocol, session: URLSession = .shared) {
        self.foodSearch = foodSearch
        self.session = session
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        anthropicAPIKey = Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String
    }

    // MARK: - Analyze Meal Photo

    // Uses Claude Haiku via direct API call for real-time meal analysis.
    // Pattern: vision analysis → parse structured JSON → cross-reference USDA (RAG).

    func analyzeMealPhoto(
        _ imageData: Data,
        remainingBudget: MacroBudget?
    ) async throws -> PhotoAnalysisResult {
        guard let apiKey = anthropicAPIKey, !apiKey.isEmpty else {
            throw NutritionError.apiKeyMissing
        }

        // Step 1: Call Claude Vision with the image
        let analysisJSON = try await callClaudeVision(imageData: imageData, budget: remainingBudget, apiKey: apiKey)

        // Step 2: Parse the structured response
        let analysis = try parseAnalysis(analysisJSON)

        // Step 3: Cross-reference top items against USDA for verified macros (RAG pattern)
        let verifiedItems = await crossReferenceUSDA(items: analysis.items)

        // Step 4: Build final result
        let totalCal = verifiedItems.reduce(0.0) { $0 + $1.calories }
        let totalPro = verifiedItems.reduce(0.0) { $0 + $1.proteinGrams }
        let totalCarbs = verifiedItems.reduce(0.0) { $0 + $1.carbsGrams }
        let totalFat = verifiedItems.reduce(0.0) { $0 + $1.fatGrams }

        let result = PhotoAnalysisResult(
            items: verifiedItems,
            totalCalories: totalCal,
            totalProtein: totalPro,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            confidence: PhotoAnalysisResult.PhotoConfidence(score: analysis.confidence),
            verdict: analysis.verdict
        )

        logger
            .info(
                "Photo analysis: \(verifiedItems.count) items, \(String(format: "%.0f", totalCal)) cal, confidence: \(analysis.confidence)"
            )
        return result
    }

    // MARK: - Claude Vision API Call

    private func callClaudeVision(
        imageData: Data,
        budget: MacroBudget?,
        apiKey: String
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let base64Image = imageData.base64EncodedString()
        let prompt = buildPrompt(budget: budget)

        let requestBody = ClaudeMessagesRequest(
            model: "claude-haiku-4-5-20251001",
            maxTokens: 1024,
            messages: [
                ClaudeMessage(
                    role: "user",
                    content: [
                        .image(mediaType: "image/jpeg", data: base64Image),
                        .text(prompt),
                    ]
                ),
            ]
        )

        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NutritionError.photoAnalysisFailed("No HTTP response")
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            break
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw NutritionError.rateLimited(retryAfter: retryAfter)
        default:
            throw NutritionError.photoAnalysisFailed("Claude API returned status \(httpResponse.statusCode)")
        }

        let claudeResponse = try decoder.decode(ClaudeMessagesResponse.self, from: data)

        guard let textContent = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text
        else {
            throw NutritionError.invalidResponse
        }

        return text
    }

    // MARK: - Build Prompt

    private func buildPrompt(budget: MacroBudget?) -> String {
        var prompt = """
        Analyze this meal photo. Identify each food item and estimate its nutritional content.

        Return ONLY valid JSON in this exact format (no markdown, no explanation):
        {
          "items": [
            {
              "name": "food name",
              "portion": "estimated portion (e.g., '1 cup', '150g', '2 slices')",
              "calories": 250,
              "protein": 12.5,
              "carbs": 30.0,
              "fat": 8.0,
              "confidence": 0.85
            }
          ],
          "confidence": 0.8,
          "verdict": "A one-sentence summary of the meal."
        }

        Rules:
        - All numeric values must be numbers, not strings.
        - Confidence is 0.0 to 1.0 (how sure you are about the identification and portion).
        - If the image does not contain food, return: {"items": [], "confidence": 0, "verdict": "No food detected in this image."}
        - If the image is too blurry or unclear, return: {"items": [], "confidence": 0, "verdict": "Image is too unclear to analyze."}
        - Be conservative with portion estimates — better to underestimate than overestimate.
        """

        if let budget {
            prompt += """

            Context: The user has these remaining macros for today:
            - Calories: \(Int(budget.caloriesRemaining)) kcal remaining of \(Int(budget.calorieTarget))
            - Protein: \(Int(budget.proteinRemaining))g remaining of \(Int(budget.proteinTarget))g
            - Carbs: \(Int(budget.carbsRemaining))g remaining of \(Int(budget.carbsTarget))g
            - Fat: \(Int(budget.fatRemaining))g remaining of \(Int(budget.fatTarget))g
            Include a note in the verdict about how this meal fits their remaining budget.
            """
        }

        return prompt
    }

    // MARK: - Parse Analysis

    private func parseAnalysis(_ jsonString: String) throws -> ClaudeFoodAnalysis {
        // Claude may wrap JSON in markdown code blocks — strip them.
        var cleaned = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find the JSON object boundaries if there's surrounding text
        if let startIndex = cleaned.firstIndex(of: "{"),
           let endIndex = cleaned.lastIndex(of: "}")
        {
            cleaned = String(cleaned[startIndex ... endIndex])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw NutritionError.invalidResponse
        }

        do {
            return try decoder.decode(ClaudeFoodAnalysis.self, from: data)
        } catch {
            logger.error("Failed to parse Claude analysis: \(error.localizedDescription)")
            throw NutritionError.photoAnalysisFailed("Failed to parse analysis response")
        }
    }

    // MARK: - Cross-reference USDA (RAG Pattern)

    // For each identified item, search USDA for verified macro data.
    // Use USDA values when available and confidence is reasonable; fall back to Claude estimates.

    private func crossReferenceUSDA(
        items: [ClaudeFoodAnalysis.ClaudeFoodItem]
    ) async -> [PhotoAnalysisResult.PhotoFoodItem] {
        var verifiedItems: [PhotoAnalysisResult.PhotoFoodItem] = []

        for item in items {
            var finalItem = PhotoAnalysisResult.PhotoFoodItem(
                id: UUID().uuidString,
                name: item.name,
                estimatedPortion: item.portion,
                calories: item.calories,
                proteinGrams: item.protein,
                carbsGrams: item.carbs,
                fatGrams: item.fat,
                confidence: item.confidence
            )

            // Attempt USDA cross-reference for higher-confidence items
            if item.confidence >= 0.5 {
                do {
                    let usdaResults = try await foodSearch.searchUSDA(query: item.name)
                    if let best = usdaResults.first {
                        // Use USDA values (per 100g baseline), scaled to Claude's portion estimate.
                        // The Claude portion estimate is rough, so we keep its calorie estimate
                        // and scale USDA macro ratios to match.
                        let usdaRatio = best.calories > 0 ? item.calories / best.calories : 1.0
                        finalItem = PhotoAnalysisResult.PhotoFoodItem(
                            id: best.id,
                            name: best.name,
                            estimatedPortion: item.portion,
                            calories: item.calories,
                            proteinGrams: best.proteinGrams * usdaRatio,
                            carbsGrams: best.carbsGrams * usdaRatio,
                            fatGrams: best.fatGrams * usdaRatio,
                            confidence: min(item.confidence + 0.1, 1.0) // Boost confidence with USDA verification
                        )
                    }
                } catch {
                    // USDA lookup failed — keep Claude estimates
                    logger.debug("USDA cross-reference failed for '\(item.name)': \(error.localizedDescription)")
                }
            }

            verifiedItems.append(finalItem)
        }

        return verifiedItems
    }
}
