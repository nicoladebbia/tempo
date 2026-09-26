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
}
