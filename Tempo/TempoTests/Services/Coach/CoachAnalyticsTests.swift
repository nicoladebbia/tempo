//
// CoachAnalyticsTests.swift
// Tempo
//
// Coach v2.1 Phase 8d — verifies the typed analytics helpers have the
// expected enum raw values + that the helper methods compile end-to-end.
// PostHog dispatch itself goes through AnalyticsService.shared.track,
// which respects user consent and is exercised by the existing analytics
// integration tests. We don't double-test that here.
//

@testable import Tempo
import XCTest

@MainActor
final class CoachAnalyticsTests: XCTestCase {
    // MARK: - ConversationSource

    func testConversationSource_rawValues() {
        XCTAssertEqual(CoachAnalytics.ConversationSource.tab.rawValue, "tab")
        XCTAssertEqual(CoachAnalytics.ConversationSource.inlinePill.rawValue, "inline_pill")
    }

    // MARK: - CapType

    func testCapType_rawValues() {
        XCTAssertEqual(CoachAnalytics.CapType.turns.rawValue, "turns")
        XCTAssertEqual(CoachAnalytics.CapType.toolCalls.rawValue, "tool_calls")
        XCTAssertEqual(CoachAnalytics.CapType.budget.rawValue, "budget")
    }

    // MARK: - CorrectionAction

    func testCorrectionAction_rawValues() {
        XCTAssertEqual(CoachAnalytics.CorrectionAction.edit.rawValue, "edit")
        XCTAssertEqual(CoachAnalytics.CorrectionAction.delete.rawValue, "delete")
        XCTAssertEqual(CoachAnalytics.CorrectionAction.verify.rawValue, "verify")
    }

    // MARK: - Helper compilation

    /// Tests that every helper method compiles and accepts its
    /// declared argument types. PostHog dispatch is mocked at runtime
    /// (consent gates prevent capture in test envs), so these calls
    /// are no-ops; we're verifying the call shape.
    func testHelpers_compileAndDispatch() {
        let convID = UUID()
        let prefID = UUID()
        CoachAnalytics.conversationStarted(conversationID: convID, source: .tab)
        CoachAnalytics.conversationStarted(
            conversationID: convID,
            source: .inlinePill,
            fromTab: "training"
        )
        CoachAnalytics.messageSent(
            conversationID: convID,
            role: "user",
            modelUsed: "haiku",
            hasToolCalls: false,
            turnCountSoFar: 1
        )
        CoachAnalytics.toolCalled(toolName: "moveMeal", success: true, durationMs: 42)
        CoachAnalytics.toolError(toolName: "moveMeal", errorType: "mealNotFound")
        CoachAnalytics.undoUsed(toolName: "moveMeal")
        CoachAnalytics.capReached(.turns)
        CoachAnalytics.budgetSubCapExhausted()
        CoachAnalytics.preferenceExtracted(
            source: "explicit",
            subject: "meal_timing.breakfast.skipped",
            polarity: "positive"
        )
        CoachAnalytics.preferenceCorrectedByUser(prefID: prefID, action: .edit)
        CoachAnalytics.outcomeGraded(
            actionToolName: "moveMeal",
            outcome: "followedThrough",
            daysFromDecision: 1
        )
        CoachAnalytics.selfGradeDismissed(weekISO: "2026-W22")
        CoachAnalytics.interviewCompleted(skipped: false, questionsAnswered: 4)
        CoachAnalytics.inlinePillTapped(source: .training)
        // No assertions — reaching this point IS the test.
    }
}
