//
// TrainerProgramDurationTextTests.swift
// Tempo
//
// Pins the exact duration copy shown on TrainerProgramView's active card and
// TrainerProgramHistoryView's rows for a block (mid-run, finished, repeating)
// and a weekly program.
//

@testable import Tempo
import XCTest

final class TrainerProgramDurationTextTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents(year: year, month: month, day: day)
        components.calendar = .current
        return components.date!
    }

    // MARK: - Block

    func testNonRepeatingBlockMidRun() {
        // 2026-09-21 is a Monday; a 4-week block started there ends
        // 2026-10-18 (Sunday).
        let program = TrainerProgram(
            name: "Coach",
            startDate: date(2026, 9, 21),
            weeks: (0 ..< 4).map { _ in ProgramWeek(days: []) },
            repeats: false,
            sourceKind: "text",
            cadence: .block
        )
        let summary = TrainerProgramDurationText.summary(for: program, now: date(2026, 9, 30))
        XCTAssertEqual(summary, "Week 2 of 4 · ends Sun 18 Oct")
    }

    func testRepeatingBlockNamesItsLengthInsteadOfAWeekNumber() {
        let program = TrainerProgram(
            name: "Coach",
            startDate: date(2026, 9, 21),
            weeks: (0 ..< 4).map { _ in ProgramWeek(days: []) },
            repeats: true,
            sourceKind: "text",
            cadence: .block
        )
        let summary = TrainerProgramDurationText.summary(for: program, now: date(2026, 9, 30))
        XCTAssertEqual(summary, "4-week block · repeats")
    }

    func testFinishedNonRepeatingBlock() {
        let program = TrainerProgram(
            name: "Coach",
            startDate: date(2026, 9, 21),
            weeks: (0 ..< 4).map { _ in ProgramWeek(days: []) },
            repeats: false,
            sourceKind: "text",
            cadence: .block
        )
        let summary = TrainerProgramDurationText.summary(for: program, now: date(2026, 12, 1))
        XCTAssertEqual(summary, "This block has finished.")
    }

    // MARK: - Weekly

    func testWeeklyProgramSummary() {
        // Served week starts Monday 2026-09-21, ends Sunday 2026-09-27.
        let program = TrainerProgram(
            name: "Coach",
            startDate: date(2026, 9, 21),
            weeks: [ProgramWeek(days: [])],
            repeats: true,
            sourceKind: "text",
            cadence: .weekly
        )
        let summary = TrainerProgramDurationText.summary(for: program, now: date(2026, 9, 23))
        XCTAssertEqual(summary, "Weekly program · this week ends Sun 27 Sep · next week's upload due Sunday")
    }

    /// Regression — once overdue, the summary must roll forward to `now`'s
    /// own week's Sunday instead of freezing on a Sunday that's already
    /// passed (which read as broken).
    func testWeeklyProgramSummaryRollsForwardOnceOverdue() {
        let program = TrainerProgram(
            name: "Coach",
            startDate: date(2026, 9, 21),
            weeks: [ProgramWeek(days: [])],
            repeats: true,
            sourceKind: "text",
            cadence: .weekly
        )
        // Three weeks stale — "now" is in the week of 2026-10-12.
        let summary = TrainerProgramDurationText.summary(for: program, now: date(2026, 10, 15))
        XCTAssertEqual(summary, "Weekly program · this week ends Sun 18 Oct · next week's upload due Sunday")
    }

    // MARK: - History rows

    func testHistoryTextForAFinishedBlock() {
        let program = TrainerProgram(
            name: "Coach",
            startDate: date(2026, 9, 21),
            weeks: (0 ..< 4).map { _ in ProgramWeek(days: []) },
            repeats: false,
            sourceKind: "text",
            cadence: .block
        )
        XCTAssertEqual(TrainerProgramDurationText.historyText(for: program), "Block · Mon 21 Sep – Sun 18 Oct")
    }

    func testHistoryTextForAWeeklyProgram() {
        let program = TrainerProgram(
            name: "Coach",
            startDate: date(2026, 9, 21),
            weeks: [ProgramWeek(days: [])],
            repeats: true,
            sourceKind: "text",
            cadence: .weekly
        )
        XCTAssertEqual(TrainerProgramDurationText.historyText(for: program), "Weekly · week of Mon 21 Sep – Sun 27 Sep")
    }
}
