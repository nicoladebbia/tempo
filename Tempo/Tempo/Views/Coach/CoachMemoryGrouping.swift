//
// CoachMemoryGrouping.swift
// Tempo
//
// Coach v2.1 Phase 8b — pure helper for CoachMemoryView's
// polarity-and-scope grouping. Extracted from the view so it's
// unit-testable without standing up SwiftUI.
//

import Foundation

enum CoachMemoryGrouping {
    struct Group: Equatable {
        let scope: LearnedPreference.Scope
        let preferences: [LearnedPreference]
    }

    /// Returns `LearnedPreference` rows filtered by `polarity`, grouped
    /// by `scope`, ordered by the canonical scope display order, with
    /// each scope's rows sorted by confidence (descending) and falling
    /// back to lastSeenAt (most-recent first) when confidence ties.
    ///
    /// Scopes with zero matching rows are omitted.
    static func group(
        preferences: [LearnedPreference],
        polarity: LearnedPreference.Polarity
    ) -> [Group] {
        let matching = preferences.filter { $0.polarity == polarity }
        // Bucket by scope.
        var buckets: [LearnedPreference.Scope: [LearnedPreference]] = [:]
        for pref in matching {
            buckets[pref.scope, default: []].append(pref)
        }
        // Emit in canonical order, sort each bucket, skip empties.
        return canonicalScopeOrder.compactMap { scope in
            guard var rows = buckets[scope], !rows.isEmpty else { return nil }
            rows.sort { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
            return Group(scope: scope, preferences: rows)
        }
    }

    /// Display order for sections — "Always" first (broadest), then
    /// weekday/weekend, then day-type-driven, then events, then seasonal.
    static let canonicalScopeOrder: [LearnedPreference.Scope] = [
        .always,
        .weekday,
        .weekend,
        .dayTypeHard,
        .dayTypeRest,
        .eventMatch,
        .eventTravel,
        .seasonalSummer,
    ]
}
