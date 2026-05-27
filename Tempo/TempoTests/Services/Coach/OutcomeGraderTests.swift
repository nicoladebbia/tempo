//
// OutcomeGraderTests.swift
// Tempo
//
// Coach v2.1 Phase 6a — covers the PendingOutcome → LearnedOutcome
// pipeline, evaluation-window mapping, the not-yet-due skip path, and
// the unclear-evidence fall-through.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class OutcomeGraderTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LearnedOutcome.self,
            PendingOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private struct StubProvider: OutcomeEvidenceProvider {
        let evidence: OutcomeEvidence
        func fetchEvidence(
            for _: String,
            payload _: Data,
            decisionDate _: Date,
            evaluationDate _: Date
        ) async throws -> OutcomeEvidence {
            evidence
        }
    }

    // MARK: - Window mapping

    func testWindowFor_perToolMapping() {
        XCTAssertEqual(PendingOutcome.window(for: "moveMeal"), .sameDay)
        XCTAssertEqual(PendingOutcome.window(for: "swapDayType"), .next48h)
        XCTAssertEqual(PendingOutcome.window(for: "insertActivity"), .nextDay)
        XCTAssertEqual(PendingOutcome.window(for: "skipMeal"), .sameDay)
        XCTAssertEqual(PendingOutcome.window(for: "shiftBedtime"), .nextDay)
        XCTAssertNil(PendingOutcome.window(for: "swapToQuickerMeal"))
        XCTAssertNil(PendingOutcome.window(for: "askUser"))
        XCTAssertNil(PendingOutcome.window(for: "updatePreference"))
        XCTAssertNil(PendingOutcome.window(for: "recordPreference"))
    }

    func testDueDate_sameDayIsEndOfDecisionDay() {
        let calendar = Calendar(identifier: .gregorian)
        let comps = DateComponents(year: 2026, month: 5, day: 26, hour: 14)
        let decisionDate = calendar.date(from: comps)!
        let due = PendingOutcome.dueDate(from: decisionDate, window: .sameDay, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 27))!
        XCTAssertEqual(due, expected)
    }

    func testDueDate_next48hAddsTwoDaysExactly() {
        let decisionDate = Date()
        let due = PendingOutcome.dueDate(from: decisionDate, window: .next48h)
        XCTAssertEqual(due.timeIntervalSince(decisionDate), 48 * 3600, accuracy: 1)
    }

    // MARK: - run

    func testRun_skipsRowsNotYetDue() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()
        let future = now.addingTimeInterval(3600) // 1h from now
        let row = PendingOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "moveMeal",
            evaluationWindow: .sameDay,
            decisionDate: future
        )
        context.insert(row)
        try context.save()

        let report = try await OutcomeGrader.run(
            in: context,
            today: now,
            provider: StubProvider(evidence: .followedThrough(actionSummary: "x"))
        )
        XCTAssertEqual(report.graded, 0)
        XCTAssertEqual(report.skippedNotYetDue, 1)
        // Pending row not deleted.
        let stillPending = try context.fetch(FetchDescriptor<PendingOutcome>())
        XCTAssertEqual(stillPending.count, 1)
        let outcomes = try context.fetch(FetchDescriptor<LearnedOutcome>())
        XCTAssertEqual(outcomes.count, 0)
    }

    func testRun_gradesDueRowAndDeletesPending() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let yesterday = Date().addingTimeInterval(-2 * 86_400)
        let row = PendingOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 1,
            actionToolName: "moveMeal",
            actionPayload: Data(#"{"mealID":"abc"}"#.utf8),
            evaluationWindow: .sameDay,
            decisionDate: yesterday
        )
        context.insert(row)
        try context.save()

        let provider = StubProvider(
            evidence: .followedThrough(summary: "logged at new time", actionSummary: "moved lunch 12:30→13:15")
        )
        let report = try await OutcomeGrader.run(
            in: context,
            today: Date(),
            provider: provider
        )
        XCTAssertEqual(report.graded, 1)
        XCTAssertEqual(report.skippedNotYetDue, 0)

        let pending = try context.fetch(FetchDescriptor<PendingOutcome>())
        XCTAssertEqual(pending.count, 0)
        let outcomes = try context.fetch(FetchDescriptor<LearnedOutcome>())
        XCTAssertEqual(outcomes.count, 1)
        let graded = try XCTUnwrap(outcomes.first)
        XCTAssertEqual(graded.outcome, .followedThrough)
        XCTAssertEqual(graded.actionToolName, "moveMeal")
        XCTAssertEqual(graded.actionSummary, "moved lunch 12:30→13:15")
        XCTAssertNotNil(graded.gradedAt)
    }

    func testRun_unclearEvidenceStillGradesAsUnclear() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let yesterday = Date().addingTimeInterval(-2 * 86_400)
        let row = PendingOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "shiftBedtime",
            evaluationWindow: .nextDay,
            decisionDate: yesterday
        )
        context.insert(row)
        try context.save()

        let report = try await OutcomeGrader.run(
            in: context,
            today: Date(),
            provider: StubProvider(evidence: .unclear(actionSummary: "no HK sleep data"))
        )
        XCTAssertEqual(report.graded, 1)
        XCTAssertEqual(report.unclearDueToMissingEvidence, 1)
        let outcomes = try context.fetch(FetchDescriptor<LearnedOutcome>())
        let row0 = try XCTUnwrap(outcomes.first)
        XCTAssertEqual(row0.outcome, .unclear)
        XCTAssertNotNil(row0.gradedAt)
    }

    func testRun_handlesMixedDueAndNotDueRows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()
        let oldDue = PendingOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "moveMeal",
            evaluationWindow: .sameDay,
            decisionDate: now.addingTimeInterval(-3 * 86_400)
        )
        let stillFuture = PendingOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "swapDayType",
            evaluationWindow: .next48h,
            decisionDate: now.addingTimeInterval(-3600) // 1h ago, due in ~47h
        )
        context.insert(oldDue)
        context.insert(stillFuture)
        try context.save()

        let report = try await OutcomeGrader.run(
            in: context,
            today: now,
            provider: StubProvider(evidence: .followedThrough(actionSummary: "x"))
        )
        XCTAssertEqual(report.graded, 1)
        XCTAssertEqual(report.skippedNotYetDue, 1)
        let pending = try context.fetch(FetchDescriptor<PendingOutcome>())
        XCTAssertEqual(pending.count, 1, "future row remains pending")
        XCTAssertEqual(pending.first?.actionToolName, "swapDayType")
    }

    // MARK: - Carries linked preference + payload through

    func testRun_propagatesLinkedPreferenceID() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let yesterday = Date().addingTimeInterval(-2 * 86_400)
        let row = PendingOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "moveMeal",
            evaluationWindow: .sameDay,
            decisionDate: yesterday
        )
        context.insert(row)
        try context.save()

        let linkedID = UUID()
        let provider = StubProvider(
            evidence: OutcomeEvidence(
                outcome: .followedThrough,
                summary: "x",
                actionSummary: "x",
                linkedPreferenceID: linkedID
            )
        )
        _ = try await OutcomeGrader.run(in: context, today: Date(), provider: provider)
        let outcomes = try context.fetch(FetchDescriptor<LearnedOutcome>())
        XCTAssertEqual(outcomes.first?.decisionPrefID, linkedID)
    }
}
