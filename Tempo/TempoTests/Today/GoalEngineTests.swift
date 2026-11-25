//
// GoalEngineTests.swift
// TempoTests
//
// Ahead / on track / behind from the straight line between the first reading
// and the target on the target date.
//

@testable import Tempo
import XCTest

final class GoalEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    private func evaluate(
        start startValue: Double, target: Double, current: Double?, today: Int, length: Int = 100
    ) -> GoalProgress {
        GoalEngine.evaluate(
            start: startValue, startDate: start, target: target, targetDate: day(length),
            current: current, now: day(today), calendar: calendar
        )
    }

    // MARK: A reading already past the target

    func testALiftAtOrAboveTheTargetIsReachedNotBehind() {
        let first = GoalEngine.evaluate(
            start: 105, startDate: start, target: 100, targetDate: day(100),
            current: 105, now: day(0), higherIsBetter: true, calendar: calendar
        )
        XCTAssertEqual(first.pace, .reached)
        XCTAssertEqual(first.fraction, 1)
        let later = GoalEngine.evaluate(
            start: 105, startDate: start, target: 100, targetDate: day(100),
            current: 110, now: day(50), higherIsBetter: true, calendar: calendar
        )
        XCTAssertEqual(later.pace, .reached, "getting stronger never turns a reached goal into behind")
    }

    func testARunFasterThanTheTargetIsReached() {
        let progress = GoalEngine.evaluate(
            start: 1380, startDate: start, target: 1500, targetDate: day(100),
            current: 1380, now: day(10), higherIsBetter: false, calendar: calendar
        )
        XCTAssertEqual(progress.pace, .reached)
    }

    func testARunSlowerThanTheTargetIsStillToDo() {
        let progress = GoalEngine.evaluate(
            start: 1700, startDate: start, target: 1500, targetDate: day(100),
            current: 1650, now: day(10), higherIsBetter: false, calendar: calendar
        )
        XCTAssertNotEqual(progress.pace, .reached)
    }

    // MARK: Gaining (a lift going up)

    func testHalfwayThereHalfwayThroughIsOnTrack() {
        let progress = evaluate(start: 80, target: 100, current: 90, today: 50)
        XCTAssertEqual(progress.pace, .onTrack)
        XCTAssertEqual(progress.expected, 90, accuracy: 0.001)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.daysLeft, 50)
    }

    func testFurtherAlongThanTheLineIsAhead() {
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 96, today: 50).pace, .ahead)
    }

    func testFurtherBackThanTheLineIsBehind() {
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 84, today: 50).pace, .behind)
    }

    func testTheToleranceBandIsATenthOfTheWholeDistance() {
        // distance 20, band 2: expected 90 -> 88 and 92 are on track, 87.9 and 92.1 are not.
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 88, today: 50).pace, .onTrack)
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 92, today: 50).pace, .onTrack)
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 87.9, today: 50).pace, .behind)
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 92.1, today: 50).pace, .ahead)
    }

    func testReachingTheTargetEndsItEarlyOrLate() {
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 100, today: 10).pace, .reached)
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 104, today: 10).pace, .reached)
        XCTAssertEqual(evaluate(start: 80, target: 100, current: 101, today: 150).pace, .reached)
    }

    // MARK: Losing (body weight, a run time)

    func testLosingWeightOnThePaceIsOnTrack() {
        let progress = evaluate(start: 90, target: 80, current: 85, today: 50)
        XCTAssertEqual(progress.pace, .onTrack)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
    }

    func testLosingFasterThanTheLineIsAhead() {
        XCTAssertEqual(evaluate(start: 90, target: 80, current: 82, today: 50).pace, .ahead)
    }

    func testLosingSlowerThanTheLineIsBehind() {
        XCTAssertEqual(evaluate(start: 90, target: 80, current: 89, today: 50).pace, .behind)
    }

    func testGoingTheWrongWayIsBehindWithNoProgress() {
        let progress = evaluate(start: 90, target: 80, current: 93, today: 50)
        XCTAssertEqual(progress.pace, .behind)
        XCTAssertEqual(progress.fraction, 0, accuracy: 0.001)
    }

    func testAShorterRunTimeThanTheTargetIsReached() {
        XCTAssertEqual(evaluate(start: 1500, target: 1400, current: 1390, today: 30).pace, .reached)
    }

    // MARK: Dates and edge cases

    func testNoReadingSaysSo() {
        let progress = evaluate(start: 80, target: 100, current: nil, today: 20)
        XCTAssertEqual(progress.pace, .noReading)
        XCTAssertNil(progress.current)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testAfterTheDateTheLineIsTheTargetItself() {
        let progress = evaluate(start: 80, target: 100, current: 95, today: 130)
        XCTAssertEqual(progress.expected, 100, accuracy: 0.001)
        XCTAssertEqual(progress.pace, .behind)
        XCTAssertEqual(progress.daysLeft, -30)
    }

    func testBeforeTheStartTheLineIsTheStart() {
        let progress = evaluate(start: 80, target: 100, current: 80, today: -5)
        XCTAssertEqual(progress.expected, 80, accuracy: 0.001)
        XCTAssertEqual(progress.pace, .onTrack)
    }

    func testAGoalThatStartsAtItsTargetIsReached() {
        XCTAssertEqual(evaluate(start: 80, target: 80, current: 80, today: 10).pace, .reached)
    }

    // MARK: Words

    func testDaysLeftReadsAsAPerson() {
        XCTAssertEqual(GoalFormat.daysLeft(0), "Due today")
        XCTAssertEqual(GoalFormat.daysLeft(1), "1 day left")
        XCTAssertEqual(GoalFormat.daysLeft(12), "12 days left")
        XCTAssertEqual(GoalFormat.daysLeft(-1), "1 day over")
        XCTAssertEqual(GoalFormat.daysLeft(-9), "9 days over")
    }

    func testRunTimesReadAsAClock() {
        XCTAssertEqual(GoalFormat.clock(seconds: 1470), "24:30")
        XCTAssertEqual(GoalFormat.clock(seconds: 3725), "1:02:05")
        XCTAssertEqual(GoalFormat.distance(km: 5), "5 km")
        XCTAssertEqual(GoalFormat.distance(km: 21.1), "21.1 km")
    }

    func testEveryPaceHasATitle() {
        for pace in [GoalProgress.Pace.ahead, .onTrack, .behind, .reached, .noReading] {
            XCTAssertFalse(pace.title.isEmpty)
        }
    }

    func testAStoredGoalWithoutAStartTakesTheFirstReading() {
        let goal = Goal(kind: .bodyWeight, targetValue: 80, targetDate: day(100), startValue: nil, startDate: start)
        let progress = GoalEngine.evaluate(goal: goal, current: 90, now: day(10), calendar: calendar)
        XCTAssertEqual(progress.start, 90)
        XCTAssertEqual(progress.pace, .onTrack)
    }
}
