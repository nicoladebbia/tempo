//
// PendingOutcome.swift
// Tempo
//
// Coach v2.1 Phase 6a — outcome-grading queue.
//
// One row per Coach action that the OutcomeGrader hasn't evaluated yet.
// Created at tool-dispatch time inside CoachService (Phase 6b); deleted
// after the grader produces a LearnedOutcome row.
//
// Per .plans/coach-v2.1/02-data-model.md "Model 3 — PendingOutcome".
//

import Foundation
import SwiftData

// MARK: - PendingOutcome

@Model
final class PendingOutcome {
    @Attribute(.unique)
    var id: UUID

    /// Conversation reference for traceability.
    var decisionConvID: UUID

    /// Turn index within the conversation (0-indexed).
    var decisionTurnIndex: Int

    /// Tool that fired ("moveMeal", "swapDayType", etc).
    var actionToolName: String

    /// Snapshot of the tool's input args as JSON. Grader uses this for
    /// context when fetching evidence (e.g., which mealID was moved).
    var actionPayload: Data

    /// Stored raw value of `EvaluationWindow`. Access via the typed
    /// `evaluationWindow` accessor.
    var evaluationWindowRaw: String

    /// Concrete due date (decisionDate + window). Grader pulls rows where
    /// this is <= now.
    var evaluationDueAt: Date

    /// When the tool fired.
    var createdAt: Date

    // MARK: - Computed

    var evaluationWindow: EvaluationWindow {
        get { EvaluationWindow(rawValue: evaluationWindowRaw) ?? .sameDay }
        set { evaluationWindowRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        decisionConvID: UUID,
        decisionTurnIndex: Int,
        actionToolName: String,
        actionPayload: Data = Data(),
        evaluationWindow: EvaluationWindow,
        decisionDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.id = id
        self.decisionConvID = decisionConvID
        self.decisionTurnIndex = decisionTurnIndex
        self.actionToolName = actionToolName
        self.actionPayload = actionPayload
        self.evaluationWindowRaw = evaluationWindow.rawValue
        self.evaluationDueAt = Self.dueDate(
            from: decisionDate,
            window: evaluationWindow,
            calendar: calendar
        )
        self.createdAt = decisionDate
    }

    // MARK: - Window resolution

    /// Maps a window enum onto a concrete future Date.
    static func dueDate(
        from decisionDate: Date,
        window: EvaluationWindow,
        calendar: Calendar = .current
    ) -> Date {
        let startOfDecisionDay = calendar.startOfDay(for: decisionDate)
        switch window {
        case .sameDay:
            // End-of-day for the decision day.
            return calendar.date(byAdding: .day, value: 1, to: startOfDecisionDay) ?? decisionDate
        case .nextDay:
            // End of the following day.
            return calendar.date(byAdding: .day, value: 2, to: startOfDecisionDay) ?? decisionDate
        case .next48h:
            return decisionDate.addingTimeInterval(48 * 3600)
        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: startOfDecisionDay) ?? decisionDate
        }
    }
}

// MARK: - EvaluationWindow

extension PendingOutcome {
    /// Per-tool grading windows. Mapping from action→window lives in
    /// PendingOutcome.window(for:) so CoachService can call a single
    /// helper at dispatch time.
    enum EvaluationWindow: String, Codable, CaseIterable, Sendable {
        case sameDay
        case nextDay
        case next48h
        case nextWeek
    }

    /// Per the v2.1 plan §"Per tool" table + Q6 decision (48h for
    /// training swaps). Returns nil for tools that don't generate
    /// PendingOutcome rows (`swapToQuickerMeal`, `askUser`,
    /// `updatePreference`, `recordPreference`).
    static func window(for actionToolName: String) -> EvaluationWindow? {
        switch actionToolName {
        case "moveMeal": return .sameDay
        case "swapDayType": return .next48h
        case "insertActivity": return .nextDay
        case "skipMeal": return .sameDay
        case "shiftBedtime": return .nextDay
        default: return nil
        }
    }
}
