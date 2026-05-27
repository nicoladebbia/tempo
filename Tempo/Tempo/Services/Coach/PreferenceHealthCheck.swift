//
// PreferenceHealthCheck.swift
// Tempo
//
// Coach v2.1 Phase 6c — proactive contradiction scan.
//
// Daily job. For each high-confidence LearnedPreference whose linked
// outcomes are predominantly negative in the recent window, sets
// `needsReview: true`. Doesn't auto-update the preference — surfacing
// happens in the next chat open via the review queue (Phase 7 will
// read pendingReviewPreferences and have the agent ask askUser first).
//
// Pure logic. No AI calls.
//
// Per .plans/coach-v2.1/02-data-model.md and §03-services-and-data-flow.md
// "Nightly jobs / PreferenceHealthCheck".
//

import Foundation
import SwiftData

// MARK: - PreferenceHealthCheck

enum PreferenceHealthCheck {
    /// Confidence threshold above which the check considers a preference
    /// "high enough" to be worth flagging for review when behavior
    /// contradicts. Below this we let decay handle the drift.
    static let highConfidenceFloor = 0.70

    /// Minimum negative-outcome count in the recent window before the
    /// flag fires. Per v2.1 plan: "contradicted 2+ times in last 14 days".
    static let minNegativeOutcomesToFlag = 2

    /// Window in days for the negative-outcome count.
    static let recentWindowDays = 14

    /// Result for the daily-reset log + tests.
    struct RunReport: Equatable {
        var flagged: Int = 0
        var clearedExistingFlag: Int = 0
        var examined: Int = 0
    }

    /// Entry. `today` defaults to now; tests pass fixed dates.
    /// Returns the run report.
    @MainActor
    @discardableResult
    static func scan(
        in context: ModelContext,
        today: Date = Date()
    ) throws -> RunReport {
        var report = RunReport()
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -recentWindowDays,
            to: today
        ) else { return report }

        let activeDescriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { pref in
                pref.isActive
            }
        )
        let preferences = (try? context.fetch(activeDescriptor)) ?? []

        let outcomeDescriptor = FetchDescriptor<LearnedOutcome>(
            predicate: #Predicate<LearnedOutcome> { row in
                row.gradedAt != nil && row.decisionDate >= cutoff
            }
        )
        let recentOutcomes = (try? context.fetch(outcomeDescriptor)) ?? []
        let outcomesByPrefID = Self.groupByLinkedPref(recentOutcomes)

        for pref in preferences {
            report.examined += 1
            // userVerified rows + red-line polarity are immune — the user
            // explicitly told Coach these. Don't second-guess via outcome
            // patterns.
            if pref.source == .userVerified { continue }
            if pref.polarity == .avoidAtAllCosts { continue }
            guard pref.confidence >= highConfidenceFloor else { continue }

            let linkedOutcomes = outcomesByPrefID[pref.id] ?? []
            let negativeCount = linkedOutcomes.filter { $0.isNegative }.count
            let positiveCount = linkedOutcomes.filter { $0.isPositive }.count

            // Contradicted = enough negative outcomes AND positives don't
            // outweigh them. Net-negative ratio guards against the
            // "few small mistakes mixed with many wins" false flag.
            if negativeCount >= minNegativeOutcomesToFlag, negativeCount > positiveCount {
                if !pref.needsReview {
                    pref.needsReview = true
                    report.flagged += 1
                }
            } else if pref.needsReview {
                // Behavior is no longer contradicting — clear the flag so
                // the agent doesn't keep surfacing a resolved review.
                pref.needsReview = false
                report.clearedExistingFlag += 1
            }
        }

        try context.save()
        return report
    }

    /// Helper for callers (Phase 7 review-queue ordering). Returns the
    /// active preferences flagged for review, most-recent-lastSeen first.
    @MainActor
    static func pendingReviewPreferences(in context: ModelContext) -> [LearnedPreference] {
        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { pref in
                pref.isActive && pref.needsReview
            }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    // MARK: - Helpers

    private static func groupByLinkedPref(_ outcomes: [LearnedOutcome]) -> [UUID: [LearnedOutcome]] {
        var grouped: [UUID: [LearnedOutcome]] = [:]
        for outcome in outcomes {
            guard let prefID = outcome.decisionPrefID else { continue }
            grouped[prefID, default: []].append(outcome)
        }
        return grouped
    }
}
