//
// VoicePantryService.swift
// Tempo
//
// Turns a spoken pantry stock-take into structured pantry items via Claude
// Haiku (server-side nutrition proxy — no Anthropic key in the app binary).
//
// Two-call flow, mirroring VoiceMealLogService:
//   1. extract(transcript:) → up to 4 multiple-choice clarifying questions
//      for genuinely ambiguous portions / container sizes.
//   2. resolve(transcript:answers:) → final structured JSON array. Multiple
//      mentions of the same item are AGGREGATED into one total, each item
//      carries a "set" vs "add" intent and a "low" confidence flag for
//      uncertain quantities.
//

import Foundation
import os

// MARK: - Wire models

/// One fully-resolved pantry item. `VoiceClarifyingQuestion` is reused from
/// VoiceMealLogService (same shape: question + tappable options).
struct VoiceResolvedPantryItem: Decodable, Sendable {
    /// The spoken item name, e.g. "spaghetti".
    let name: String
    /// "set" (current total — "I have…") or "add" (a purchase — "I bought…").
    let intent: String
    /// The AGGREGATED total quantity (the AI sums 500 + 250 → 750).
    let quantity: Double
    /// Raw unit string — one of PantryUnit's raw values.
    let unitRaw: String
    /// Raw storage string — one of PantryStorageLocation's raw values, or nil.
    let storageRaw: String?
    /// The breakdown the AI used, e.g. ["500g pack", "half pack (250g)"].
    let components: [String]
    /// "high" | "low" — uncertain identity or approximate quantity.
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case name
        case intent
        case quantity
        case unitRaw = "unit"
        case storageRaw = "storage"
        case components
        case confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        intent = (try c.decodeIfPresent(String.self, forKey: .intent))?.lowercased() ?? "add"
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? 0
        unitRaw = try c.decodeIfPresent(String.self, forKey: .unitRaw) ?? ""
        storageRaw = try c.decodeIfPresent(String.self, forKey: .storageRaw)
        components = try c.decodeIfPresent([String].self, forKey: .components) ?? []
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
    }

    /// Maps `unitRaw` to a known PantryUnit. nil when the AI emitted a unit
    /// outside the allowed set — callers skip these (no silent gram fabrication).
    var unit: PantryUnit? {
        PantryUnit(rawValue: unitRaw)
    }

    /// Storage location, defaulting to `.pantry` when nil or unrecognised.
    var storage: PantryStorageLocation {
        guard let storageRaw else { return .pantry }
        return PantryStorageLocation(rawValue: storageRaw) ?? .pantry
    }

    var isLowConfidence: Bool {
        confidence?.lowercased() == "low"
    }

    var isSet: Bool {
        intent == "set"
    }
}

private struct VoiceResolvedPantryResponse: Decodable, Sendable {
    let items: [VoiceResolvedPantryItem]
}

enum VoicePantryError: LocalizedError {
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
final class VoicePantryService {
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "app.tempo", category: "voice-pantry")

    private let maxRetries = 2
    private let baseRetryDelay: Double = 1.0

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Step 1: extract + clarifying questions

    func extract(transcript: String) async throws -> [VoiceClarifyingQuestion] {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw VoicePantryError.emptyTranscript }

        let prompt = """
        The user described what's in their pantry out loud: "\(clean)"

        Identify each pantry item. For any item whose portion size OR container \
        size is genuinely ambiguous (e.g. "the olive oil bottle — what's its \
        full size?"), produce a multiple-choice clarifying question. Respond \
        with JSON only: {"questions":[{"question":"...","options":["...","...",\
        "...","..."]}]}. At most 4 questions total, each with at most 4 \
        options. If nothing is ambiguous, return {"questions":[]}.
        """

        let text = try await send(
            system: Self.extractSystemPrompt,
            prompt: prompt,
            feature: "voice_pantry_extract"
        )
        let parsed: VoiceExtractionResult = try parseJSON(
            text, as: VoiceExtractionResult.self, feature: "voice_pantry_extract"
        )
        return Array(parsed.questions.prefix(4))
    }

    // MARK: - Step 2: resolve to structured pantry items

    func resolve(
        transcript: String,
        answers: [String: String]
    ) async throws -> [VoiceResolvedPantryItem] {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw VoicePantryError.emptyTranscript }

        let answerLines = answers.isEmpty
            ? "(no clarifications were needed)"
            : answers.map { "- \($0.key) → \($0.value)" }.joined(separator: "\n")

        let prompt = """
        Spoken pantry stock-take: "\(clean)"

        Clarifications the user picked:
        \(answerLines)

        Return JSON only in this exact shape:
        {"items":[{"name":"","intent":"set|add","quantity":0,"unit":"",\
        "storage":"","components":["",""],"confidence":"high|low"}]}.

        Rules:
        - AGGREGATE multiple mentions of the same item into ONE total. \
        "a full 500g pack and a half pack" → quantity 750, \
        components ["500g pack","half pack (250g)"].
        - "unit" MUST be exactly one of: g, kg, ml, l, pieces, servings, oz, \
        lb, cans, bottles, jars, packs.
        - "storage" MUST be one of: pantry, fridge, freezer, cupboard. Default \
        to "pantry" when unclear.
        - "components" is the breakdown you used to reach the total. Use [] if \
        the item was a single simple mention.
        - "intent": use "set" when the user phrases a CURRENT TOTAL ("I have…", \
        "there's…", "I've got…"); use "add" when they phrase a PURCHASE \
        ("I bought…", "I got…", "add…").
        - "confidence": set "low" for any item whose quantity or identity is \
        uncertain or approximate ("about a third of a bottle"); otherwise "high".
        """

        let text = try await send(
            system: Self.resolveSystemPrompt,
            prompt: prompt,
            feature: "voice_pantry_resolve"
        )
        let parsed: VoiceResolvedPantryResponse = try parseJSON(
            text, as: VoiceResolvedPantryResponse.self, feature: "voice_pantry_resolve"
        )
        return parsed.items
    }

    // MARK: - Prompts

    private static let extractSystemPrompt = """
    You are Tempo's voice PANTRY parser. You receive a spoken description of \
    what's in someone's pantry and find ambiguous portions or container sizes \
    that need clarification. You ONLY output JSON. Clarifying questions must be \
    multiple-choice (the user taps an option; they cannot type). Keep questions \
    short and concrete.
    """

    private static let resolveSystemPrompt = """
    You are Tempo's voice PANTRY parser. Given a pantry stock-take and the \
    user's clarification choices, output a structured JSON array of pantry \
    items. Aggregate repeated mentions of the same item into one total. Output \
    JSON only — no prose, no markdown fences.
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

        throw VoicePantryError.apiFailed(lastError ?? APIError.unknown(statusCode: -1))
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
        throw VoicePantryError.parseFailed(errDetail)
    }
}
