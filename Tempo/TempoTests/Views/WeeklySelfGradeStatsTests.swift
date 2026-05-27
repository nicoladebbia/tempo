//
// WeeklySelfGradeStatsTests.swift
// Tempo
//
// Coach v2.1 Phase 8c — covers the self-grade math used by
// WeeklySelfGradeCard. Visual rendering is verified by build-green
// + the morning manual-QA pass.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WeeklySelfGradeStatsTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LearnedOutcome.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeOutcome(
        outcome: LearnedOutcome.Outcome,
        daysAgo: Int = 1,
        userOverride: Bool = false,
        graded: Bool = true
    ) -> LearnedOutcome {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return LearnedOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "moveMeal",
            actionSummary: "x",
            decisionDate: date,
            evaluationDueAt: date,
            outcome: outcome,
            gradedAt: graded ? date : nil,
            userOverride: userOverride
        )
    }

    // MARK: - Empty

    func testStats_emptyOutcomes_isEmpty() {
        let stats = WeeklySelfGradeStats.compute(outcomes: [])
        XCTAssertTrue(stats.isEmpty)
        XCTAssertEqual(stats.suggestionsMade, 0)
    }

    func testStats_onlyUngradedOutcomes_isEmpty() {
        // gradedAt nil → filtered out.
        let stats = WeeklySelfGradeStats.compute(outcomes: [
            makeOutcome(outcome: .goodSleep, graded: false),
        ])
        XCTAssertTrue(stats.isEmpty)
    }

    // MARK: - Counting

    func testStats_countsByOutcome() {
        let outcomes = [
            makeOutcome(outcome: .goodSleep),
            makeOutcome(outcome: .goodWorkout),
            makeOutcome(outcome: .followedThrough),
            makeOutcome(outcome: .badSleep),
            makeOutcome(outcome: .abandoned),
            makeOutcome(outcome: .unclear),
        ]
        let stats = WeeklySelfGradeStats.compute(outcomes: outcomes)
        XCTAssertEqual(stats.suggestionsMade, 6)
        // Taken = everything except abandoned → 5.
        XCTAssertEqual(stats.takenCount, 5)
        // Worked well = goodSleep + goodWorkout + followedThrough = 3.
        XCTAssertEqual(stats.workedWellCount, 3)
        // Regretted = badSleep + abandoned = 2.
        XCTAssertEqual(stats.regrettedCount, 2)
    }

    func testStats_userOverrideForcesRegretted() {
        let outcomes = [
            // Outcome says goodSleep but user flagged regret.
            makeOutcome(outcome: .goodSleep, userOverride: true),
        ]
        let stats = WeeklySelfGradeStats.compute(outcomes: outcomes)
        XCTAssertEqual(stats.regrettedCount, 1, "userOverride must count as regretted")
        XCTAssertEqual(stats.workedWellCount, 0)
    }

    func testStats_acceptanceRateMath() {
        let outcomes = [
            makeOutcome(outcome: .followedThrough),
            makeOutcome(outcome: .followedThrough),
            makeOutcome(outcome: .abandoned),
            makeOutcome(outcome: .unclear),
        ]
        let stats = WeeklySelfGradeStats.compute(outcomes: outcomes)
        XCTAssertEqual(stats.takenCount, 3)
        XCTAssertEqual(stats.acceptanceRate, 0.75, accuracy: 0.001)
    }

    // MARK: - Window filtering

    func testStats_excludesOutcomesOutsideWindow() {
        let outcomes = [
            makeOutcome(outcome: .followedThrough, daysAgo: 30), // outside default 7d
            makeOutcome(outcome: .followedThrough, daysAgo: 3),  // inside
        ]
        let stats = WeeklySelfGradeStats.compute(outcomes: outcomes)
        XCTAssertEqual(stats.suggestionsMade, 1)
    }

    func testStats_customWindow() {
        let outcomes = [
            makeOutcome(outcome: .followedThrough, daysAgo: 25),
            makeOutcome(outcome: .followedThrough, daysAgo: 3),
        ]
        let stats = WeeklySelfGradeStats.compute(outcomes: outcomes, windowDays: 30)
        XCTAssertEqual(stats.suggestionsMade, 2)
    }

    // MARK: - Summary line

    func testStats_summaryLine_pluralization() {
        let stats1 = WeeklySelfGradeStats(suggestionsMade: 1, takenCount: 1, workedWellCount: 1, regrettedCount: 0)
        XCTAssertTrue(stats1.summaryLine.contains("1 suggestion,"))

        let statsN = WeeklySelfGradeStats(suggestionsMade: 3, takenCount: 2, workedWellCount: 2, regrettedCount: 0)
        XCTAssertTrue(statsN.summaryLine.contains("3 suggestions,"))
    }

    // MARK: - WeeklyConfidenceAdjustment.delta

    func testConfidenceAdjustment_deltaSign() {
        let down = WeeklyConfidenceAdjustment(
            id: UUID(), subject: "x", oldConfidence: 0.8, newConfidence: 0.7
        )
        let up = WeeklyConfidenceAdjustment(
            id: UUID(), subject: "x", oldConfidence: 0.5, newConfidence: 0.6
        )
        XCTAssertLessThan(down.delta, 0)
        XCTAssertGreaterThan(up.delta, 0)
    }
}
