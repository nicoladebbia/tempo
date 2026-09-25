//
// PhotoAnalysisService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif
// `maxClaudeVisionPixelEdge` (1568px) and the downsampling logic live in
// `UIImage+Downsample.swift`, shared with the receipt-upload path.

// MARK: - PhotoAnalysisServiceProtocol

protocol PhotoAnalysisServiceProtocol: Sendable {
    func analyzeMealPhoto(_ imageData: Data, remainingBudget: MacroBudget?) async throws -> PhotoAnalysisResult
}

// MARK: - PhotoAnalysisService

@Observable
final class PhotoAnalysisService: PhotoAnalysisServiceProtocol, @unchecked Sendable {
    private let foodSearch: any FoodSearchServiceProtocol
    /// Backend proxy for Claude calls. Per INTELLIGENCE_REMEDIATION_PLAN.md §3:
    /// the Anthropic key never ships in the app binary; image bytes are
    /// uploaded to /v1/nutrition/ai/proxy/vision instead of straight to Claude.
    private let apiClient: APIClient
    private let logger = Logger.nutrition

    init(foodSearch: any FoodSearchServiceProtocol, apiClient: APIClient) {
        self.foodSearch = foodSearch
        self.apiClient = apiClient
    }

    // MARK: - Analyze Meal Photo

    // Uses Claude Haiku via direct API call for real-time meal analysis.
    // Pattern: vision analysis → parse structured JSON → cross-reference USDA (RAG).

    func analyzeMealPhoto(
        _ imageData: Data,
        remainingBudget: MacroBudget?
    ) async throws -> PhotoAnalysisResult {
        // Step 1: Call Claude Vision via the backend proxy.
        let analysisJSON = try await callClaudeVision(imageData: imageData, budget: remainingBudget)

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

    // MARK: - Claude Vision API Call (via backend proxy)

    private func callClaudeVision(
        imageData: Data,
        budget: MacroBudget?
    ) async throws -> String {
        let base64Image = Self.downsampledBase64(imageData)
        let prompt = buildPrompt(budget: budget)

        let body = NutritionProxyVisionRequest(
            model: "haiku",
            system: "",
            userMessage: prompt,
            imageMediaType: "image/jpeg",
            imageBase64: base64Image,
            maxTokens: 1024,
            temperature: 0.2,
            caller: "photo_analysis"
        )

        do {
            let response: NutritionProxyTextResponse = try await apiClient.request(
                APIEndpoint<NutritionProxyTextResponse>.nutritionProxyVision(),
                body: body
            )
            return response.text
        } catch let error as APIError {
            switch error {
            case let .rateLimited(retryAfter):
                throw NutritionError.rateLimited(retryAfter: retryAfter)
            case let .serverError(statusCode):
                throw NutritionError.photoAnalysisFailed("Backend proxy returned status \(statusCode)")
            default:
                throw NutritionError.photoAnalysisFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Build Prompt

    private func buildPrompt(budget: MacroBudget?) -> String {
        var prompt = """
        Analyze this meal photo. Identify each food item and estimate its nutritional content.

        For EACH food item, include up to 2 alternative identifications when the
        visual is ambiguous (e.g. chicken vs. pork, white rice vs. cauliflower
        rice, beef vs. plant-based ground). Skip the alternatives array entirely
        when the identification is unambiguous (a banana is a banana).

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
              "confidence": 0.85,
              "alternatives": [
                {
                  "name": "alternative food name",
                  "portion": "1 cup",
                  "calories": 240,
                  "protein": 11.0,
                  "carbs": 28.0,
                  "fat": 9.0,
                  "confidence": 0.55
                }
              ]
            }
          ],
          "confidence": 0.8,
          "verdict": "A one-sentence summary of the meal."
        }

        Rules:
        - All numeric values must be numbers, not strings.
        - Confidence is 0.0 to 1.0 (how sure you are about the identification and portion).
        - The primary item is your best guess; alternatives are ranked by descending confidence.
        - Each alternative must carry its OWN macros — different foods have different macros even at the same portion.
        - Maximum 2 alternatives per item. Skip the alternatives key entirely for unambiguous items.
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
            return try JSONDecoder().decode(ClaudeFoodAnalysis.self, from: data)
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
            // Map any model-supplied alternatives onto the public DTO shape.
            // We deliberately do NOT USDA-verify alternatives — the user
            // hasn't picked one yet, so spending an extra API call per
            // candidate would multiply latency for guesses the user will
            // probably never accept.
            let mappedAlternatives = (item.alternatives ?? []).map { alt in
                PhotoAnalysisResult.FoodCandidate(
                    id: UUID().uuidString,
                    name: alt.name,
                    estimatedPortion: alt.portion,
                    calories: alt.calories,
                    proteinGrams: alt.protein,
                    carbsGrams: alt.carbs,
                    fatGrams: alt.fat,
                    confidence: alt.confidence
                )
            }

            var finalItem = PhotoAnalysisResult.PhotoFoodItem(
                id: UUID().uuidString,
                name: item.name,
                estimatedPortion: item.portion,
                calories: item.calories,
                proteinGrams: item.protein,
                carbsGrams: item.carbs,
                fatGrams: item.fat,
                confidence: item.confidence,
                alternatives: mappedAlternatives
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
                            confidence: min(item.confidence + 0.1, 1.0), // Boost confidence with USDA verification
                            alternatives: mappedAlternatives
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

    /// Decode → resize-to-fit → re-encode as 0.8 quality JPEG → base64 via the
    /// shared `UIImage.downsampledJPEGBase64` helper. Falls back to the raw
    /// bytes if UIImage decode fails (vector PDFs, HEIC variants without the
    /// right decoder) or if the image is already within the size cap.
    static func downsampledBase64(_ original: Data) -> String {
        #if canImport(UIKit)
        guard let image = UIImage(data: original) else {
            return original.base64EncodedString()
        }
        // Already small enough → keep the original bytes, skip the re-encode.
        guard max(image.size.width, image.size.height) > maxClaudeVisionPixelEdge else {
            return original.base64EncodedString()
        }
        return image.downsampledJPEGBase64()?.base64 ?? original.base64EncodedString()
        #else
        return original.base64EncodedString()
        #endif
    }
}
