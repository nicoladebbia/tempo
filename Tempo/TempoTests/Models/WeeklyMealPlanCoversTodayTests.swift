//
// WeeklyMealPlanCoversTodayTests.swift
// Tempo
//
// Bug A guard — the stale-active-plan invariant. A WeeklyMealPlan stays
// `isActive` until the next generation deletes it, so `isActive` alone is
// NOT sufficient to decide "is this the current plan". `coversToday` /
// `coversDate` gate on the [startDate, endDate] range so an out-of-range
// past plan (e.g. dated May 25–31 viewed on June 2) is correctly treated as
// not-current. This is the bug that showed a stale plan as active and drove
// a wrong Today/Plan view, so it's pinned by test.
//

@testable import Tempo
import XCTest

final class WeeklyMealPlanCoversTodayTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func plan(start: Date, end: Date, isActive: Bool = true) -> WeeklyMealPlan {
        WeeklyMealPlan(startDate: start, endDate: end, isActive: isActive)
    }

    // MARK: - The reported bug: a past plan must NOT cover today

    func testPastPlanDoesNotCoverLaterDate() {
        // May 25–31 plan, asked about June 2 — the exact reported scenario.
        let p = plan(start: day(2026, 5, 25), end: day(2026, 5, 31))
        XCTAssertFalse(p.coversDate(day(2026, 6, 2)),
                       "A May 25–31 plan must not be current on June 2")
    }

    func testFuturePlanDoesNotCoverEarlierDate() {
        let p = plan(start: day(2026, 6, 8), end: day(2026, 6, 14))
        XCTAssertFalse(p.coversDate(day(2026, 6, 2)),
                       "A future plan is not yet current")
    }

    // MARK: - Inclusive bounds (both endpoints count, full last day)

    func testStartDayIsCovered() {
        let p = plan(start: day(2026, 6, 1), end: day(2026, 6, 7))
        XCTAssertTrue(p.coversDate(day(2026, 6, 1)), "startDate is inclusive")
    }

    func testEndDayIsCovered() {
        // endDate is normalized to start-of-day(June 7); any moment on June 7
        // must still count as covered.
        let p = plan(start: day(2026, 6, 1), end: day(2026, 6, 7))
        let lateOnEndDay = cal.date(byAdding: .hour, value: 23, to: day(2026, 6, 7))!
        XCTAssertTrue(p.coversDate(lateOnEndDay),
                      "The whole of endDate's calendar day is covered")
    }

    func testMidWeekDayIsCovered() {
        let p = plan(start: day(2026, 6, 1), end: day(2026, 6, 7))
        XCTAssertTrue(p.coversDate(day(2026, 6, 4)))
    }

    // MARK: - Boundary: day before start / day after end

    func testDayBeforeStartNotCovered() {
        let p = plan(start: day(2026, 6, 1), end: day(2026, 6, 7))
        XCTAssertFalse(p.coversDate(day(2026, 5, 31)))
    }

    func testDayAfterEndNotCovered() {
        let p = plan(start: day(2026, 6, 1), end: day(2026, 6, 7))
        XCTAssertFalse(p.coversDate(day(2026, 6, 8)))
    }

    // MARK: - isActive is orthogonal to coverage

    func testCoversDateIgnoresIsActiveFlag() {
        // coversDate is purely about the date window; the caller combines it
        // with isActive. An inactive plan can still "cover" a date.
        let p = plan(start: day(2026, 6, 1), end: day(2026, 6, 7), isActive: false)
        XCTAssertTrue(p.coversDate(day(2026, 6, 3)),
                      "coversDate is date-only; isActive is combined by the caller")
    }
}
