//
// TrainerProgramWeeklyUploadTests.swift
// Tempo
//
// Weekly-upload feature — pins the Sunday-19:00/Monday-08:00 deadline math,
// the "is it due" persistence across stale weeks, upcoming-week coverage, and
// the Mon–Fri-vs-Sat/Sun upload-timing decision. Every date here is an
// injected fixture, never the real wall clock (CLAUDE.md — we already had
// date/time-of-day-dependent test failures twice this week).
//

@testable import Tempo
import XCTest

final class TrainerProgramWeeklyUploadTests: XCTestCase {
    /// 2026-09-21 is a real, fixed Monday; 09-27 the Sunday that ends its
    /// week; 09-28 the following Monday.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        components.calendar = .current
        return components.date!
    }

    private func weeklyProgram(startDate: Date) -> TrainerProgram {
        TrainerProgram(
            name: "Coach",
            startDate: startDate,
            weeks: [ProgramWeek(days: [])],
            repeats: true,
            sourceKind: "text",
            cadence: .weekly
        )
    }

    private func blockProgram(startDate: Date, weeks: Int = 4) -> TrainerProgram {
        TrainerProgram(
            name: "Coach",
            startDate: startDate,
            weeks: (0 ..< weeks).map { _ in ProgramWeek(days: []) },
            repeats: false,
            sourceKind: "text",
            cadence: .block
        )
    }

    // MARK: - Deadline math

    func testSundayDeadlineIsNineteenHundredOnTheWeeksSunday() {
        let monday = date(2026, 9, 21)
        let deadline = TrainerProgramWeeklyUpload.sundayDeadline(afterWeekStarting: monday)
        XCTAssertEqual(deadline, date(2026, 9, 27, hour: 19))
    }

    func testMondayNudgeIsEightHundredTheFollowingMonday() {
        let monday = date(2026, 9, 21)
        let nudge = TrainerProgramWeeklyUpload.mondayNudge(afterWeekStarting: monday)
        XCTAssertEqual(nudge, date(2026, 9, 28, hour: 8))
    }

    // MARK: - effectiveWeekMonday — rolls forward once stale

    func testEffectiveWeekMondayMatchesServedWeekWhenFresh() {
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertEqual(
            TrainerProgramWeeklyUpload.effectiveWeekMonday(for: program, now: date(2026, 9, 23)),
            date(2026, 9, 21)
        )
    }

    func testEffectiveWeekMondayRollsForwardOnceStale() {
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertEqual(
            TrainerProgramWeeklyUpload.effectiveWeekMonday(for: program, now: date(2026, 10, 15)),
            date(2026, 10, 12),
            "three weeks stale — rolls forward to NOW's own week, not the original served week"
        )
    }

    // MARK: - isDue — the Sunday 18:59/19:00 boundary

    func testNotDueBeforeSundayDeadline() {
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertFalse(TrainerProgramWeeklyUpload.isDue(activeProgram: program, now: date(2026, 9, 27, hour: 18, minute: 59)))
    }

    func testDueExactlyAtSundayDeadline() {
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertTrue(TrainerProgramWeeklyUpload.isDue(activeProgram: program, now: date(2026, 9, 27, hour: 19)))
    }

    func testStaysDueManyWeeksLaterWithNothingUploaded() {
        // The program was due weeks ago and nothing new landed — the
        // fallback keeps repeating, but the card/reminders must not reset.
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertTrue(TrainerProgramWeeklyUpload.isDue(activeProgram: program, now: date(2026, 10, 19)))
    }

    func testBlockCadenceIsNeverDue() {
        let program = blockProgram(startDate: date(2026, 9, 21))
        XCTAssertFalse(TrainerProgramWeeklyUpload.isDue(activeProgram: program, now: date(2026, 12, 1)))
    }

    // MARK: - isUpcomingWeekCovered

    func testUpcomingWeekNotCoveredByDefault() {
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertFalse(
            TrainerProgramWeeklyUpload.isUpcomingWeekCovered(programs: [program], activeProgram: program, now: date(2026, 9, 23))
        )
    }

    func testUpcomingWeekCoveredByAQueuedProgram() {
        let active = weeklyProgram(startDate: date(2026, 9, 21))
        let queued = TrainerProgram(
            name: "Coach", startDate: date(2026, 9, 28), weeks: [ProgramWeek(days: [])],
            isActive: false, sourceKind: "text", queuedActivationDate: date(2026, 9, 28), cadence: .weekly
        )
        XCTAssertTrue(
            TrainerProgramWeeklyUpload.isUpcomingWeekCovered(
                programs: [active, queued], activeProgram: active, now: date(2026, 9, 23)
            )
        )
    }

    /// Regression — once `active` is weeks stale, a legitimate NEW upload's
    /// own `startDate` is computed off the REAL current week (`uploadTiming`
    /// uses `now`, not the stale program), not off `active`'s long-past
    /// served week. `isUpcomingWeekCovered` must measure against `now`'s
    /// week, or it would never recognize such an upload as covering anything.
    func testUpcomingWeekCoveredMeasuresFromNowNotTheStaleServedWeek() {
        // Active program served week 09-21, but "now" is three weeks later.
        let staleActive = weeklyProgram(startDate: date(2026, 9, 21))
        let freshlyQueued = TrainerProgram(
            name: "Coach", startDate: date(2026, 10, 19), weeks: [ProgramWeek(days: [])],
            isActive: false, sourceKind: "text", queuedActivationDate: date(2026, 10, 19), cadence: .weekly
        )
        XCTAssertTrue(
            TrainerProgramWeeklyUpload.isUpcomingWeekCovered(
                programs: [staleActive, freshlyQueued], activeProgram: staleActive, now: date(2026, 10, 15)
            ),
            "a program queued for next week (relative to NOW) must count as covering, however stale the active one is"
        )
    }

    // MARK: - shouldPromptUpload — the single check the card/reminders share

    func testPromptsWhenDueAndUncovered() {
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertTrue(
            TrainerProgramWeeklyUpload.shouldPromptUpload(programs: [program], activeProgram: program, now: date(2026, 9, 27, hour: 19))
        )
    }

    func testNoPromptOnceTheWeekAlreadyUploaded() {
        let active = weeklyProgram(startDate: date(2026, 9, 21))
        let queued = TrainerProgram(
            name: "Coach", startDate: date(2026, 9, 28), weeks: [ProgramWeek(days: [])],
            isActive: false, sourceKind: "text", queuedActivationDate: date(2026, 9, 28), cadence: .weekly
        )
        XCTAssertFalse(
            TrainerProgramWeeklyUpload.shouldPromptUpload(
                programs: [active, queued], activeProgram: active, now: date(2026, 9, 27, hour: 20)
            )
        )
    }

    func testNoPromptBeforeDeadlineEvenIfUncovered() {
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        XCTAssertFalse(
            TrainerProgramWeeklyUpload.shouldPromptUpload(programs: [program], activeProgram: program, now: date(2026, 9, 24))
        )
    }

    // MARK: - Review-screen auto start/queue decision (fix #5)

    func testWeekdayUploadStartsThisMondayAndActivatesNow() {
        // Wednesday upload.
        let timing = TrainerProgramWeeklyUpload.uploadTiming(forUploadOn: date(2026, 9, 23))
        XCTAssertEqual(timing.startDate, date(2026, 9, 21))
        XCTAssertFalse(timing.isQueued)
        XCTAssertNil(timing.queuedActivationDate)
    }

    func testSaturdayUploadQueuesForNextMonday() {
        let timing = TrainerProgramWeeklyUpload.uploadTiming(forUploadOn: date(2026, 9, 26))
        XCTAssertEqual(timing.startDate, date(2026, 9, 28))
        XCTAssertTrue(timing.isQueued)
        XCTAssertEqual(timing.queuedActivationDate, date(2026, 9, 28))
    }

    func testSundayUploadQueuesForNextMonday() {
        let timing = TrainerProgramWeeklyUpload.uploadTiming(forUploadOn: date(2026, 9, 27))
        XCTAssertEqual(timing.startDate, date(2026, 9, 28))
        XCTAssertTrue(timing.isQueued)
    }

    func testFridayUploadStartsThisMondayAndActivatesNow() {
        let timing = TrainerProgramWeeklyUpload.uploadTiming(forUploadOn: date(2026, 9, 25))
        XCTAssertEqual(timing.startDate, date(2026, 9, 21))
        XCTAssertFalse(timing.isQueued)
    }
}
