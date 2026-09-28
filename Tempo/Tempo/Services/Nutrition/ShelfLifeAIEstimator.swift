//
// ShelfLifeAIEstimator.swift
// Tempo
//
// Batched AI fallback for `ShelfLifeEstimator` — used ONLY when the
// hand-authored table has no keyword for a food (`estimate(...).matched ==
// false`). Goes through the same server-side nutrition proxy every other
// Haiku-backed nutrition feature uses (no Anthropic key in the app binary).
// Results are cached (in-memory, keyed by food+location) so the same unknown
// food never triggers a second network call in one app session.
//
// Injectable via the `ShelfLifeAIEstimating` protocol so LocalPantryService's
// tests never hit the network — they pass a fake.
//

import Foundation
import os

// MARK: - ShelfLifeAIRequest

struct ShelfLifeAIRequest: Hashable, Sendable {
    let canonicalName: String
    let storageLocation: PantryStorageLocation

    /// Cache / response-dictionary key.
    var key: String {
        "\(canonicalName)|\(storageLocation.rawValue)"
    }
}

// MARK: - ShelfLifeAIEstimating

protocol ShelfLifeAIEstimating: Sendable {
    /// Returns estimated days-to-spoil keyed by `ShelfLifeAIRequest.key`.
    /// A food missing from the result (e.g. the model didn't answer for it)
    /// simply keeps its generic-fallback estimate — callers never crash on
    /// a partial response.
    func estimateDays(_ requests: [ShelfLifeAIRequest]) async throws -> [String: Int]
}

// MARK: - ShelfLifeAICache

/// In-memory session cache. An `actor` so concurrent callers (multiple
/// pantry adds in quick succession) never race on the dictionary.
actor ShelfLifeAICache {
    static let shared = ShelfLifeAICache()

    private var storage: [String: Int] = [:]

    func get(_ key: String) -> Int? {
        storage[key]
    }

    func set(_ key: String, _ days: Int) {
        storage[key] = days
    }

    /// Test-only reset so cases don't bleed into each other via the shared singleton.
    func reset() {
        storage.removeAll()
    }
}

// MARK: - LiveShelfLifeAIEstimator

final class LiveShelfLifeAIEstimator: ShelfLifeAIEstimating {
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "app.tempo", category: "shelf-life-ai")

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    private struct Item: Decodable {
        let key: String
        let days: Int
    }

    private struct Response: Decodable {
        let estimates: [Item]
    }

    func estimateDays(_ requests: [ShelfLifeAIRequest]) async throws -> [String: Int] {
        guard !requests.isEmpty else {
            return [:]
        }

        let lines = requests
            .map { "- \($0.canonicalName) stored in the \($0.storageLocation.rawValue) (key: \"\($0.key)\")" }
            .joined(separator: "\n")

        let prompt = """
        Estimate days-until-spoiled for each of these foods, given their storage location:
        \(lines)

        Return JSON only, no prose, no markdown fences, in this exact shape:
        {"estimates":[{"key":"","days":0}]}

        Rules:
        - "days" is a whole number of days from today until the food should be
          discarded (typical shelf life for that storage location).
        - Use the EXACT "key" string given above for each food, unchanged.
        - Be conservative (food safety) rather than optimistic.
        """

        let body = NutritionProxyTextRequest(
            model: "haiku",
            system: "You are Tempo's food shelf-life estimator. Output JSON only.",
            userMessage: prompt,
            maxTokens: 800,
            temperature: 0.1,
            caller: "pantry_shelf_life_estimate"
        )
        let response: NutritionProxyTextResponse = try await apiClient.request(
            APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
            body: body
        )

        let cleaned = VoicePantryService.stripMarkdownFence(response.text)
        guard let data = cleaned.data(using: .utf8) else {
            logger.error("shelf-life AI response not UTF8")
            return [:]
        }
        do {
            let parsed = try JSONDecoder().decode(Response.self, from: data)
            var result: [String: Int] = [:]
            for item in parsed.estimates where item.days > 0 {
                result[item.key] = item.days
            }
            return result
        } catch {
            logger.error("shelf-life AI parse failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
