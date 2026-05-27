//
// PreferenceRetriever.swift
// Tempo
//
// Coach v2.1 Phase 4a — selects the top-N relevant preferences for a turn.
//
// Reads LearnedPreference rows, filters by isActive + scope-matches-today
// + polarity-is-not-suppressed, ranks by
// `confidence × recencyWeight × subjectRelevance(message)`, joins
// LearnedOutcome rows by decisionPrefID for confidence drag on
// preferences whose downstream actions led to negative outcomes.
//
// `avoidAtAllCosts` rows ALWAYS surface regardless of subject relevance
// — they're safety rails the agent must respect every turn.
//
// Per .plans/coach-v2.1/02-data-model.md + §03-services-and-data-flow.md.
//

import Foundation
import SwiftData

// MARK: - PreferenceRetriever

enum PreferenceRetriever {
    /// Default cap on how many preferences land in the context block.
    /// Tuned with the assembler's 3700-token budget in mind.
    static let defaultLimit = 30

    /// Recency half-life (days). A preference last seen ~14 days ago
    /// keeps half its weight; 28 days, a quarter. Tuned so the agent
    /// prefers recent context without forgetting older but still-active
    /// preferences.
    static let recencyHalfLifeDays: Double = 14

    /// Maximum confidence drag a single negative outcome can apply.
    /// Capped to avoid letting one bad day torch a high-confidence
    /// preference.
    static let outcomeDragPerNegative: Double = 0.10
    /// Maximum boost from a positive outcome.
    static let outcomeBoostPerPositive: Double = 0.05

    /// Primary entry point. `today` defaults to now; pass an explicit
    /// date in tests for determinism. `userMessage` is the last user
    /// turn (or nil at conversation start) — drives subject relevance.
    /// `dayType` is today's training-day-type when known; nil means
    /// dayType-scoped preferences are skipped (treated as not matching).
    static func retrieve(
        forContext context: ModelContext,
        userMessage: String? = nil,
        today: Date = Date(),
        dayType: DayType? = nil,
        limit: Int = defaultLimit,
        calendar: Calendar = .current
    ) -> [LearnedPreference] {
        let allActive = fetchActive(in: context)
        let outcomes = fetchOutcomes(in: context)
        let outcomesByPrefID = Self.groupOutcomes(outcomes)

        let todaysScopes = scopes(matchingToday: today, dayType: dayType, calendar: calendar)
        let messageTokens = tokenize(userMessage)

        // Avoid-at-all-costs ALWAYS surface (safety rails). They bypass
        // scope filtering but still get ranked + outcome-adjusted so
        // ordering inside that group is stable.
        let alwaysSurface = allActive.filter { $0.polarity == .avoidAtAllCosts }

        let scopeFiltered = allActive.filter { pref in
            pref.polarity != .avoidAtAllCosts && todaysScopes.contains(pref.scope)
        }

        let rankedSafety = alwaysSurface
            .map { ($0, rank(of: $0, messageTokens: messageTokens, today: today, outcomes: outcomesByPrefID[$0.id] ?? [])) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        let rankedRegular = scopeFiltered
            .map { ($0, rank(of: $0, messageTokens: messageTokens, today: today, outcomes: outcomesByPrefID[$0.id] ?? [])) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        // Safety rails first, then regular by rank, capped at limit.
        let combined = rankedSafety + rankedRegular
        return Array(combined.prefix(limit))
    }

    // MARK: - Ranking

    /// Composite score in [0, ~2]. Higher = more relevant.
    /// score = confidence * recencyWeight * (1 + subjectRelevance) + outcomeAdjust
    static func rank(
        of pref: LearnedPreference,
        messageTokens: Set<String>,
        today: Date,
        outcomes: [LearnedOutcome]
    ) -> Double {
        let recency = recencyWeight(lastSeen: pref.lastSeenAt, today: today)
        let relevance = subjectRelevance(subject: pref.subject, messageTokens: messageTokens)
        let outcomeAdjust = outcomeAdjustment(from: outcomes)
        return pref.confidence * recency * (1.0 + relevance) + outcomeAdjust
    }

    /// 1.0 when seen today, decays exponentially with `recencyHalfLifeDays`.
    /// Floor at 0.1 so very old preferences don't drop to ~0.
    static func recencyWeight(lastSeen: Date, today: Date) -> Double {
        let secondsPerDay = 86_400.0
        let elapsed = max(0, today.timeIntervalSince(lastSeen)) / secondsPerDay
        // half-life formula: 2^(-elapsed/halfLife)
        let raw = pow(2.0, -elapsed / recencyHalfLifeDays)
        return max(0.1, raw)
    }

    /// 0.0 (no tokens match) → ~1.0 (subject path tokens all appear in
    /// message). Tokens are taken from the dot-separated subject path
    /// AND a few common synonyms baked into well-known subject paths.
    /// Simple bag-of-words — good enough for v2.1; replace with embeddings
    /// in v3.x if needed.
    static func subjectRelevance(subject: String, messageTokens: Set<String>) -> Double {
        guard !messageTokens.isEmpty else { return 0.0 }
        let subjectTokens = subjectExpansion(subject: subject)
        guard !subjectTokens.isEmpty else { return 0.0 }
        let intersection = subjectTokens.intersection(messageTokens)
        return Double(intersection.count) / Double(subjectTokens.count)
    }

    /// Returns the set of tokens that make a subject path relevant.
    /// E.g. `meal_timing.breakfast.actual` → {meal, timing, breakfast,
    /// actual, eat, food}. Synonyms hard-coded for the top-level
    /// categories.
    static func subjectExpansion(subject: String) -> Set<String> {
        var tokens = Set<String>()
        for part in subject.lowercased().split(separator: ".") {
            for word in part.split(separator: "_") {
                tokens.insert(String(word))
            }
        }
        // Hard-coded synonyms for the top-level taxonomy nodes.
        if tokens.contains("meal") { tokens.formUnion(["eat", "food", "ate"]) }
        if tokens.contains("timing") { tokens.formUnion(["time", "when", "schedule"]) }
        if tokens.contains("digestion") { tokens.formUnion(["stomach", "bloat", "full"]) }
        if tokens.contains("breakfast") { tokens.formUnion(["morning", "am"]) }
        if tokens.contains("lunch") { tokens.formUnion(["noon", "midday"]) }
        if tokens.contains("dinner") { tokens.formUnion(["evening", "pm", "supper"]) }
        if tokens.contains("snack") { tokens.formUnion(["snacks"]) }
        if tokens.contains("training") { tokens.formUnion(["workout", "lift", "lifting", "gym"]) }
        if tokens.contains("sleep") { tokens.formUnion(["bed", "bedtime", "rest", "nap"]) }
        if tokens.contains("schedule") { tokens.formUnion(["plan", "calendar", "busy"]) }
        if tokens.contains("dislikes") { tokens.formUnion(["dislike", "hate", "avoid"]) }
        if tokens.contains("tone") { tokens.formUnion(["voice", "style"]) }
        if tokens.contains("goals") { tokens.formUnion(["goal", "target", "objective"]) }
        return tokens
    }

    /// Sum of capped per-outcome contributions. Positive outcomes add a
    /// boost; negative ones (including user-flagged regrets) drag.
    /// Symmetric caps stop runaway adjustments.
    static func outcomeAdjustment(from outcomes: [LearnedOutcome]) -> Double {
        var adjust = 0.0
        for outcome in outcomes where outcome.isGraded {
            if outcome.isNegative {
                adjust -= outcomeDragPerNegative
            } else if outcome.isPositive {
                adjust += outcomeBoostPerPositive
            }
        }
        // Hard ceiling/floor so a streak of one polarity can't dominate.
        return max(-0.30, min(0.30, adjust))
    }

    // MARK: - Scope matching

    /// Returns the set of `LearnedPreference.Scope` values that apply to
    /// "today" given the calendar date and optional dayType. `always` is
    /// always included. Weekday vs weekend derived from `today`. dayType-
    /// specific scopes included only when caller supplies a dayType.
    static func scopes(
        matchingToday today: Date,
        dayType: DayType?,
        calendar: Calendar = .current
    ) -> Set<LearnedPreference.Scope> {
        var scopes: Set<LearnedPreference.Scope> = [.always]

        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        if weekday == 1 || weekday == 7 {
            scopes.insert(.weekend)
        } else {
            scopes.insert(.weekday)
        }

        if let dayType {
            switch dayType {
            case .strength, .cardio, .double:
                scopes.insert(.dayTypeHard)
            case .rest:
                scopes.insert(.dayTypeRest)
            case .soccer:
                // Soccer days are both event-driven and dayTypeHard.
                scopes.insert(.dayTypeHard)
                scopes.insert(.eventMatch)
            }
        }

        // Seasonal: simple month-based summer band (Jun–Aug northern hemisphere).
        let month = calendar.component(.month, from: today)
        if (6...8).contains(month) {
            scopes.insert(.seasonalSummer)
        }

        // .eventTravel is set by external state (not derivable from a
        // calendar date alone). v2.1 ships without it; future versions
        // can read a travel-mode flag from UserSettings.

        return scopes
    }

    // MARK: - Tokenizer

    static func tokenize(_ message: String?) -> Set<String> {
        guard let message else { return [] }
        let lowered = message.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " "))
        let filtered = String(lowered.unicodeScalars.filter { allowed.contains($0) })
        let words = filtered.split(separator: " ").map(String.init).filter { $0.count >= 2 }
        return Set(words)
    }

    // MARK: - Fetch helpers

    private static func fetchActive(in context: ModelContext) -> [LearnedPreference] {
        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { $0.isActive }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchOutcomes(in context: ModelContext) -> [LearnedOutcome] {
        let descriptor = FetchDescriptor<LearnedOutcome>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func groupOutcomes(_ outcomes: [LearnedOutcome]) -> [UUID: [LearnedOutcome]] {
        var grouped: [UUID: [LearnedOutcome]] = [:]
        for outcome in outcomes {
            guard let prefID = outcome.decisionPrefID else { continue }
            grouped[prefID, default: []].append(outcome)
        }
        return grouped
    }
}
