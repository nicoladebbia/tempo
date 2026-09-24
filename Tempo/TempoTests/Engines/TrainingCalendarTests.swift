//
// TrainingCalendarTests.swift
// Tempo
//
// Pins the §6 Sunday week-boundary fix: `Calendar.current`'s own
// dateComponents([.yearForWeekOfYear, .weekOfYear]) + weekday=2 math resolves
// "this Monday" to TOMORROW on an en_US Sunday (en_US's own week starts that
// Sunday, so weekday=2 is the day after it). `TrainingCalendar.mondayOfWeek`
// must return the Monday that just passed — 6 days BEHIND, never 1 day AHEAD
// — regardless of the device's region calendar, and on every day of the week.
//

@testable import Tempo
import XCTest

final class TrainingCalendarTests: XCTestCase {
    /// A fixed en_US, Sunday-first calendar — the exact shape that produced
    /// the bug — used ONLY to construct fixture dates, never passed to the
    /// code under test (which must be locale-independent on its own).
    private var enUSSundayFirstCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return enUSSundayFirstCalendar.date(from: comps)!
    }

    func testSunday_mondayOfWeekIsSixDaysBeforeNotTomorrow() {
        // 2026-09-20 is a Sunday; 2026-09-21 (tomorrow) is the bug's wrong
        // answer, 2026-09-14 (six days earlier) is the correct "this Monday".
        let sunday = date(2026, 9, 20)
        let expectedMonday = date(2026, 9, 14)
        let wrongTomorrow = date(2026, 9, 21)

        let result = TrainingCalendar.mondayOfWeek(containing: sunday)

        XCTAssertTrue(
            enUSSundayFirstCalendar.isDate(result, inSameDayAs: expectedMonday),
            "Expected the Monday that already passed, got \(result)"
        )
        XCTAssertFalse(
            enUSSundayFirstCalendar.isDate(result, inSameDayAs: wrongTomorrow),
            "Must never resolve to tomorrow — that was the en_US Calendar.current bug"
        )
    }

    func testMidweek_mondayOfWeekIsThatSameWeeksMonday() {
        // 2026-09-16 is a Wednesday in the same ISO week as 2026-09-14 (Monday).
        let wednesday = date(2026, 9, 16)
        let expectedMonday = date(2026, 9, 14)

        let result = TrainingCalendar.mondayOfWeek(containing: wednesday)

        XCTAssertTrue(enUSSundayFirstCalendar.isDate(result, inSameDayAs: expectedMonday))
    }

    func testMonday_mondayOfWeekIsItself() {
        let monday = date(2026, 9, 14)
        let result = TrainingCalendar.mondayOfWeek(containing: monday)
        XCTAssertTrue(enUSSundayFirstCalendar.isDate(result, inSameDayAs: monday))
    }
}
