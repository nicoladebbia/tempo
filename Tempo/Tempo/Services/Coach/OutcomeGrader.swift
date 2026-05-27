//
// OutcomeGrader.swift
// Tempo
//
// Coach v2.1 Phase 6a — turns PendingOutcome rows into LearnedOutcome rows.
//
// Runs daily from DailyResetCoordinator (Phase 6c). For each pending row
// whose `evaluationDueAt` has passed, asks the evidence provider for the
// data the grader needs (HK sleep, meal logs, workout completion),
// scores the outcome, writes the LearnedOutcome row, and deletes the
// pending row.
//
// Pure orchestration — the evidence provider is a Sendable protocol so
// tests inject a deterministic stub. The real implementation lives in
// Phase 6c wiring (wraps HealthKit + SwiftData reads).
//
// Per .plans/coach-v2.1/02-data-model.md and §03-services-and-data-flow.md
// "Nightly jobs / OutcomeGrader.run".
//

import Foundation
import SwiftData

// MARK: - OutcomeGrader

enum OutcomeGrader {
    /// Result of one grading pass. Useful for the daily-reset log + tests.
    struct RunReport: Equatable {
        var graded: Int = 0
        var skippedNotYetDue: Int = 0
        var unclearDueToMissingEvidence: Int = 0
    }

    /// Entry point. `today` defaults to now; tests pass a fixed date for
    /// determinism. `provider` supplies the evidence for each tool's
    /// grading. Throws on persistence failure.
    @MainActor
    @discardableResult
    static func run(
        in context: ModelContext,
        today: Date = Date(),
        provider: OutcomeEvidenceProvider
    ) async throws -> RunReport {
        var report = RunReport()

        let descriptor = FetchDescriptor<PendingOutcome>()
        let pending = (try? context.fetch(descriptor)) ?? []

        for row in pending {
            guard row.evaluationDueAt <= today else {
                report.skippedNotYetDue += 1
                continue
            }

            let evidence = try await provider.fetchEvidence(
                for: row.actionToolName,
                payload: row.actionPayload,
                decisionDate: row.createdAt,
                evaluationDate: today
            )

            let outcomeRow = LearnedOutcome(
                decisionPrefID: evidence.linkedPreferenceID,
                decisionConvID: row.decisionConvID,
                decisionTurnIndex: row.decisionTurnIndex,
                actionToolName: row.actionToolName,
                actionSummary: evidence.actionSummary ?? row.actionToolName,
                decisionDate: row.createdAt,
                evaluationDueAt: row.evaluationDueAt,
                outcome: evidence.outcome,
                evidence: evidence.summary,
                gradedAt: today,
                userOverride: false
            )
            context.insert(outcomeRow)
            context.delete(row)

            if evidence.outcome == .unclear {
                report.unclearDueToMissingEvidence += 1
            }
            report.graded += 1
        }

        try context.save()
        return report
    }
}

// MARK: - OutcomeEvidenceProvider

/// Sendable protocol for evidence fetching. Tests inject deterministic
/// stubs; Phase 6c wiring provides a real impl that reads HealthKit +
/// SwiftData (MealLog, WorkoutPlan, DailyRecovery).
///
/// The provider returns an `Evidence` value containing the scored
/// `Outcome`, an optional human-readable summary for the LearnedOutcome
/// row, and an optional `linkedPreferenceID` (when the action was
/// driven by a specific preference — populated by CoachService at
/// dispatch time once Phase 6b ships).
protocol OutcomeEvidenceProvider: Sendable {
    func fetchEvidence(
        for toolName: String,
        payload: Data,
        decisionDate: Date,
        evaluationDate: Date
    ) async throws -> OutcomeEvidence
}

// MARK: - OutcomeEvidence

struct OutcomeEvidence: Equatable {
    let outcome: LearnedOutcome.Outcome
    let summary: String?
    let actionSummary: String?
    let linkedPreferenceID: UUID?

    init(
        outcome: LearnedOutcome.Outcome,
        summary: String? = nil,
        actionSummary: String? = nil,
        linkedPreferenceID: UUID? = nil
    ) {
        self.outcome = outcome
        self.summary = summary
        self.actionSummary = actionSummary
        self.linkedPreferenceID = linkedPreferenceID
    }

    /// Convenience for tools that grade as "did the user follow through"
    /// (e.g., did the moved meal actually get logged at the new time).
    static func followedThrough(summary: String? = nil, actionSummary: String? = nil) -> OutcomeEvidence {
        OutcomeEvidence(outcome: .followedThrough, summary: summary, actionSummary: actionSummary)
    }

    static func abandoned(summary: String? = nil, actionSummary: String? = nil) -> OutcomeEvidence {
        OutcomeEvidence(outcome: .abandoned, summary: summary, actionSummary: actionSummary)
    }

    static func unclear(actionSummary: String? = nil) -> OutcomeEvidence {
        OutcomeEvidence(outcome: .unclear, summary: nil, actionSummary: actionSummary)
    }
}
