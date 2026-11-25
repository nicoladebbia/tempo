//
// StudyHistoryTests.swift
// Tempo
//
// The Study page's maths: minutes per day, best day, subjects, the time-of-day
// grid, and what the list of today's sessions says when it is empty.
//

@testable import Tempo
import XCTest

final class StudyHistoryTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    /// Wednesday 18 Nov 2026, 12:00.
    private var now: Date {
        date(day: 18, hour: 12)
    }

    private func date(day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func entry(day: Int, hour: Int = 9, minutes: Int, subject: String? = nil) -> StudyEntry {
        StudyEntry(startTime: date(day: day, hour: hour), durationMinutes: minutes, subject: subject)
    }

    // MARK: lastDays

    func testLastDaysAlwaysGivesOneBarPerDayOldestFirst() {
        let days = StudyHistory.lastDays([], endingOn: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.date, date(day: 12, hour: 0))
        XCTAssertEqual(days.last?.date, date(day: 18, hour: 0))
        XCTAssertTrue(days.allSatisfy { $0.minutes == 0 })
    }

    func testLastDaysAddsSessionsOfTheSameDay() {
        let entries = [entry(day: 18, hour: 8, minutes: 30), entry(day: 18, hour: 20, minutes: 45), entry(day: 17, minutes: 10)]
        let days = StudyHistory.lastDays(entries, endingOn: now, calendar: calendar)
        XCTAssertEqual(days.last?.minutes, 75)
        XCTAssertEqual(days[5].minutes, 10)
    }

    func testLastDaysLeavesOutSessionsOlderThanTheWindow() {
        let days = StudyHistory.lastDays([entry(day: 5, minutes: 90)], endingOn: now, calendar: calendar)
        XCTAssertEqual(days.reduce(0) { $0 + $1.minutes }, 0)
    }

    // MARK: bestDay

    func testBestDayIsTheBusiestDayNotTheLongestSession() {
        let entries = [
            entry(day: 10, minutes: 80),
            entry(day: 12, hour: 8, minutes: 40), entry(day: 12, hour: 15, minutes: 50),
        ]
        let best = StudyHistory.bestDay(entries, calendar: calendar)
        XCTAssertEqual(best?.minutes, 90)
        XCTAssertEqual(best?.date, date(day: 12, hour: 0))
    }

    func testBestDayTieGoesToTheEarlierDay() {
        let best = StudyHistory.bestDay([entry(day: 14, minutes: 60), entry(day: 11, minutes: 60)], calendar: calendar)
        XCTAssertEqual(best?.date, date(day: 11, hour: 0))
    }

    func testBestDayIsNilWhenNothingWasStudied() {
        XCTAssertNil(StudyHistory.bestDay([], calendar: calendar))
        XCTAssertNil(StudyHistory.bestDay([entry(day: 10, minutes: 0)], calendar: calendar))
    }

    // MARK: subjectTotals

    func testSubjectTotalsGroupSortAndNameTheUntagged() {
        let entries = [
            entry(day: 17, minutes: 30, subject: "Maths"),
            entry(day: 18, minutes: 45, subject: "Maths"),
            entry(day: 18, minutes: 20, subject: "Physics"),
            entry(day: 18, minutes: 90, subject: nil),
            entry(day: 18, minutes: 5, subject: ""),
        ]
        let totals = StudyHistory.subjectTotals(entries, since: date(day: 16, hour: 0))
        XCTAssertEqual(totals.map(\.subject), ["Untagged", "Maths", "Physics"])
        XCTAssertEqual(totals.map(\.minutes), [95, 75, 20])
    }

    func testSubjectTotalsIgnoreSessionsBeforeTheStart() {
        let totals = StudyHistory.subjectTotals([entry(day: 10, minutes: 60, subject: "Maths")], since: date(day: 16, hour: 0))
        XCTAssertTrue(totals.isEmpty)
    }

    // MARK: heatmap

    func testHeatmapPutsMondayInTheFirstColumnAndSixAmInTheFirstRow() {
        // 16 Nov 2026 is a Monday.
        let grid = StudyHistory.heatmap([entry(day: 16, hour: 6, minutes: 25)], now: now, calendar: calendar)
        XCTAssertEqual(grid.count, 7)
        XCTAssertEqual(grid[0].count, 16)
        XCTAssertEqual(grid[0][0], 25)
    }

    func testHeatmapPutsSundayInTheLastColumn() {
        // 15 Nov 2026 is a Sunday.
        let grid = StudyHistory.heatmap([entry(day: 15, hour: 21, minutes: 40)], now: now, calendar: calendar)
        XCTAssertEqual(grid[6][15], 40)
    }

    func testHeatmapSkipsNightHoursAndOldSessions() throws {
        let entries = try [
            entry(day: 17, hour: 3, minutes: 50),
            entry(day: 17, hour: 22, minutes: 50),
            StudyEntry(startTime: XCTUnwrap(calendar.date(byAdding: .day, value: -40, to: now)), durationMinutes: 50, subject: nil),
        ]
        let grid = StudyHistory.heatmap(entries, now: now, calendar: calendar)
        XCTAssertEqual(grid.flatMap(\.self).reduce(0, +), 0)
    }

    // MARK: formatting

    func testFormatMinutes() {
        XCTAssertEqual(StudyHistory.formatMinutes(0), "0m")
        XCTAssertEqual(StudyHistory.formatMinutes(45), "45m")
        XCTAssertEqual(StudyHistory.formatMinutes(120), "2h")
        XCTAssertEqual(StudyHistory.formatMinutes(125), "2h 5m")
    }

    // MARK: today's list

    func testNothingStudiedAndNothingListedSaysNothingYet() {
        XCTAssertEqual(StudyTodayList.empty(minutesToday: 0, sessionCount: 0), .nothingYet)
    }

    func testMinutesWithoutSessionsDoNotClaimThereWereNoSessions() {
        // Two hours counted today with no session behind them.
        XCTAssertEqual(StudyTodayList.empty(minutesToday: 120, sessionCount: 0), .minutesWithoutSessions)
    }

    func testSessionsMeanNoEmptyState() {
        XCTAssertNil(StudyTodayList.empty(minutesToday: 120, sessionCount: 2))
        XCTAssertNil(StudyTodayList.empty(minutesToday: 0, sessionCount: 1))
    }

    func testShownMinutesDropTheHiddenSessionAndNeverGoNegative() {
        XCTAssertEqual(StudyTodayList.shownMinutes(counted: 120, removed: 45), 75)
        XCTAssertEqual(StudyTodayList.shownMinutes(counted: 30, removed: 45), 0)
        XCTAssertEqual(StudyTodayList.shownMinutes(counted: 30, removed: -5), 30)
    }
}
