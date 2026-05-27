//
// PreferenceExtractorAdapter.swift
// Tempo
//
// Coach v2.1 Phase 8a — real APIClient-backed adapter for
// PreferenceExtractionAIClient (Phase 4c protocol).
//
// Posts the extraction prompt as a single-shot Haiku call against the
// existing /v1/nutrition/ai/proxy/text route with caller="coach_extractor"
// so backend logs separate it from coach-chat and coach-summary spend.
// Parses the JSON array response into [PreferenceCandidate].
//
// Per .plans/coach-v2.1/04-ai-architecture.md "Extraction prompt".
//

import Foundation

// MARK: - PreferenceExtractorAdapter

struct PreferenceExtractorAdapter: PreferenceExtractionAIClient {
    let requester: APIRequester
    let maxTokens: Int

    init(requester: APIRequester, maxTokens: Int = 600) {
        self.requester = requester
        self.maxTokens = maxTokens
    }

    func extractPreferences(prompt: String) async throws -> [PreferenceCandidate] {
        let body = NutritionProxyTextRequest(
            model: "haiku",
            system: "You extract preferences from chat transcripts. Output JSON array only.",
            userMessage: prompt,
            maxTokens: maxTokens,
            temperature: 0.0,
            caller: "coach_extractor"
        )
        let response = try await requester.request(
            APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
            body: body
        )
        return Self.parseCandidates(from: response.text)
    }

    /// Defensive JSON-array parsing. Anthropic sometimes wraps responses
    /// in ```json fences or adds prose despite the prompt's instructions;
    /// we strip those and try the cleanest substring that looks like a
    /// JSON array.
    static func parseCandidates(from raw: String) -> [PreferenceCandidate] {
        let candidates = isolateJSONArray(raw)
        guard let data = candidates.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PreferenceCandidate].self, from: data)) ?? []
    }

    /// Returns the largest `[...]` substring in `raw`. When the model
    /// wraps the answer in markdown fences or adds a preamble, this peels
    /// it back to the array.
    static func isolateJSONArray(_ raw: String) -> String {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"),
              start < end
        else {
            return raw
        }
        return String(raw[start...end])
    }
}
