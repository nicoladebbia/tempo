//
// CoachAnalytics.swift
// Tempo
//
// Coach v2.1 Phase 8d — typed PostHog event helpers for the Coach
// surface. Each event has a fixed property schema so dashboards stay
// stable as Coach evolves.
//
// All events route through AnalyticsService.shared.track which respects
// the user's analytics consent. Nothing is captured before consent is
// granted; see AnalyticsService.applyConsent.
//
// Per .plans/coach-v2.1/03-services-and-data-flow.md "Observability".
//

import Foundation

// MARK: - CoachAnalytics

@MainActor
enum CoachAnalytics {
    // MARK: Conversation lifecycle

    static func conversationStarted(
        conversationID: UUID,
        source: ConversationSource,
        fromTab: String? = nil
    ) {
        var props: [String: Any] = [
            "conversation_id": conversationID.uuidString,
            "source": source.rawValue,
        ]
        if let fromTab {
            props["from_tab"] = fromTab
        }
        AnalyticsService.shared.track("coach.conversation_started", properties: props)
    }

    static func messageSent(
        conversationID: UUID,
        role: String,
        modelUsed: String?,
        hasToolCalls: Bool,
        turnCountSoFar: Int
    ) {
        AnalyticsService.shared.track(
            "coach.message_sent",
            properties: [
                "conversation_id": conversationID.uuidString,
                "role": role,
                "model_used": modelUsed ?? "none",
                "has_tool_calls": hasToolCalls,
                "turn_count": turnCountSoFar,
            ]
        )
    }

    // MARK: Tool dispatch

    static func toolCalled(
        toolName: String,
        success: Bool,
        durationMs: Int? = nil
    ) {
        var props: [String: Any] = [
            "tool_name": toolName,
            "success": success,
        ]
        if let durationMs {
            props["duration_ms"] = durationMs
        }
        AnalyticsService.shared.track("coach.tool_called", properties: props)
    }

    static func toolError(toolName: String, errorType: String) {
        AnalyticsService.shared.track(
            "coach.tool_error",
            properties: [
                "tool_name": toolName,
                "error_type": errorType,
            ]
        )
    }

    static func undoUsed(toolName: String) {
        AnalyticsService.shared.track(
            "coach.undo_used",
            properties: ["tool_name": toolName]
        )
    }

    // MARK: Caps + budget

    static func capReached(_ cap: CapType) {
        AnalyticsService.shared.track(
            "coach.cap_reached",
            properties: ["cap_type": cap.rawValue]
        )
    }

    static func budgetSubCapExhausted() {
        AnalyticsService.shared.track("coach.budget_subcap_exhausted")
    }

    // MARK: Memory layer

    static func preferenceExtracted(
        source: String,
        subject: String,
        polarity: String
    ) {
        AnalyticsService.shared.track(
            "coach.preference_extracted",
            properties: [
                "source": source,
                "subject": subject,
                "polarity": polarity,
            ]
        )
    }

    // MARK: Outcomes

    static func outcomeGraded(
        actionToolName: String,
        outcome: String,
        daysFromDecision: Int
    ) {
        AnalyticsService.shared.track(
            "coach.outcome_graded",
            properties: [
                "action_tool": actionToolName,
                "outcome": outcome,
                "days_from_decision": daysFromDecision,
            ]
        )
    }
}

// MARK: - Enums

extension CoachAnalytics {
    enum ConversationSource: String, Sendable {
        case tab
        case inlinePill = "inline_pill"
    }

    enum CapType: String, Sendable {
        case turns
        case toolCalls = "tool_calls"
        case budget
    }
}
