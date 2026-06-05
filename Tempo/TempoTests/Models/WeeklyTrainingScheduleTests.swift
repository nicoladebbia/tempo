//
// WeeklyTrainingScheduleTests.swift
// Tempo
//
// WeeklyTrainingSchedule.make projects the user's TrainingSplit + footballDays
// onto a Mon=1 … Sun=7 week for the meal-plan prompt. The bug this locks: the
// football overlay fed make's Mon=1 weekday into ActiveDays.isActive(on:),
// which expects Calendar's Sun=1 — so a user with SUNDAY football got MONDAY =
// Football in the plan (measured via [Diag.Plan] wd1=Football). Pure function,
// so we assert all 7 days.
//

@testable import Tempo
import XCTest

final class WeeklyTrainingScheduleTests: XCTestCase {

    func testSundayFootball_landsOnSundayNotMonday() {
        let s = WeeklyTrainingSchedule.make(split: .pushPullLegs, footballDays: .sunday)
        // Sunday (key 7) is match day…
        XCTAssertEqual(s.byWeekday[7], "Football", "Sunday must be football")
        // …and Monday (key 1) must NOT be football — it's the split's Push day.
        XCTAssertNotEqual(s.byWeekday[1], "Football",
                          "Monday must not be football (the off-by-one bug)")
        XCTAssertEqual(s.byWeekday[1], "Push", "Monday is the PPL split's Push")
    }

    func testWednesdayFootball_landsOnWednesday() {
        // Midweek case proves no uniform shift — football lands exactly on the
        // chosen day, not one off.
        let s = WeeklyTrainingSchedule.make(split: .pushPullLegs, footballDays: .wednesday)
        XCTAssertEqual(s.byWeekday[3], "Football", "Wednesday = football")
        XCTAssertNotEqual(s.byWeekday[2], "Football", "Tuesday unaffected")
        XCTAssertNotEqual(s.byWeekday[4], "Football", "Thursday unaffected")
    }

    func testNoFootball_keepsPureSplit() {
        let s = WeeklyTrainingSchedule.make(
            split: .pushPullLegs, footballDays: ActiveDays(rawValue: 0)
        )
        XCTAssertEqual(s.byWeekday[1], "Push")
        XCTAssertEqual(s.byWeekday[3], "Legs")
        XCTAssertEqual(s.byWeekday[6], "Legs") // Saturday
        XCTAssertEqual(s.byWeekday[7], "Rest")  // Sunday default
    }

    func testMultipleFootballDays_allLandCorrectly() {
        // ActiveDays isn't an OptionSet — combine via rawValue OR.
        let tueAndSun = ActiveDays(
            rawValue: ActiveDays.tuesday.rawValue | ActiveDays.sunday.rawValue
        )
        let s = WeeklyTrainingSchedule.make(split: .upperLower, footballDays: tueAndSun)
        XCTAssertEqual(s.byWeekday[2], "Football", "Tuesday")
        XCTAssertEqual(s.byWeekday[7], "Football", "Sunday")
        XCTAssertNotEqual(s.byWeekday[1], "Football", "Monday unaffected")
    }
}
