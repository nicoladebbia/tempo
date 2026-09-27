//
// TrainingPauseScheduleTests.swift
// Tempo
//
// Pause/travel-pain feature — pins the pure overlay/coverage rules
// `TrainingPauseSchedule` uses at both `applyTrainerProgram`-sibling call
// sites, plus the "covers the whole week" gate the weekly-upload nudge reads
// and the fixed-mode resume-shift math.
//

@testable import Tempo
import XCTest

// MARK: - TrainingPauseScheduleTests

final class TrainingPauseScheduleTests: XCTestCase {
    private let cal = TrainingCalendar.iso8601

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!
    }

    private func pause(
        reason: PauseReason = .sick,
        start: String,
        end: String? = nil,
        resumedAt: String? = nil,
        createdAt: String? = nil
    ) -> TrainingPause {
        TrainingPause(
            reason: reason,
            startDate: date(start),
            plannedEndDate: end.map(date),
            createdAt: createdAt.map(date) ?? date(start)
        ).with { p in
            p.resumedAt = resumedAt.map(date)
        }
    }

    // MARK: - coveringPause

    func testCoveringPause_withinRange() {
        let p = pause(start: "2026-09-22", end: "2026-09-24")
        XCTAssertNotNil(TrainingPauseSchedule.coveringPause([p], on: date("2026-09-23"), calendar: cal))
        XCTAssertNil(TrainingPauseSchedule.coveringPause([p], on: date("2026-09-21"), calendar: cal), "before start")
        XCTAssertNil(TrainingPauseSchedule.coveringPause([p], on: date("2026-09-25"), calendar: cal), "after end")
    }

    func testCoveringPause_openEndedUntilResumed() {
        let p = pause(start: "2026-09-22")
        XCTAssertNotNil(
            TrainingPauseSchedule.coveringPause([p], on: date("2026-10-30"), calendar: cal),
            "no end — still covers a month later"
        )
    }

    func testCoveringPause_resumedEndsCoverageFromThatDay() {
        let p = pause(start: "2026-09-22", resumedAt: "2026-09-24")
        XCTAssertNotNil(TrainingPauseSchedule.coveringPause([p], on: date("2026-09-23"), calendar: cal))
        XCTAssertNil(
            TrainingPauseSchedule.coveringPause([p], on: date("2026-09-24"), calendar: cal),
            "resume day itself is no longer paused"
        )
    }

    func testCoveringPause_mostRecentlyCreatedWinsOnOverlap() {
        let older = pause(start: "2026-09-22", end: "2026-09-28", createdAt: "2026-09-22")
        let newer = pause(reason: .travel, start: "2026-09-22", end: "2026-09-28", createdAt: "2026-09-23")
        let winner = TrainingPauseSchedule.coveringPause([older, newer], on: date("2026-09-23"), calendar: cal)
        XCTAssertEqual(winner?.reason, .travel)
    }

    // MARK: - apply

    func testApply_forcesRestAndClearsTrainerKeys() {
        let plan = WorkoutPlan(date: date("2026-09-23"), type: .push)
        plan.programSessionKey = "abc#0#d0"
        plan.secondarySessionType = .run
        let p = pause(start: "2026-09-22", end: "2026-09-24")
        TrainingPauseSchedule.apply([p], to: [plan], calendar: cal)
        XCTAssertEqual(plan.type, .rest)
        XCTAssertNil(plan.programSessionKey)
        XCTAssertNil(plan.secondarySessionType)
        XCTAssertEqual(plan.pauseReason, .sick)
    }

    func testApply_neverOverridesFootballOrNonPlannedDays() {
        let footballPlan = WorkoutPlan(date: date("2026-09-23"), type: .football)
        let completedPlan = WorkoutPlan(date: date("2026-09-23"), type: .push, status: .completed)
        let p = pause(start: "2026-09-22", end: "2026-09-24")
        TrainingPauseSchedule.apply([p], to: [footballPlan, completedPlan], calendar: cal)
        XCTAssertEqual(footballPlan.type, .football, "a match/football day is a fixed commitment, unaffected by pause")
        XCTAssertEqual(completedPlan.type, .push, "a completed session is sacred, never overwritten")
    }

    func testApply_noOpOutsideCoverage() {
        let plan = WorkoutPlan(date: date("2026-09-30"), type: .push)
        let p = pause(start: "2026-09-22", end: "2026-09-24")
        TrainingPauseSchedule.apply([p], to: [plan], calendar: cal)
        XCTAssertEqual(plan.type, .push)
    }

    // MARK: - pausesCoverWholeWeek

    func testPausesCoverWholeWeek_true() {
        let monday = date("2026-09-21")
        let p = pause(start: "2026-09-21", end: "2026-09-27")
        XCTAssertTrue(TrainingPauseSchedule.pausesCoverWholeWeek(pauses: [p], weekMonday: monday, calendar: cal))
    }

    func testPausesCoverWholeWeek_falseWithOneGapDay() {
        let monday = date("2026-09-21")
        let p = pause(start: "2026-09-21", end: "2026-09-26") // misses Sunday
        XCTAssertFalse(TrainingPauseSchedule.pausesCoverWholeWeek(pauses: [p], weekMonday: monday, calendar: cal))
    }

    func testPausesCoverWholeWeek_falseWithNoPauses() {
        XCTAssertFalse(TrainingPauseSchedule.pausesCoverWholeWeek(pauses: [], weekMonday: date("2026-09-21"), calendar: cal))
    }

    // MARK: - Resume math (fixed-mode shift)

    func testPausedDayCount() {
        let p = pause(start: "2026-09-22")
        XCTAssertEqual(TrainingPauseSchedule.pausedDayCount(p, resumeDay: date("2026-09-25"), calendar: cal), 3)
    }

    func testShiftedStartDate_pushesForwardByPausedDays() {
        let program = TrainerProgram(name: "PT", startDate: date("2026-09-07"), weeks: [ProgramWeek(days: [])], sourceKind: "text")
        let shifted = TrainingPauseSchedule.shiftedStartDate(for: program, pausedDays: 3, calendar: cal)
        XCTAssertEqual(shifted, date("2026-09-10"))
    }
}

private extension TrainingPause {
    /// Test-only convenience so a fixture can set a field the designated
    /// init doesn't expose (`resumedAt`), without cluttering the init.
    func with(_ configure: (TrainingPause) -> Void) -> TrainingPause {
        configure(self)
        return self
    }
}
