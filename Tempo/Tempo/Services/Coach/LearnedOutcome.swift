//
// LearnedOutcome.swift
// Tempo
//
// Coach v2.1 Phase 4a — the causal-reasoning table.
//
// One row per Coach action that's been graded. Lets the agent reason
// from cause-and-effect ("last 3 times you ate dinner <90min before
// sleep, your HRV next morning dropped 8%") rather than only
// correlation patterns.
//
// Written by OutcomeGrader (Phase 6.12). Read by PreferenceRetriever
// (Phase 4a) to drag confidence when a preference's downstream actions
// consistently lead to bad outcomes, and by WeeklySelfGradeCard
// (Phase 8.13) for the weekly summary.
//
// Per .plans/coach-v2.1/02-data-model.md "Model 2 — LearnedOutcome".
//

import Foundation
import SwiftData

// MARK: - LearnedOutcome

@Model
final class LearnedOutcome {
    @Attribute(.unique)
    var id: UUID

    /// If the action was driven by a specific preference, link to it.
    /// Used by the retriever to adjust confidence on that preference
    /// based on downstream success/failure.
    var decisionPrefID: UUID?

    /// Which conversation produced the action.
    var decisionConvID: UUID

    /// Which turn within that conversation (0-indexed).
    var decisionTurnIndex: Int

    /// Tool that fired (e.g. "moveMeal", "swapDayType").
    var actionToolName: String

    /// Plain-English summary ("moved dinner from 19:30 to 20:30 on 2026-05-26").
    var actionSummary: String

    /// When Coach made the suggestion.
    var decisionDate: Date

    /// When the grader should evaluate the outcome.
    /// Tool-dependent: meal moves = sameDay, training swaps = next48h,
    /// activity inserts = nextDay, bedtime shifts = nextDay.
    var evaluationDueAt: Date

    /// Stored raw value of `Outcome`. Nil until the grader runs.
    /// Access via `outcome` computed accessor.
    var outcomeRaw: String?

    /// Compact data snippet that drove the outcome
    /// ("HRV next morning: 78, baseline 85, Δ -8%"). Nil until graded.
    var evidence: String?

    /// When the grader produced this row's outcome + evidence.
    /// Nil while still pending evaluation.
    var gradedAt: Date?

    /// If user explicitly rated the suggestion (e.g. long-pressed
    /// "I regretted this" in chat history), gets stamped true. Treated
    /// as a strong negative signal by the retriever and self-grade card.
    var userOverride: Bool

    // MARK: - Computed accessor

    var outcome: Outcome? {
        get {
            guard let raw = outcomeRaw else { return nil }
            return Outcome(rawValue: raw)
        }
        set { outcomeRaw = newValue?.rawValue }
    }

    /// True once gradedAt + outcomeRaw are set.
    var isGraded: Bool { gradedAt != nil && outcomeRaw != nil }

    /// True when the outcome counts as a "good" suggestion for the
    /// weekly self-grade card (goodSleep / goodWorkout / followedThrough).
    var isPositive: Bool {
        guard let outcome else { return false }
        return outcome.isPositive
    }

    /// True for negative outcomes (badSleep / badWorkout / abandoned) OR
    /// user-flagged regrets via long-press.
    var isNegative: Bool {
        if userOverride { return true }
        guard let outcome else { return false }
        return outcome.isNegative
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        decisionPrefID: UUID? = nil,
        decisionConvID: UUID,
        decisionTurnIndex: Int,
        actionToolName: String,
        actionSummary: String,
        decisionDate: Date = Date(),
        evaluationDueAt: Date,
        outcome: Outcome? = nil,
        evidence: String? = nil,
        gradedAt: Date? = nil,
        userOverride: Bool = false
    ) {
        self.id = id
        self.decisionPrefID = decisionPrefID
        self.decisionConvID = decisionConvID
        self.decisionTurnIndex = decisionTurnIndex
        self.actionToolName = actionToolName
        self.actionSummary = actionSummary
        self.decisionDate = decisionDate
        self.evaluationDueAt = evaluationDueAt
        self.outcomeRaw = outcome?.rawValue
        self.evidence = evidence
        self.gradedAt = gradedAt
        self.userOverride = userOverride
    }
}

// MARK: - Outcome

extension LearnedOutcome {
    /// What actually happened after Coach made the suggestion.
    /// `unclear` means the grader couldn't pull enough evidence (e.g.,
    /// no HK sleep data for that night) — counts neutrally in the
    /// self-grade card.
    enum Outcome: String, Codable, CaseIterable, Sendable {
        case goodSleep
        case badSleep
        case goodWorkout
        case badWorkout
        case followedThrough
        case abandoned
        case unclear

        var isPositive: Bool {
            switch self {
            case .goodSleep, .goodWorkout, .followedThrough: return true
            default: return false
            }
        }

        var isNegative: Bool {
            switch self {
            case .badSleep, .badWorkout, .abandoned: return true
            default: return false
            }
        }
    }
}
