//
// PreferenceExtractor.swift
// Tempo
//
// Post-conversation Haiku side-call that mines a chat transcript for new
// `LearnedPreference` entries. Runs after a coach session ends — never
// during the agent loop, so it can't slow the user's experience.
//
// Why a separate extractor instead of letting the agent emit prefs inline?
//
// • The agent loop optimizes for the user's immediate ask. Asking it to
//   *also* curate long-term memory mid-turn risks polluting tool calls or
//   missing subtle implicit signals ("ugh, no eggs again" → dislikes eggs).
// • An extractor pass is a single small Haiku call (~$0.001) so it's cheap
//   to run on every conversation.
// • Output is JSON-shaped, so failures are easy to detect and re-prompt.
//
// Output contract (Claude returns this JSON):
//
// {
//   "preferences": [
//     {
//       "text": "...",
//       "subject": "meal_timing.dinner",
//       "confidence": 0.0-1.0,
//       "source": "explicit" | "observed" | "inferred",
//       "supersedes": [<UUID-of-existing-pref>, ...]   // optional
//     }
//   ]
// }
//
// The extractor:
//   • dedupes incoming preferences against the existing active store
//     (subject + near-text equality)
//   • supersedes prior prefs the model flagged as contradicted
//   • caps inserts per call (defensive guardrail — 8 max per session)
//   • returns the inserted preferences for callers that want to display
//     "Coach learned: ..." chips
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class PreferenceExtractor {

    private let apiClient: APIClient
    private let logger = Logger(subsystem: "com.tempo.app", category: "PreferenceExtractor")

    /// Hard ceiling on prefs minted per extraction pass. Defense against
    /// a runaway model dumping every utterance into memory.
    private let maxPreferencesPerCall = 8

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Extract preferences from a finished conversation transcript and
    /// persist them. Returns the new preferences inserted into `context`.
    /// Existing prefs that were superseded are marked but not deleted.
    @discardableResult
    func extract(
        transcript: String,
        conversationID: UUID,
        context: ModelContext
    ) async throws -> [LearnedPreference] {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let existing = BehaviorObserver.fetchActivePreferences(in: context)
        let response = try await callHaiku(transcript: transcript, existing: existing)
        let parsed = try parse(jsonText: response)
        return persist(
            parsed: parsed,
            existing: existing,
            conversationID: conversationID,
            context: context
        )
    }

    // MARK: - Claude call

    private func callHaiku(
        transcript: String,
        existing: [LearnedPreference]
    ) async throws -> String {
        let system = Self.systemPrompt(existing: existing)
        let request = NutritionProxyTextRequest(
            model: "haiku",
            system: system,
            userMessage: "Transcript:\n\(transcript)\n\nReturn JSON now.",
            maxTokens: 1_500,
            temperature: 0.2,
            caller: "coach_extractor"
        )
        let endpoint = APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText()
        let response = try await apiClient.request(endpoint, body: request)
        return response.text
    }

    static func systemPrompt(existing: [LearnedPreference]) -> String {
        // Inline up to 30 existing prefs so the model knows what's already
        // known + what could be superseded. More than 30 is rare for this
        // user; truncate by recency if it ever blows out.
        let pinned = existing
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
            .prefix(30)
            .map { "- [\($0.id.uuidString.prefix(8))] (\($0.subject)) \($0.text)" }
            .joined(separator: "\n")

        return """
        You analyze a Tempo Coach chat transcript and extract durable user
        preferences worth remembering across future sessions. A preference
        is durable when it's:

          • a stated routine, constraint, or dislike ("I don't eat eggs",
            "lights out by 11", "soccer Tue/Thu 7-9pm")
          • a clarification the user gave to a tool the agent ran
          • a contradiction or correction of a prior preference

        DO NOT extract:

          • one-off facts ("had pizza tonight")
          • short-term context ("busy this week")
          • tool execution side-effects already logged elsewhere

        Subjects MUST be drawn from the canonical taxonomy below. Use the
        exact dot-string. Confidence is 0.0-1.0; .explicit user-stated → 0.9,
        clarification → 0.8, observed in turn → 0.6, inferred → 0.5.

        Canonical subjects:
          meal_timing.{breakfast|lunch|dinner|snack}
          meal_content.{cuisine|ingredients.disliked|prep_speed}
          training.{intensity|timing.preferred|recovery.tolerance}
          sleep.{bedtime|wake|weekend_drift}
          social.{weekday|weekend|match_days}
          study.{peak_hours|session_length}
          work.{peak_hours|schedule}
          digestion.{before_bed|before_training}
          mood.weekly_pattern
          recovery.tolerance.{strain|sleep_debt}
          general.{communication_style|coaching_tone}

        Existing preferences (use these short IDs in `supersedes` if a new
        pref contradicts an old one):
        \(pinned.isEmpty ? "(none)" : pinned)

        Output strictly this JSON shape (no preamble, no markdown fence):
        {
          "preferences": [
            {
              "text": "short, plain sentence in third person",
              "subject": "<from taxonomy>",
              "confidence": 0.0,
              "source": "explicit" | "observed" | "inferred",
              "supersedes": ["<8-char-id>", ...]
            }
          ]
        }

        Return {"preferences": []} when nothing durable was said.
        """
    }

    // MARK: - Parsing

    struct ParsedResponse: Decodable {
        let preferences: [Parsed]
    }

    struct Parsed: Decodable {
        let text: String
        let subject: String
        let confidence: Double
        let source: String
        let supersedes: [String]?
    }

    func parse(jsonText: String) throws -> ParsedResponse {
        let cleaned = Self.extractJSON(jsonText)
        guard let data = cleaned.data(using: .utf8) else {
            throw ExtractorError.malformedJSON("no utf-8 data")
        }
        do {
            return try JSONDecoder().decode(ParsedResponse.self, from: data)
        } catch {
            logger.error("PreferenceExtractor: JSON decode failed: \(error.localizedDescription)")
            throw ExtractorError.malformedJSON(error.localizedDescription)
        }
    }

    /// Pull the first `{...}` block out of the response. Haiku sometimes
    /// wraps JSON in prose despite explicit instructions — be defensive.
    static func extractJSON(_ raw: String) -> String {
        guard let start = raw.firstIndex(of: "{") else { return raw }
        var depth = 0
        var end: String.Index?
        for i in raw[start...].indices {
            let c = raw[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { end = i; break }
            }
        }
        guard let end else { return raw }
        return String(raw[start...end])
    }

    // MARK: - Persistence

    func persist(
        parsed: ParsedResponse,
        existing: [LearnedPreference],
        conversationID: UUID,
        context: ModelContext
    ) -> [LearnedPreference] {
        var inserted: [LearnedPreference] = []
        let now = Date()

        for entry in parsed.preferences.prefix(maxPreferencesPerCall) {
            guard let source = LearnedPreference.Source(rawValue: entry.source) else {
                logger.warning("PreferenceExtractor: unknown source '\(entry.source)' — skipping")
                continue
            }

            // Supersession: any existing pref the model flagged gets
            // `supersede(by:)` and is excluded from dedup.
            let supersededIDs = (entry.supersedes ?? []).compactMap { shortID -> LearnedPreference? in
                existing.first { $0.id.uuidString.hasPrefix(shortID) }
            }

            // Dedup: skip if an existing pref has identical subject + near
            // text and wasn't just superseded.
            let duplicate = existing.first { pref in
                pref.subject == entry.subject
                    && pref.text.localizedCaseInsensitiveCompare(entry.text) == .orderedSame
                    && !supersededIDs.contains(where: { $0.id == pref.id })
            }
            if let duplicate {
                duplicate.markReinforced(at: now)
                continue
            }

            let pref = LearnedPreference(
                text: entry.text,
                subject: entry.subject,
                confidence: entry.confidence,
                source: source,
                firstSeenAt: now,
                lastSeenAt: now,
                sourceConversationID: conversationID
            )
            context.insert(pref)
            for superseded in supersededIDs {
                superseded.supersede(by: pref.id, at: now)
            }
            inserted.append(pref)
        }

        try? context.save()
        logger.info("PreferenceExtractor: inserted \(inserted.count) prefs from conversation \(conversationID)")
        return inserted
    }

    enum ExtractorError: Error, LocalizedError {
        case malformedJSON(String)

        var errorDescription: String? {
            switch self {
            case let .malformedJSON(msg): "Coach extractor returned malformed JSON: \(msg)"
            }
        }
    }
}
