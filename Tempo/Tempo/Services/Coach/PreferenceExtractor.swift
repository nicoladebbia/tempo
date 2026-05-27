//
// PreferenceExtractor.swift
// Tempo
//
// Coach v2.1 Phase 4c — post-conversation extractor.
//
// After a chat ends, runs a Haiku side-call asking the model to extract
// 0–N new preferences the user revealed in conversation. Returns
// preference candidates which are deduped against existing rows by
// subject + textual similarity, then persisted via CoachTools.recordPreference.
//
// The AI client is injected via PreferenceExtractionAIClient — tests
// supply a deterministic stub; Phase 6 wires a real adapter against the
// backend coach-chat (or a dedicated extract) route.
//
// Per .plans/coach-v2.1/04-ai-architecture.md "Extraction prompt"
// (the verbatim shape lives at `extractionPrompt(for:)`).
//

import Foundation
import SwiftData

// MARK: - PreferenceExtractor

enum PreferenceExtractor {
    /// Hard cap on preferences extracted per conversation. Anthropic
    /// returns more if the conversation is rich; we trust the model
    /// hint but enforce here too.
    static let maxPerConversation = 5

    /// Minimum text-similarity to consider two preferences the same
    /// subject (Jaccard over token bags). Above this threshold,
    /// reinforcement instead of insertion.
    static let dedupeThreshold = 0.6

    /// Public entry. Runs on the conversation-end hook (Phase 6.10).
    /// Returns the run report — count proposed + reinforced + skipped.
    /// Persistence happens via the supplied modelContext; tests pass
    /// in-memory contexts.
    @MainActor
    @discardableResult
    static func extract(
        from transcript: CoachTranscript,
        using aiClient: PreferenceExtractionAIClient,
        context: ModelContext,
        today: Date = Date()
    ) async throws -> RunReport {
        var report = RunReport()
        guard !transcript.turns.isEmpty else { return report }

        // Build prompt + dispatch the AI call.
        let prompt = extractionPrompt(for: transcript)
        let candidates: [PreferenceCandidate]
        do {
            candidates = try await aiClient.extractPreferences(prompt: prompt)
        } catch {
            // Silent failure per v2.1 plan Q7 — log + skip, don't retry.
            report.aiFailed = true
            return report
        }

        let capped = Array(candidates.prefix(maxPerConversation))
        for candidate in capped {
            // Re-validate confidence floors: explicit ≥ 0.6, inferred ≥ 0.4.
            guard candidatePassesFloor(candidate) else {
                report.skippedBelowFloor += 1
                continue
            }
            if let dupe = findDuplicate(of: candidate, in: context) {
                dupe.markReinforced(at: today)
                report.reinforced += 1
                continue
            }
            let pref = LearnedPreference(
                text: candidate.text,
                subject: candidate.subject,
                source: candidate.source,
                polarity: candidate.polarity,
                scope: candidate.scope,
                confidence: candidate.confidence,
                lastSeenAt: today,
                evidenceConvId: transcript.id,
                evidenceTurnIndex: candidate.turnIndex
            )
            context.insert(pref)
            report.proposed += 1
        }

        try context.save()
        return report
    }

    // MARK: - Confidence floors

    static func candidatePassesFloor(_ candidate: PreferenceCandidate) -> Bool {
        switch candidate.source {
        case .explicit, .userVerified: return candidate.confidence >= 0.6
        case .inferred: return candidate.confidence >= 0.4
        case .observed: return candidate.confidence >= 0.4
        }
    }

    // MARK: - Dedupe

    /// Returns an existing active LearnedPreference that should be
    /// reinforced instead of a fresh insert. Matches when subject path
    /// is identical AND text-similarity ≥ dedupeThreshold.
    @MainActor
    static func findDuplicate(
        of candidate: PreferenceCandidate,
        in context: ModelContext
    ) -> LearnedPreference? {
        let candidateSubject = candidate.subject
        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { pref in
                pref.isActive && pref.subject == candidateSubject
            }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let candidateTokens = tokenize(candidate.text)
        for row in existing {
            let rowTokens = tokenize(row.text)
            if jaccard(candidateTokens, rowTokens) >= dedupeThreshold {
                return row
            }
        }
        return nil
    }

    static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " "))
        let filtered = String(lowered.unicodeScalars.filter { allowed.contains($0) })
        return Set(filtered.split(separator: " ").map(String.init).filter { $0.count >= 2 })
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    // MARK: - Prompt

    /// Verbatim per .plans/coach-v2.1/04-ai-architecture.md §"Extraction
    /// prompt". The prompt is deterministic; only the transcript varies.
    static func extractionPrompt(for transcript: CoachTranscript) -> String {
        let renderedTurns = transcript.turns.enumerated().map { idx, turn in
            "[turn \(idx)] \(turn.role): \(turn.text)"
        }.joined(separator: "\n")

        return """
        You are extracting personal preferences from a user-coach conversation.

        Read this conversation carefully. Identify 0 to N new preferences the user
        revealed. Distinguish carefully:

        (a) Explicit: user stated a recurring pattern directly ("I never eat before 11am")
        (b) One-time: user expressed a single intent that's not a pattern ("I'm not lifting today")
        (c) Inferred: you inferred from behavior or context — lower confidence

        Output JSON array. No prose. Cap at \(maxPerConversation) preferences.

        Schema per item:
        {
          "text": "<short plain-English preference, third-person>",
          "subject": "<dot.path.taxonomy>",
          "confidence": <0.0-1.0>,
          "source": "explicit" | "inferred",
          "polarity": "positive" | "negative" | "avoidAtAllCosts",
          "scope": "always" | "weekday" | "weekend" | "dayTypeHard" | "dayTypeRest" | "eventMatch" | "eventTravel",
          "turnIndex": <int — which turn revealed this>,
          "evidence": "<short verbatim quote from convo>"
        }

        Confidence guidance:
        - explicit + clear pattern: 0.85-0.95
        - explicit but vague: 0.65-0.80
        - inferred from context: 0.45-0.55
        - inferred from one signal: 0.40 (will likely decay before reinforcement)

        DO NOT extract:
        - One-time intents (item (b)). They're not preferences.
        - Medical conditions stated in passing (those need explicit user verification).
        - Anything the user contradicted later in the same conversation.

        Conversation:
        \(renderedTurns)
        """
    }
}

// MARK: - Public types

/// Lightweight transcript view that the extractor consumes. Phase 6's
/// CoachConversation @Model maps to this struct at extraction time —
/// keeps Phase 4c independent of the (yet-to-be-built) conversation model.
struct CoachTranscript: Equatable {
    let id: UUID
    let turns: [Turn]

    struct Turn: Equatable {
        let role: String // "user" | "assistant"
        let text: String
    }
}

/// Candidate returned by the AI. Becomes a LearnedPreference row after
/// dedupe + confidence-floor checks.
struct PreferenceCandidate: Codable, Equatable {
    let text: String
    let subject: String
    let confidence: Double
    let source: LearnedPreference.Source
    let polarity: LearnedPreference.Polarity
    let scope: LearnedPreference.Scope
    let turnIndex: Int?
    let evidence: String?
}

/// AI-client injection seam. Real impl wraps APIClient + coach chat
/// route; tests pass a deterministic stub. Sendable because the
/// extractor (@MainActor) awaits the call off-actor.
protocol PreferenceExtractionAIClient: Sendable {
    func extractPreferences(prompt: String) async throws -> [PreferenceCandidate]
}

// MARK: - RunReport

extension PreferenceExtractor {
    struct RunReport: Equatable {
        var proposed: Int = 0
        var reinforced: Int = 0
        var skippedBelowFloor: Int = 0
        var aiFailed: Bool = false
    }
}
