//
// ProgramSchedulerTests.swift
// Tempo
//
// Sessions without weekdays are placed around football: lifts spread on free
// days, conditioning on the rest, overflow stacked as a second session.
//

@testable import Tempo
import XCTest

final class ProgramSchedulerTests: XCTestCase {
    private func lift(_ title: String) -> ProgramDay {
        ProgramDay(weekday: 1, title: title, focus: "full_body",
                   exercises: [ProgramExercise(name: "Leg Press", sets: 3, repsLow: 8)], weekdayGuessed: true)
    }

    private func cond(_ title: String) -> ProgramDay {
        ProgramDay(weekday: 1, title: title, focus: "run",
                   exercises: [ProgramExercise(name: "Run", sets: 1, repsLow: 1, detail: "15' easy")], weekdayGuessed: true)
    }

    func testRealTwoLiftsThreeConditioningAroundFootball() {
        // Football Tue / Thu / Sat → free Mon, Wed, Fri, Sun.
        let week = ProgramWeek(days: [lift("Lifting 1"), lift("Lifting 2"), cond("Aerobic"), cond("Anaerobic"), cond("Speed")])
        let placed = ProgramScheduler.place(week: week, footballWeekdays: [2, 4, 6])
        let days = placed.days.map(\.weekday)

        XCTAssertTrue(placed.days.allSatisfy { ![2, 4, 6].contains($0.weekday) }, "nothing on football days: \(days)")
        let lifts = Array(days.prefix(2))
        XCTAssertEqual(Set(lifts).count, 2, "two different lift days")
        XCTAssertGreaterThanOrEqual(abs(lifts[0] - lifts[1]), 2, "lifts spread apart: \(lifts)")
        // 4 free days, 5 sessions → exactly one day carries lift + conditioning.
        let counts = Dictionary(grouping: days, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(counts.values.filter { $0 == 2 }.count, 1, "\(days)")
        XCTAssertEqual(Set(days).count, 4)
    }

    func testSourceWeekdaysAreNeverMoved() {
        var fixed = lift("Monday lift")
        fixed.weekday = 3
        fixed.weekdayGuessed = false
        let placed = ProgramScheduler.place(week: ProgramWeek(days: [fixed, lift("Other")]), footballWeekdays: [])
        XCTAssertEqual(placed.days[0].weekday, 3)
        XCTAssertNotEqual(placed.days[1].weekday, 3)
    }

    func testFootballBitsToIsoWeekdays() {
        XCTAssertEqual(ProgramScheduler.isoWeekdays(of: ActiveDays(rawValue: 0b1010010)), [2, 5, 7])
    }

    func testSpreadPicksEvenlySpacedDays() {
        XCTAssertEqual(ProgramScheduler.spread(count: 3, over: [1, 2, 3, 4, 5, 6, 7]), [1, 4, 7])
        XCTAssertEqual(ProgramScheduler.spread(count: 2, over: [1, 3, 5, 7]), [1, 7])
    }
}
