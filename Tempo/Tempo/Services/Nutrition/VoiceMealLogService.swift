//
// VoiceMealLogService.swift
// Tempo
//
// Turns a spoken meal description into structured food items via Claude
// Haiku (server-side nutrition proxy — no Anthropic key in the app binary).
//
// Two-call flow:
//   1. extract(transcript:) → items + up to 4 multiple-choice clarifying
//      questions for ambiguous portions/times.
//   2. resolve(transcript:answers:) → final structured JSON array, with a
//      "low" confidence flag on items Haiku can't identify confidently.
//

import Foundation
import os

// MARK: - Wire models

/// One tappable multiple-choice clarifying question (no free-text entry).
struct VoiceClarifyingQuestion: Codable, Identifiable, Sendable {
    var id: String { question }
    let question: String
    let options: [String]
}

/// First-pass extraction: provisional items + questions to disambiguate.
struct VoiceExtractionResult: Codable, Sendable {
    let questions: [VoiceClarifyingQuestion]
}

/// One fully-resolved food item. `logged_at` is accepted from Haiku but not
/// surfaced — the existing MealLog save path stamps the timestamp, same as
/// Search/Photo/Scan.
struct VoiceResolvedItem: Decodable, Sendable {
    let name: String
    let quantityG: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case name
        case quantityG = "quantity_g"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case confidence
        case loggedAt = "logged_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        quantityG = try c.decodeIfPresent(Double.self, forKey: .quantityG) ?? 0
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        proteinG = try c.decodeIfPresent(Double.self, forKey: .proteinG) ?? 0
        carbsG = try c.decodeIfPresent(Double.self, forKey: .carbsG) ?? 0
        fatG = try c.decodeIfPresent(Double.self, forKey: .fatG) ?? 0
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
    }

    var isLowConfidence: Bool {
        confidence?.lowercased() == "low"
    }
}

private struct VoiceResolvedResponse: Decodable, Sendable {
    let items: [VoiceResolvedItem]
}

enum VoiceMealLogError: LocalizedError {
    case emptyTranscript
    case apiFailed(Error)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript: "I didn't catch that — try again."
        case let .apiFailed(error): "Couldn't reach the assistant: \(error.localizedDescription)"
        case let .parseFailed(detail): "Couldn't read the assistant's reply: \(detail)"
        }
    }
}

// MARK: - Service

@Observable
@MainActor
final class VoiceMealLogService {
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "app.tempo", category: "voice-meal-log")

    private let maxRetries = 2
    private let baseRetryDelay: Double = 1.0

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Step 1: extract + clarifying questions

    func extract(transcript: String) async throws -> [VoiceClarifyingQuestion] {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw VoiceMealLogError.emptyTranscript }

        let prompt = """
        The user described a meal out loud: "\(clean)"

        Identify each food item. For any item whose portion size OR time of \
        eating is ambiguous, produce a clarifying question. Respond with JSON \
        only: {"questions":[{"question":"...","options":["...","...","...","..."]}]}.
        At most 4 questions total, each with at most 4 options. If nothing is \
        ambiguous, return {"questions":[]}.
        """

        let text = try await send(
            system: Self.extractSystemPrompt,
            prompt: prompt,
            feature: "voice_meal_extract"
        )
        let parsed: VoiceExtractionResult = try parseJSON(
            text, as: VoiceExtractionResult.self, feature: "voice_meal_extract"
        )
        return Array(parsed.questions.prefix(4))
    }

    // MARK: - Step 2: resolve to structured items

    func resolve(
        transcript: String,
        answers: [String: String]
    ) async throws -> [VoiceResolvedItem] {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw VoiceMealLogError.emptyTranscript }

        let answerLines = answers.isEmpty
            ? "(no clarifications were needed)"
            : answers.map { "- \($0.key) → \($0.value)" }.joined(separator: "\n")

        let prompt = """
        Spoken meal: "\(clean)"

        Clarifications the user picked:
        \(answerLines)

        Return JSON only in this exact shape:
        {"items":[{"name":"","quantity_g":0,"calories":0,"protein_g":0,\
        "carbs_g":0,"fat_g":0,"logged_at":"ISO8601","confidence":"high|low"}]}.
        Estimate macros from standard nutrition databases. Set \
        "confidence":"low" for any item you cannot identify with reasonable \
        certainty; otherwise "high".
        """

        let text = try await send(
            system: Self.resolveSystemPrompt,
            prompt: prompt,
            feature: "voice_meal_resolve"
        )
        let parsed: VoiceResolvedResponse = try parseJSON(
            text, as: VoiceResolvedResponse.self, feature: "voice_meal_resolve"
        )
        return parsed.items
    }

    // MARK: - Prompts

    private static let extractSystemPrompt = """
    You are Tempo's voice nutrition parser. You receive a spoken meal \
    description and find ambiguous portions or eating times that need \
    clarification. You ONLY output JSON. Clarifying questions must be \
    multiple-choice (the user taps an option; they cannot type). Keep \
    questions short and concrete.
    """

    private static let resolveSystemPrompt = """
    You are Tempo's voice nutrition parser. Given a meal description and the \
    user's clarification choices, output a structured JSON array of food \
    items with per-item macro estimates. Output JSON only — no prose, no \
    markdown fences.
    """

    // MARK: - Proxy call (mirrors NutritionCoachService.sendWithRetry)

    private func send(system: String, prompt: String, feature: String) async throws -> String {
        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "haiku",
                    system: system,
                    userMessage: prompt,
                    maxTokens: 800,
                    temperature: 0.2,
                    caller: feature
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                logger.info("[\(feature)] Haiku response received (attempt \(attempt))")
                return response.text
            } catch let error as APIError {
                lastError = error
                logger.warning("[\(feature)] proxy error (attempt \(attempt)): \(String(describing: error))")
                guard error.isRetryable, attempt < maxRetries else { break }
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch {
                lastError = error
                logger.error("[\(feature)] unexpected error: \(error.localizedDescription)")
                break
            }
        }

        throw VoiceMealLogError.apiFailed(lastError ?? APIError.unknown(statusCode: -1))
    }

    // MARK: - JSON parsing (same extraction strategy as NutritionCoachService)

    private func parseJSON<T: Decodable>(_ response: String, as type: T.Type, feature: String) throws -> T {
        let decoder = JSONDecoder()
        var firstDecodeError: Error?

        if let data = response.data(using: .utf8) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                firstDecodeError = error
            }
        }

        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}")
        {
            let jsonString = String(response[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8),
               let result = try? decoder.decode(T.self, from: data)
            {
                logger.info("[\(feature)] JSON extracted from wrapped response")
                return result
            }
        }

        let errDetail = firstDecodeError.map { String(describing: $0) } ?? "no decode error"
        logger.error("[\(feature)] parse failed: \(response.prefix(200)) | \(errDetail, privacy: .public)")
        throw VoiceMealLogError.parseFailed(errDetail)
    }
}
