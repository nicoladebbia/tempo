//
// TodayPromptPlannerTests.swift
// TempoTests
//
// Today shows at most one prominent card, and the week in review is loud only
// on Sunday evening and Monday morning.
//

@testable import Tempo
import XCTest

final class TodayPromptPlannerTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
    }

    /// Day in November 2026: the 22nd is a Sunday.
    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func prompt(
        _ facts: TodayPromptPlanner.Facts, day: Int, hour: Int, minute: Int = 0
    ) -> TodayPromptPlanner.Prompt? {
        TodayPromptPlanner.prominent(facts, now: at(day: day, hour: hour, minute: minute), calendar: calendar)
    }

    func testNothingToAskShowsNothing() {
        XCTAssertNil(prompt(.init(), day: 24, hour: 20))
    }

    func testSetupComesBeforeEverything() {
        let facts = TodayPromptPlanner.Facts(setupVisible: true, hasWeekData: true, tomorrowHasContent: true)
        XCTAssertEqual(prompt(facts, day: 22, hour: 21), .setup)
        XCTAssertEqual(prompt(facts, day: 24, hour: 21), .setup)
    }

    func testWeekReviewIsLoudSundayEveningAndMondayMorningOnly() {
        let facts = TodayPromptPlanner.Facts(hasWeekData: true)
        XCTAssertNil(prompt(facts, day: 22, hour: 12))
        XCTAssertNil(prompt(facts, day: 22, hour: 19, minute: 29))
        XCTAssertEqual(prompt(facts, day: 22, hour: 19, minute: 30), .weekReview)
        XCTAssertEqual(prompt(facts, day: 22, hour: 23), .weekReview)
        XCTAssertEqual(prompt(facts, day: 23, hour: 7), .weekReview)
        XCTAssertEqual(prompt(facts, day: 23, hour: 11, minute: 59), .weekReview)
        XCTAssertNil(prompt(facts, day: 23, hour: 12))
        XCTAssertNil(prompt(facts, day: 25, hour: 8))
        XCTAssertNil(prompt(facts, day: 28, hour: 21))
    }

    func testWeekReviewNeedsSomethingToReview() {
        XCTAssertNil(prompt(.init(hasWeekData: false), day: 22, hour: 21))
    }

    func testTomorrowShowsInTheEveningOnlyWhenItHasContent() {
        XCTAssertEqual(prompt(.init(tomorrowHasContent: true), day: 24, hour: 20), .tomorrow)
        XCTAssertNil(prompt(.init(tomorrowHasContent: true), day: 24, hour: 15))
        XCTAssertNil(prompt(.init(tomorrowHasContent: false), day: 24, hour: 20))
    }

    func testTheEveningFollowsTheSchedule() {
        var facts = TodayPromptPlanner.Facts(tomorrowHasContent: true)
        facts.leisureMinutes = 21 * 60
        XCTAssertNil(prompt(facts, day: 24, hour: 20))
        XCTAssertEqual(prompt(facts, day: 24, hour: 21), .tomorrow)
    }

    func testSundayEveningPrefersTheWeekOverTomorrow() {
        let facts = TodayPromptPlanner.Facts(hasWeekData: true, tomorrowHasContent: true)
        XCTAssertEqual(prompt(facts, day: 22, hour: 21), .weekReview)
    }

    func testQuietLinksCoverWhatIsNotAlreadyACard() {
        let shown = TodayPromptPlanner.quietLinks(prominent: .weekReview, hasWeekData: true, hasGoal: false, isConfigured: true)
        XCTAssertFalse(shown.weekReview)
        XCTAssertTrue(shown.setGoal)

        let quiet = TodayPromptPlanner.quietLinks(prominent: nil, hasWeekData: true, hasGoal: true, isConfigured: true)
        XCTAssertTrue(quiet.weekReview)
        XCTAssertFalse(quiet.setGoal)
    }

    func testNoLinksWhenThereIsNothingToLinkTo() {
        let links = TodayPromptPlanner.quietLinks(prominent: nil, hasWeekData: false, hasGoal: false, isConfigured: false)
        XCTAssertFalse(links.weekReview)
        XCTAssertFalse(links.setGoal)
    }

    func testMondayMorningReviewsTheWeekThatJustEnded() {
        XCTAssertEqual(
            WeekReviewBuilder.reference(for: at(day: 23, hour: 8), calendar: calendar), at(day: 22, hour: 8)
        )
        XCTAssertEqual(
            WeekReviewBuilder.reference(for: at(day: 23, hour: 13), calendar: calendar), at(day: 23, hour: 13)
        )
        XCTAssertEqual(
            WeekReviewBuilder.reference(for: at(day: 24, hour: 8), calendar: calendar), at(day: 24, hour: 8)
        )
    }
}
