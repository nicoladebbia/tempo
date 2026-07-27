//
// WorkoutWindowPreferenceTests.swift
// Tempo
//
// Requirement (c): the suggested workout window respects the user's training-
// time preference — a REAL calendar-free slot inside their preferred daypart,
// falling back to the largest free gap when that daypart is busy. Pins the two
// pure helpers CalendarService.suggestWorkoutWindow now composes.
//

@testable import Tempo
import XCTest

@MainActor
final class WorkoutWindowPreferenceTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private var day: Date { cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }
    private let minDur: TimeInterval = 45 * 60

    func testPreferredDaypartMapsHours() {
        let morning = CalendarService.preferredDaypart(for: .morning, on: day, calendar: cal)
        XCTAssertEqual(morning?.start, at(8))
        XCTAssertEqual(morning?.end, at(12))
        let evening = CalendarService.preferredDaypart(for: .evening, on: day, calendar: cal)
        XCTAssertEqual(evening?.start, at(17))
        XCTAssertEqual(evening?.end, at(22))
        XCTAssertNil(CalendarService.preferredDaypart(for: .anyFree, on: day, calendar: cal),
                     "anyFree imposes no time-of-day bias")
    }

    func testPrefersSlotInsidePreferredDaypartOverLargerGapOutside() {
        // A 2h morning gap vs a bigger 5h evening gap.
        let gaps = [DateInterval(start: at(9), end: at(11)),
                    DateInterval(start: at(17), end: at(22))]
        let morning = CalendarService.preferredDaypart(for: .morning, on: day, calendar: cal)
        let picked = CalendarService.bestWindow(freeGaps: gaps, preferred: morning, minimumDuration: minDur)
        XCTAssertEqual(picked?.start, at(9), "Morning person gets the morning slot, not the larger evening block")
        XCTAssertEqual(picked?.end, at(11))
    }

    func testFallsBackToLargestGapWhenPreferredDaypartBusy() {
        // Only an evening gap exists; a morning preference can't be honored.
        let gaps = [DateInterval(start: at(18), end: at(21))]
        let morning = CalendarService.preferredDaypart(for: .morning, on: day, calendar: cal)
        let picked = CalendarService.bestWindow(freeGaps: gaps, preferred: morning, minimumDuration: minDur)
        XCTAssertEqual(picked?.start, at(18), "Preferred daypart busy → fall back to the real free evening slot")
    }

    func testAnyFreeReturnsLargestGap() {
        let gaps = [DateInterval(start: at(9), end: at(10)),
                    DateInterval(start: at(14), end: at(18))]
        let picked = CalendarService.bestWindow(freeGaps: gaps, preferred: nil, minimumDuration: minDur)
        XCTAssertEqual(picked?.start, at(14), "anyFree → the largest free gap")
    }

    func testClampsPreferredOverlapToDaypart() {
        // A gap spanning 10–14 under a morning preference (8–12) clamps to 10–12.
        let gaps = [DateInterval(start: at(10), end: at(14))]
        let morning = CalendarService.preferredDaypart(for: .morning, on: day, calendar: cal)
        let picked = CalendarService.bestWindow(freeGaps: gaps, preferred: morning, minimumDuration: minDur)
        XCTAssertEqual(picked?.start, at(10))
        XCTAssertEqual(picked?.end, at(12))
    }

    func testRejectsSubMinimumGaps() {
        let gaps = [DateInterval(start: at(9), end: at(9, 30))] // 30 min < 45
        XCTAssertNil(CalendarService.bestWindow(freeGaps: gaps, preferred: nil, minimumDuration: minDur))
    }
}
