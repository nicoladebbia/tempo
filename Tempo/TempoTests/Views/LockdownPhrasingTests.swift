//
// LockdownPhrasingTests.swift
// Tempo
//
// The words and pace maths of the Lockdown page: no "Less than 0m", no
// finish time promised from nothing, no 7/7 days after two days.
//

@testable import Tempo
import XCTest

final class LockdownPhrasingTests: XCTestCase {
    // MARK: - PS5 countdown

    func testLessThanNeverSaysZeroMinutes() {
        XCTAssertEqual(PS5Countdown.lessThan(0), "PS5 time has passed.")
        XCTAssertEqual(PS5Countdown.lessThan(-30), "PS5 time has passed.")
        XCTAssertEqual(PS5Countdown.lessThan(40), "Less than a minute until PS5 time.")
    }

    func testLessThanRoundsMinutesUpSoItStaysTrue() {
        // 11m 30s left is less than 12m, not less than 11m.
        XCTAssertEqual(PS5Countdown.lessThan(11 * 60 + 30), "Less than 12m until PS5 time.")
        XCTAssertEqual(PS5Countdown.lessThan(60), "Less than 1m until PS5 time.")
    }

    func testOnlyLine() {
        XCTAssertEqual(PS5Countdown.only(0), "PS5 time has passed.")
        XCTAssertEqual(PS5Countdown.only(30), "Under a minute until PS5 time.")
        XCTAssertEqual(PS5Countdown.only(25 * 60), "Only 25m until PS5 time.")
    }

    func testRemainingNeedsAWholeMinute() {
        XCTAssertNil(PS5Countdown.remaining(0))
        XCTAssertNil(PS5Countdown.remaining(59))
        XCTAssertEqual(PS5Countdown.remaining(60), "1m")
        XCTAssertEqual(PS5Countdown.remaining(65 * 60), "1h 5m")
    }

    func testStatusLineAtEachStage() {
        XCTAssertEqual(PS5Countdown.statusLine(seconds: 0), "PS5 time is here. Handle your business.")
        XCTAssertEqual(PS5Countdown.statusLine(seconds: 20), "Under a minute. Move.")
        XCTAssertEqual(PS5Countdown.statusLine(seconds: 10 * 60), "10m. Move.")
        XCTAssertEqual(PS5Countdown.statusLine(seconds: 45 * 60), "45m. Clock's ticking.")
        XCTAssertEqual(PS5Countdown.statusLine(seconds: 90 * 60), "1h 30m left. Focus up.")
        XCTAssertEqual(PS5Countdown.statusLine(seconds: 5 * 3600), "5h 0m until your usual PS5 time")
    }

    // MARK: - Pace

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(
        done: Int, total: Int, left: TimeInterval, study: Double = 0
    ) -> LockdownPace.Reading? {
        LockdownPace.reading(
            done: done, total: total, timeToPS5: left, studyMinutesRemaining: study, now: now
        )
    }

    func testNothingDoneGivesNoFinishTime() {
        // Midday, nothing done: there is no pace to read, so no "on pace" claim.
        XCTAssertNil(reading(done: 0, total: 4, left: 6 * 3600))
    }

    func testBeforeTheDayStartsGivesNoFinishTime() {
        // More time left than the working day: one task done early says nothing.
        XCTAssertNil(reading(done: 1, total: 4, left: LockdownPace.activeDay + 3600))
        XCTAssertNil(reading(done: 1, total: 4, left: LockdownPace.activeDay - 60))
    }

    func testOnPaceFinishIsInTheFuture() throws {
        // 6h elapsed, 2 of 4 done: 3h per task, 2 left needs 6h, 5.5h left: too slow.
        XCTAssertEqual(reading(done: 2, total: 4, left: 5.5 * 3600), .wontFinish)

        // 6h elapsed, 3 of 4 done: 2h per task, 1 left needs 2h, 5.5h left: fine.
        let result = try XCTUnwrap(reading(done: 3, total: 4, left: 5.5 * 3600))
        guard case let .onPace(finish, ahead) = result else {
            return XCTFail("expected onPace, got \(result)")
        }
        XCTAssertEqual(finish.timeIntervalSince(now), 2 * 3600, accuracy: 1)
        XCTAssertTrue(ahead)
        XCTAssertTrue(result.onTrack)
    }

    func testOnPaceButNotAheadWhenItUsesMostOfTheTimeLeft() throws {
        // 8h elapsed, 2 of 4 done: 4h per task, 2 left needs 8h; 3.5h left: too slow.
        XCTAssertEqual(reading(done: 2, total: 4, left: 3.5 * 3600), .wontFinish)
        // 8h elapsed, 3 of 4 done: 2.67h per task, needs 2.67h of 3.5h left: on pace, not ahead.
        let result = try XCTUnwrap(reading(done: 3, total: 4, left: 3.5 * 3600))
        guard case let .onPace(_, ahead) = result else {
            return XCTFail("expected onPace, got \(result)")
        }
        XCTAssertFalse(ahead)
    }

    func testPassedWithTasksOpen() {
        XCTAssertEqual(reading(done: 1, total: 4, left: 0), .passed(remaining: 3))
        XCTAssertEqual(reading(done: 3, total: 4, left: 0), .passed(remaining: 1))
    }

    func testAllDoneHasNoReading() {
        XCTAssertNil(reading(done: 4, total: 4, left: 3 * 3600))
        XCTAssertNil(reading(done: 0, total: 0, left: 3 * 3600))
    }

    func testStudyAloneCanBeBehindEvenWithNothingDone() {
        // 90 minutes of study left, 60 minutes of day left: 30 short, no pace needed.
        XCTAssertEqual(reading(done: 0, total: 4, left: 3600, study: 90), .studyBehind(minutes: 30))
        XCTAssertFalse(LockdownPace.Reading.studyBehind(minutes: 30).onTrack)
    }

    func testMessages() {
        let format: (Date) -> String = { _ in "7:00 PM" }
        XCTAssertEqual(
            LockdownPace.message(for: .passed(remaining: 1), finishFormat: format),
            "PS5 time has passed. 1 task still incomplete."
        )
        XCTAssertEqual(
            LockdownPace.message(for: .passed(remaining: 3), finishFormat: format),
            "PS5 time has passed. 3 tasks still incomplete."
        )
        XCTAssertEqual(
            LockdownPace.message(for: .onPace(finish: now, ahead: true), finishFormat: format),
            "On pace to finish by 7:00 PM. Ahead of schedule."
        )
        XCTAssertEqual(
            LockdownPace.message(for: .onPace(finish: now, ahead: false), finishFormat: format),
            "At this pace, you'll finish by 7:00 PM. Stay focused."
        )
    }

    // MARK: - Weekly days

    func testTwoPerfectDaysAreTwoOfTwoNotSevenOfSeven() {
        let tally = WeeklyDays.tally([(1, 1), (1, 1)])
        XCTAssertEqual(tally, WeeklyDays.Tally(completed: 2, tracked: 2))
        XCTAssertEqual(WeeklyDays.phrase(tally), "2 of 2 days completed")
    }

    func testOnlyFullyCompletedDaysCount() {
        let tally = WeeklyDays.tally([(2, 2), (1, 2), (0, 2), (0, 0)])
        XCTAssertEqual(tally.completed, 1)
        XCTAssertEqual(tally.tracked, 3)
        XCTAssertEqual(tally.progress, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testOneTrackedDayAndNoTrackedDays() {
        XCTAssertEqual(WeeklyDays.phrase(WeeklyDays.tally([(1, 1)])), "1 of 1 day completed")
        let none = WeeklyDays.tally([(0, 0), (0, 0)])
        XCTAssertEqual(WeeklyDays.phrase(none), "No days tracked yet")
        XCTAssertEqual(none.progress, 0)
    }

    // MARK: - Plurals

    func testPlurals() {
        XCTAssertEqual(Plural.count(1, "day"), "1 day")
        XCTAssertEqual(Plural.count(0, "day"), "0 days")
        XCTAssertEqual(Plural.count(2, "session"), "2 sessions")
        XCTAssertEqual(Plural.count(3, "box", "boxes"), "3 boxes")
    }

    func testDaysLeft() {
        XCTAssertEqual(Plural.daysLeft(-2), "Passed")
        XCTAssertEqual(Plural.daysLeft(0), "Today")
        XCTAssertEqual(Plural.daysLeft(1), "Tomorrow")
        XCTAssertEqual(Plural.daysLeft(9), "9 days left")
    }
}
