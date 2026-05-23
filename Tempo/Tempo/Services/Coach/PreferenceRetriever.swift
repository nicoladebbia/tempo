//
// PreferenceRetriever.swift
// Tempo
//
// Ranks active LearnedPreferences by relevance to a user message so the
// CoachContextAssembler only spends tokens on the prefs that matter for the
// turn. Pure logic — no I/O, no async — to keep it cheap to call inside the
// assembler hot path and trivial to unit-test.
//
// Ranking signal (in priority order):
//   1. Subject-keyword overlap   — does the message mention this subject?
//   2. Pinned (userVerified)     — explicit user-confirmed prefs always rank high
//   3. Confidence                — fall back to model confidence for tie-break
//   4. Recency (lastSeenAt)      — newer evidence beats stale evidence
//
// We deliberately avoid TF-IDF / embeddings here. The active preference set
// is small (target < 200) and the subject taxonomy is hand-curated, so a
// rule-based ranker is faster, debuggable, and never wrong for the wrong reason.
//

import Foundation

enum PreferenceRetriever {

    /// Maximum number of preferences to surface for any single retrieval.
    /// The assembler uses this as the upper bound when composing the
    /// memory block; it may take fewer if the message is very narrow.
    static let defaultLimit = 12

    /// Returns up to `limit` active preferences ranked by relevance to
    /// `userMessage`. Inactive / superseded / deactivated preferences are
    /// filtered out before ranking.
    static func retrieve(
        for userMessage: String,
        from candidates: [LearnedPreference],
        limit: Int = defaultLimit,
        now: Date = Date()
    ) -> [LearnedPreference] {
        let tokens = tokenize(userMessage)
        let active = candidates.filter(\.isRetrievable)

        let scored = active.map { pref -> (LearnedPreference, Double) in
            (pref, score(pref: pref, tokens: tokens, now: now))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                // Stable secondary sort by id so the same input yields the
                // same output (tests rely on deterministic ordering).
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Returns the relevance score for a single preference. Exposed for
    /// tests so they can assert specific ranking behavior without rerunning
    /// the full pipeline.
    static func score(
        pref: LearnedPreference,
        tokens: Set<String>,
        now: Date
    ) -> Double {
        // 1. Subject keyword overlap. Subject is dot-separated
        //    ("meal_timing.dinner") — explode all segments + the pref text
        //    itself to catch synonyms ("dinner", "evening meal").
        let subjectTokens = tokenize(pref.subject.replacingOccurrences(of: ".", with: " "))
        let textTokens = tokenize(pref.text)
        let prefTokens = subjectTokens.union(textTokens)
        let overlap = Double(tokens.intersection(prefTokens).count)
        var score = overlap * 1.0

        // If overlap is zero, the pref is effectively off-topic. Give it a
        // tiny baseline so userVerified prefs can still bubble up when the
        // message is generic ("what should I eat?").
        if overlap == 0 { score = 0.05 }

        // 2. Pinned bonus — user-confirmed prefs are sacred.
        if pref.userVerified { score += 0.5 }

        // 3. Confidence — additive, scaled so it never dominates overlap.
        score += pref.confidence * 0.2

        // 4. Recency — exponential decay over 90 days; recent prefs score higher.
        let daysSince = max(0, now.timeIntervalSince(pref.lastSeenAt) / 86_400)
        let recency = exp(-daysSince / 90.0)
        score += recency * 0.1

        return score
    }

    // MARK: - Helpers

    /// Lowercase + split on non-alphanumeric, drop stopwords. Identical
    /// pipeline for queries and preference text so set intersection works.
    static func tokenize(_ s: String) -> Set<String> {
        let lowered = s.lowercased()
        let chars = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let cleaned = String(chars)
        return Set(
            cleaned
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 && !stopwords.contains($0) }
        )
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "but", "with", "that", "this", "have", "has",
        "you", "your", "yours", "are", "was", "were", "from", "what", "when",
        "where", "why", "how", "can", "should", "would", "could", "will",
        "about", "into", "than", "then", "they", "them", "their", "some",
        "any", "all", "not", "out", "off", "too", "very", "just", "also",
        "get", "got", "make", "made", "want", "need", "like", "know",
    ]
}
