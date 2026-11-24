//
// BodyHistoryTests.swift
// Tempo
//
// What the Body page compares today against: the average of the days before it,
// yesterday and last week, each only when there are real days behind it.
//

@testable import Tempo
import XCTest

final class BodyHistoryTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    private func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 6))!
    }

    private func reading(
        _ d: Int, recovery: Double = 70, hrv: Double? = nil, rhr: Double? = nil, sleep: Double? = nil
    ) -> RecoveryDayReading {
        RecoveryDayReading(
            date: calendar.startOfDay(for: day(d)), recovery: recovery, hrv: hrv, rhr: rhr, sleepHours: sleep, strain: nil
        )
    }

    // MARK: baseline

    func testBaselineAveragesTheSevenDaysBeforeToday() {
        // Days 17...23 count; today (24) and day 16 do not.
        let readings = [reading(16, recovery: 10, hrv: 10)]
            + (17 ... 23).map { reading($0, recovery: 60, hrv: 50, rhr: 55, sleep: 7) }
            + [reading(24, recovery: 99, hrv: 99)]
        let baseline = BodyHistory.baseline(readings, today: day(24), calendar: calendar)
        XCTAssertEqual(baseline.dayCount, 7)
        XCTAssertEqual(baseline.recovery, 60)
        XCTAssertEqual(baseline.hrv, 50)
        XCTAssertEqual(baseline.rhr, 55)
        XCTAssertEqual(baseline.sleepHours, 7)
    }

    func testTwoDaysAreNotABaseline() {
        let readings = [reading(22, hrv: 50), reading(23, hrv: 52)]
        let baseline = BodyHistory.baseline(readings, today: day(24), calendar: calendar)
        XCTAssertEqual(baseline.dayCount, 2)
        XCTAssertNil(baseline.recovery)
        XCTAssertNil(baseline.hrv)
    }

    func testEachReadingNeedsThreeDaysThatHaveIt() {
        // Recovery on three days, HRV on only two of them.
        let readings = [reading(21, hrv: 50), reading(22, hrv: 52), reading(23)]
        let baseline = BodyHistory.baseline(readings, today: day(24), calendar: calendar)
        XCTAssertEqual(baseline.recovery, 70)
        XCTAssertNil(baseline.hrv)
    }

    func testAnEmptyPlaceholderDayDoesNotPullTheBaselineDown() {
        // A day holding a score of 0 and nothing else is a day without data.
        let readings = [reading(20), reading(21), reading(22), reading(23, recovery: 0)]
        let baseline = BodyHistory.baseline(readings, today: day(24), calendar: calendar)
        XCTAssertEqual(baseline.dayCount, 3)
        XCTAssertEqual(baseline.recovery, 70)
    }

    // MARK: verdict

    func testWithinFivePercentIsTheSame() {
        XCTAssertEqual(BodyHistory.verdict(current: 52, baseline: 50, higherIsBetter: true), .same)
        XCTAssertEqual(BodyHistory.verdict(current: 48, baseline: 50, higherIsBetter: true), .same)
    }

    func testHigherIsBetterForHRVAndWorseForRestingHeartRate() {
        XCTAssertEqual(BodyHistory.verdict(current: 60, baseline: 50, higherIsBetter: true), .better)
        XCTAssertEqual(BodyHistory.verdict(current: 40, baseline: 50, higherIsBetter: true), .worse)
        XCTAssertEqual(BodyHistory.verdict(current: 60, baseline: 50, higherIsBetter: false), .worse)
        XCTAssertEqual(BodyHistory.verdict(current: 40, baseline: 50, higherIsBetter: false), .better)
    }

    func testAZeroBaselineSaysNothing() {
        XCTAssertEqual(BodyHistory.verdict(current: 5, baseline: 0, higherIsBetter: true), .same)
    }

    // MARK: against another day

    func testChangesAgainstYesterday() {
        let today = reading(24, recovery: 72, hrv: 48, sleep: 7.5)
        let yesterday = reading(23, recovery: 67, hrv: 50, sleep: 7.0)
        let changes = BodyHistory.changes(today: today, other: yesterday, kinds: [.recovery, .hrv, .sleep])
        XCTAssertEqual(changes.map(\.text), ["+5%", "-2 ms", "+0.5 h"])
        XCTAssertEqual(changes.map(\.verdict), [.better, .worse, .better])
    }

    func testAChangeThatRoundsToZeroIsTheSameAndHasNoSign() {
        let changes = BodyHistory.changes(
            today: reading(24, sleep: 7.04), other: reading(23, sleep: 7.0), kinds: [.sleep]
        )
        XCTAssertEqual(changes.first?.text, "0 h")
        XCTAssertEqual(changes.first?.verdict, .same)
    }

    func testAChangeOnlyAppearsWhenBothDaysMeasuredIt() {
        let changes = BodyHistory.changes(
            today: reading(24, hrv: 48), other: reading(23), kinds: [.recovery, .hrv, .sleep]
        )
        XCTAssertEqual(changes.map(\.kind), [.recovery])
    }

    func testNoComparisonWithoutTwoRealDays() {
        XCTAssertTrue(BodyHistory.changes(today: reading(24), other: nil, kinds: [.recovery]).isEmpty)
        XCTAssertTrue(BodyHistory.changes(today: nil, other: reading(23), kinds: [.recovery]).isEmpty)
        // A placeholder day (score 0, nothing else) is not a day to compare with.
        XCTAssertTrue(
            BodyHistory.changes(today: reading(24), other: reading(23, recovery: 0), kinds: [.recovery]).isEmpty
        )
    }

    func testFindingADayByCalendarDate() {
        let readings = [reading(17, recovery: 61), reading(23, recovery: 67)]
        let weekAgo = BodyHistory.day(7, before: day(24), calendar: calendar)
        XCTAssertEqual(weekAgo.flatMap { BodyHistory.reading(on: $0, in: readings, calendar: calendar) }?.recovery, 61)
        XCTAssertNil(BodyHistory.reading(on: day(20), in: readings, calendar: calendar))
    }

    // MARK: text

    func testSignedText() {
        XCTAssertEqual(BodyHistory.signed(5, decimals: 0, unit: "%"), "+5%")
        XCTAssertEqual(BodyHistory.signed(-2.4, decimals: 0, unit: " ms"), "-2 ms")
        XCTAssertEqual(BodyHistory.signed(0.04, decimals: 1, unit: " h"), "0 h")
        XCTAssertEqual(BodyHistory.signed(-0.04, decimals: 0, unit: "%"), "0%")
    }

    // MARK: sleep stages

    func testStagesNeedAtLeastOneMinute() {
        XCTAssertNil(SleepStageMinutes(deep: nil, rem: nil, light: nil, awake: nil))
        XCTAssertNil(SleepStageMinutes(deep: 0, rem: 0, light: 0, awake: 0))
        let stages = SleepStageMinutes(deep: 75, rem: 88, light: 195, awake: nil)
        XCTAssertEqual(stages?.total, 358)
        XCTAssertEqual(stages?.awake, 0)
    }

    func testStageMinutesRead() {
        XCTAssertEqual(SleepStageMinutes.formatted(425), "7h 5m")
        XCTAssertEqual(SleepStageMinutes.formatted(120), "2h")
        XCTAssertEqual(SleepStageMinutes.formatted(45), "45m")
        XCTAssertEqual(SleepStageMinutes.formatted(0), "0m")
    }
}
