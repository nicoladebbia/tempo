//
// MonthlyReview.swift
// Tempo
//
// D4 monthly arc (docs/INTELLIGENT_TRAINING_SYSTEM.md §17). One row per
// reviewed month:
//   • §17.1 — the logged interview: the qualitative signal Whoop/Withings
//     can't capture (what went well, what was skipped and why, niggles,
//     subjective progress, next month's goals + emphasis choice — the
//     interview is where Nicola naturally sets the §14 manual block).
//   • §17.2 — the Sonnet-generated summary text. `summaryText != nil` IS the
//     ≤1-Sonnet-call/month gate (same persisted-guard idea as
//     AdaptiveProfile.lastAIHydratedWeekKey, but the row itself is the guard).
//
// All fields additive per the single-V1-schema migration rule (§10).
//

import Foundation
import SwiftData

@Model
final class MonthlyReview {
    @Attribute(.unique)
    var id: UUID

    /// The reviewed month, "yyyy-MM" (e.g. "2026-06"). Unique per month by
    /// construction: the due-check fetches by key before ever creating one.
    var monthKey: String

    // MARK: - §17.1 interview (all optional — a skipped question is honest)

    var wentWell: String?
    /// What he skipped/struggled with AND why — the adherence story behind
    /// the numbers.
    var struggles: String?
    /// Injuries / niggles to carry into next month's prescriptions.
    var niggles: String?
    /// Subjective progress ("feel faster", "shirts fit tighter") — the signal
    /// no sensor has.
    var subjectiveProgress: String?
    var goalsNextMonth: String?

    /// The §14 manual block choice for next month, if he made one here.
    /// Raw storage (same enum-storage pattern as TrainingBlock.emphasisRaw).
    var chosenEmphasisRaw: String?

    // MARK: - §17.2 summary (Sonnet, ≤1/month)

    /// The generated report. Non-nil = this month's Sonnet call is SPENT.
    var summaryText: String?
    var summaryGeneratedAt: Date?

    var createdAt: Date

    // MARK: - Computed

    @Transient
    var chosenEmphasis: BlockEmphasis? {
        get { chosenEmphasisRaw.flatMap(BlockEmphasis.init(rawValue:)) }
        set { chosenEmphasisRaw = newValue?.rawValue }
    }

    init(
        monthKey: String,
        wentWell: String? = nil,
        struggles: String? = nil,
        niggles: String? = nil,
        subjectiveProgress: String? = nil,
        goalsNextMonth: String? = nil,
        chosenEmphasis: BlockEmphasis? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.monthKey = monthKey
        self.wentWell = wentWell
        self.struggles = struggles
        self.niggles = niggles
        self.subjectiveProgress = subjectiveProgress
        self.goalsNextMonth = goalsNextMonth
        self.chosenEmphasisRaw = chosenEmphasis?.rawValue
        self.summaryText = nil
        self.summaryGeneratedAt = nil
        self.createdAt = createdAt
    }
}
