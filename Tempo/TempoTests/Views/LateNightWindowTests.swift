//
// LateNightWindowTests.swift
// Tempo
//
// Midnight–5am counts as "still last night": Today shows the bedtime card
// instead of the live session.
//

@testable import Tempo
import XCTest

final class LateNightWindowTests: XCTestCase {
    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute)
        components.calendar = .current
        return components.date!
    }

    func testMidnightToFiveIsLateNight() {
        XCTAssertTrue(LateNightWindow.contains(date(hour: 0, minute: 2)))
        XCTAssertTrue(LateNightWindow.contains(date(hour: 4, minute: 59)))
    }

    func testFiveAmOnwardIsTheNewDay() {
        XCTAssertFalse(LateNightWindow.contains(date(hour: 5)))
        XCTAssertFalse(LateNightWindow.contains(date(hour: 12)))
        XCTAssertFalse(LateNightWindow.contains(date(hour: 23, minute: 59)))
    }

    // MARK: - "Skip for tonight" skip-until computation

    func testSkipUntilIsFiveAmOfTheSameCalendarDay() {
        let now = date(hour: 1, minute: 30)
        let skipUntil = LateNightWindow.skipUntil(from: now)
        let expected = date(hour: 5)
        XCTAssertEqual(skipUntil, expected)
    }

    func testSkipUntilTakenRightBeforeFiveAmIsStillMinutesAway() {
        let now = date(hour: 4, minute: 58)
        let skipUntil = LateNightWindow.skipUntil(from: now)
        XCTAssertEqual(skipUntil, date(hour: 5))
        XCTAssertGreaterThan(skipUntil, now)
    }
}
