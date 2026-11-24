//
// TrainDisplayLogicTests.swift
// Tempo
//
// The Train screens' wording and visibility rules: counts agree with their
// noun, the coach's modality never shows an underscore, a suggested workout
// window never sits in the past, and the Start workout bar hides under the
// Paused card.
//

@testable import Tempo
import XCTest

final class TrainDisplayLogicTests: XCTestCase {
    // MARK: - TrainCount

    func testCountAgreesWithNoun() {
        XCTAssertEqual(TrainCount.text(0, "exercise"), "0 exercises")
        XCTAssertEqual(TrainCount.text(1, "exercise"), "1 exercise")
        XCTAssertEqual(TrainCount.text(6, "exercise"), "6 exercises")
        XCTAssertEqual(TrainCount.text(1, "PR"), "1 PR")
        XCTAssertEqual(TrainCount.text(58, "PR"), "58 PRs")
        XCTAssertEqual(TrainCount.noun(1, "set"), "set")
        XCTAssertEqual(TrainCount.noun(2, "set"), "sets")
        XCTAssertEqual(TrainCount.text(2, "person", plural: "people"), "2 people")
    }

    // MARK: - TrainModalityName

    func testModalityNeverShowsAnUnderscore() {
        XCTAssertEqual(TrainModalityName.displayName("full_body"), "Full Body")
        XCTAssertEqual(TrainModalityName.displayName("Full_Body"), "Full Body")
        XCTAssertEqual(TrainModalityName.displayName("push"), "Push")
        XCTAssertEqual(TrainModalityName.displayName("zone_2_run"), "Zone 2 Run")
        XCTAssertEqual(TrainModalityName.displayName("recovery"), "Recovery")
    }

    // MARK: - TrainWindowMath

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testWindowInThePastIsDropped() {
        let window = DateInterval(start: at(9), end: at(11))
        XCTAssertNil(TrainWindowMath.upcoming(window, now: at(15)))
    }

    func testWindowStillAheadIsKeptAsIs() throws {
        let window = DateInterval(start: at(17), end: at(19))
        let kept = try XCTUnwrap(TrainWindowMath.upcoming(window, now: at(15)))
        XCTAssertEqual(kept, window)
    }

    func testWindowAlreadyUnderwayStartsFromNowRoundedUp() throws {
        let window = DateInterval(start: at(9), end: at(18))
        let kept = try XCTUnwrap(TrainWindowMath.upcoming(window, now: at(15, 2)))
        XCTAssertEqual(kept.start, at(15, 5))
        XCTAssertEqual(kept.end, at(18))
    }

    func testWindowWithLessThanFortyFiveMinutesLeftIsDropped() {
        let window = DateInterval(start: at(9), end: at(18))
        XCTAssertNil(TrainWindowMath.upcoming(window, now: at(17, 30)))
        XCTAssertNotNil(TrainWindowMath.upcoming(window, now: at(17, 10)))
    }

    // MARK: - TrainStartBar

    func testStartBarHidesUnderThePausedCard() {
        XCTAssertTrue(TrainStartBar.isVisible(
            canStartWorkout: true, isLoading: false, showsBedtimeCard: false, showsPausedCard: false
        ))
        XCTAssertFalse(TrainStartBar.isVisible(
            canStartWorkout: true, isLoading: false, showsBedtimeCard: false, showsPausedCard: true
        ))
        XCTAssertFalse(TrainStartBar.isVisible(
            canStartWorkout: true, isLoading: false, showsBedtimeCard: true, showsPausedCard: false
        ))
        XCTAssertFalse(TrainStartBar.isVisible(
            canStartWorkout: true, isLoading: true, showsBedtimeCard: false, showsPausedCard: false
        ))
        XCTAssertFalse(TrainStartBar.isVisible(
            canStartWorkout: false, isLoading: false, showsBedtimeCard: false, showsPausedCard: false
        ))
    }
}
