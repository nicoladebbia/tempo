//
// WeeklyTrainingScheduleTests.swift
// Tempo
//
// Created by Tempo on 26/05/2026.
//
// Phase 10b1 — day alignment between ActiveDays bitmask (Mon-1-based)
// and WeeklyTrainingSchedule.byWeekday (Mon-1-based) via
// ActiveDays.isActive(on:) (Calendar-standard Sun-1-based).
//
// Bug history: before the fix, the overlay loop in
// WeeklyTrainingSchedule.make passed the Mon-1 weekday index directly into
// isActive, which interpreted it as Calendar-standard. A user who marked
// Wednesday as a football day would see Tuesday football appear in the
// nutrition weekly plan — every day shifted by one.
//

@testable import Tempo
import XCTest

final class WeeklyTrainingScheduleTests: XCTestCase {
    func testFootballOnWednesdayLandsOnWednesday() {
        let footballDays = ActiveDays(rawValue: ActiveDays.wednesday.rawValue)
        let schedule = WeeklyTrainingSchedule.make(split: .pushPullLegs, footballDays: footballDays)
        // Mon=1, Tue=2, Wed=3, ..., Sun=7 in this dict.
        XCTAssertEqual(schedule.byWeekday[3], "Football", "Wednesday football must land on byWeekday[3]")
        // Tuesday and Thursday must remain at their PPL labels.
        XCTAssertEqual(schedule.byWeekday[2], "Pull", "Tuesday must NOT have been clobbered by football")
        XCTAssertEqual(schedule.byWeekday[4], "Push", "Thursday must NOT have been clobbered by football")
    }

    func testFootballOnSundayLandsOnSunday() {
        let footballDays = ActiveDays(rawValue: ActiveDays.sunday.rawValue)
        let schedule = WeeklyTrainingSchedule.make(split: .pushPullLegs, footballDays: footballDays)
        // Sunday is the wrap-around case for our (weekday % 7) + 1 conversion.
        XCTAssertEqual(schedule.byWeekday[7], "Football", "Sunday football must land on byWeekday[7]")
        // Monday (bit 0 of ActiveDays) must remain Push, NOT be flipped to football.
        XCTAssertEqual(schedule.byWeekday[1], "Push", "Monday must NOT have been clobbered by Sunday football")
    }

    func testFootballOnMondayLandsOnMonday() {
        let footballDays = ActiveDays(rawValue: ActiveDays.monday.rawValue)
        let schedule = WeeklyTrainingSchedule.make(split: .pushPullLegs, footballDays: footballDays)
        XCTAssertEqual(schedule.byWeekday[1], "Football", "Monday football must land on byWeekday[1]")
        // Saturday (the previous slot when wrapped) must remain Legs.
        XCTAssertEqual(schedule.byWeekday[6], "Legs", "Saturday must NOT have been clobbered")
    }

    func testTuesdayAndThursdayFootballLandsCorrectly() {
        let rawValue = ActiveDays.tuesday.rawValue | ActiveDays.thursday.rawValue
        let footballDays = ActiveDays(rawValue: rawValue)
        let schedule = WeeklyTrainingSchedule.make(split: .upperLower, footballDays: footballDays)
        XCTAssertEqual(schedule.byWeekday[2], "Football", "Tuesday football must land on byWeekday[2]")
        XCTAssertEqual(schedule.byWeekday[4], "Football", "Thursday football must land on byWeekday[4]")
        // Wednesday and Friday must remain at their Upper/Lower labels —
        // a one-off shift bug would have moved football to Mon+Wed.
        XCTAssertEqual(schedule.byWeekday[3], "Upper", "Wednesday must NOT be football")
        XCTAssertEqual(schedule.byWeekday[5], "Upper", "Friday must NOT be football")
    }

    func testEmptyFootballDaysLeavesBaseSplitUntouched() {
        let schedule = WeeklyTrainingSchedule.make(split: .pushPullLegs, footballDays: ActiveDays(rawValue: 0))
        XCTAssertEqual(schedule.byWeekday[1], "Push")
        XCTAssertEqual(schedule.byWeekday[2], "Pull")
        XCTAssertEqual(schedule.byWeekday[3], "Legs")
        XCTAssertEqual(schedule.byWeekday[4], "Push")
        XCTAssertEqual(schedule.byWeekday[5], "Pull")
        XCTAssertEqual(schedule.byWeekday[6], "Legs")
        XCTAssertEqual(schedule.byWeekday[7], "Rest")
    }
}
