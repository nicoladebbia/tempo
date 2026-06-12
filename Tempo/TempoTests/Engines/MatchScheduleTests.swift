//
// MatchScheduleTests.swift
// Tempo
//
// Proves the pure match-schedule math (docs/INTELLIGENT_TRAINING_SYSTEM.md §9 D3,
// §14 mid-week-match trigger): daysUntilNextMatch picks the nearest upcoming
// match ignoring past ones, T-1 detection lands exactly one day before, and
// match-day (T-0) detection is start-of-day robust regardless of kickoff time.
// Pure — no SwiftData, no implicit "now".
//

@testable import Tempo
import XCTest

final class MatchScheduleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")! // Nicola is in Miami (ET)
        return c
    }()

    /// A fixed reference day at noon so ±hours never crosses a day boundary.
    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let start = cal.startOfDay(for: base)
        let shifted = cal.date(byAdding: .day, value: offset, to: start)!
        return cal.date(byAdding: .hour, value: hour, to: shifted)!
    }

    // MARK: - daysUntilNextMatch

    func testNoMatchesReturnsNil() {
        XCTAssertNil(MatchSchedule.daysUntilNextMatch(kickoffs: [], from: day(0), calendar: cal))
    }

    func testMatchTodayIsZero() {
        // A match at 7PM today, asked at 9AM today → still 0 (same day).
        let result = MatchSchedule.daysUntilNextMatch(kickoffs: [day(0, hour: 19)], from: day(0, hour: 9), calendar: cal)
        XCTAssertEqual(result, 0)
    }

    func testMatchTomorrowIsOne() {
        XCTAssertEqual(MatchSchedule.daysUntilNextMatch(kickoffs: [day(1)], from: day(0), calendar: cal), 1)
    }

    func testPicksNearestUpcomingIgnoringPast() {
        // Past match (-3), far match (+10), near match (+2) — expect 2.
        let kickoffs = [day(-3), day(10), day(2)]
        XCTAssertEqual(MatchSchedule.daysUntilNextMatch(kickoffs: kickoffs, from: day(0), calendar: cal), 2)
    }

    func testAllPastReturnsNil() {
        XCTAssertNil(MatchSchedule.daysUntilNextMatch(kickoffs: [day(-1), day(-5)], from: day(0), calendar: cal))
    }

    func testUnsortedInputHandled() {
        let kickoffs = [day(7), day(1), day(4)]
        XCTAssertEqual(MatchSchedule.daysUntilNextMatch(kickoffs: kickoffs, from: day(0), calendar: cal), 1)
    }

    // MARK: - isTMinus1

    func testTMinus1TrueExactlyOneDayBefore() {
        let keys: Set<Date> = [cal.startOfDay(for: day(1))]
        XCTAssertTrue(MatchSchedule.isTMinus1(date: day(0), matchDayKeys: keys, calendar: cal))
    }

    func testTMinus1FalseOnMatchDayItself() {
        let keys: Set<Date> = [cal.startOfDay(for: day(0))]
        XCTAssertFalse(MatchSchedule.isTMinus1(date: day(0), matchDayKeys: keys, calendar: cal))
    }

    func testTMinus1FalseTwoDaysBefore() {
        let keys: Set<Date> = [cal.startOfDay(for: day(2))]
        XCTAssertFalse(MatchSchedule.isTMinus1(date: day(0), matchDayKeys: keys, calendar: cal))
    }

    func testTMinus1IgnoresKickoffTime() {
        // Match at 9AM tomorrow; "today" asked at 11PM → still T-1.
        let keys: Set<Date> = [cal.startOfDay(for: day(1, hour: 9))]
        XCTAssertTrue(MatchSchedule.isTMinus1(date: day(0, hour: 23), matchDayKeys: keys, calendar: cal))
    }

    // MARK: - isMatchDay

    func testMatchDayTrueRegardlessOfHour() {
        let keys: Set<Date> = [cal.startOfDay(for: day(0))]
        XCTAssertTrue(MatchSchedule.isMatchDay(date: day(0, hour: 6), matchDayKeys: keys, calendar: cal))
        XCTAssertTrue(MatchSchedule.isMatchDay(date: day(0, hour: 23), matchDayKeys: keys, calendar: cal))
    }

    func testMatchDayFalseOnOtherDay() {
        let keys: Set<Date> = [cal.startOfDay(for: day(0))]
        XCTAssertFalse(MatchSchedule.isMatchDay(date: day(1), matchDayKeys: keys, calendar: cal))
    }
}
