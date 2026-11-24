//
// RecoveryPeriodTests.swift
// Tempo
//
// The maths behind the Recovery page's Week and Month views: which days belong
// to a period, what it averages, and when a failed refresh counts as an error.
//

@testable import Tempo
import XCTest

final class RecoveryPeriodTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    /// Wednesday 12:00, so "today" is mid-day and day starts are not special.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
    }

    override func setUp() {
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    private func day(
        _ offset: Int,
        recovery: Double = 70,
        hrv: Double? = 60,
        rhr: Double? = 50,
        sleep: Double? = 7.5,
        strain: Double? = 10
    ) -> RecoveryDayReading {
        let start = calendar.startOfDay(for: today)
        return RecoveryDayReading(
            date: calendar.date(byAdding: .day, value: -offset, to: start)!,
            recovery: recovery, hrv: hrv, rhr: rhr, sleepHours: sleep, strain: strain
        )
    }

    // MARK: Window

    func testWindowCountsCalendarDaysNotRows() {
        // Three recorded days spread over a month: a week holds only the one inside it.
        let readings = [day(1), day(10), day(20)]
        let week = RecoveryWindow.select(readings, days: 7, endingOn: today, calendar: calendar)
        XCTAssertEqual(week.count, 1)
        let month = RecoveryWindow.select(readings, days: 30, endingOn: today, calendar: calendar)
        XCTAssertEqual(month.count, 3)
    }

    func testWindowIncludesTodayAndTheSixDaysBefore() {
        let readings = (0 ... 8).map { day($0) }
        let week = RecoveryWindow.select(readings, days: 7, endingOn: today, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first?.date, day(6).date)
        XCTAssertEqual(week.last?.date, day(0).date)
    }

    func testWindowIsOldestFirst() {
        let readings = [day(0), day(3), day(1)]
        let week = RecoveryWindow.select(readings, days: 7, endingOn: today, calendar: calendar)
        XCTAssertEqual(week.map(\.date), [day(3).date, day(1).date, day(0).date])
    }

    func testAPlaceholderDayIsNotARedDay() {
        // Today's row exists with a score of 0 and nothing else until WHOOP answers.
        let placeholder = day(0, recovery: 0, hrv: nil, rhr: nil, sleep: nil, strain: nil)
        XCTAssertFalse(placeholder.hasReadings)
        let week = RecoveryWindow.select([placeholder, day(1)], days: 7, endingOn: today, calendar: calendar)
        XCTAssertEqual(week.count, 1)
    }

    func testAZeroScoreWithReadingsIsStillADay() {
        XCTAssertTrue(day(0, recovery: 0, hrv: 30).hasReadings)
    }

    func testPreviousWindowIsTheSameLengthJustBefore() {
        let readings = (0 ... 13).map { day($0) }
        let earlier = RecoveryWindow.previous(readings, days: 7, endingOn: today, calendar: calendar)
        XCTAssertEqual(earlier.count, 7)
        XCTAssertEqual(earlier.first?.date, day(13).date)
        XCTAssertEqual(earlier.last?.date, day(7).date)
    }

    func testZeroDaysSelectsNothing() {
        XCTAssertTrue(RecoveryWindow.select([day(0)], days: 0, endingOn: today, calendar: calendar).isEmpty)
    }

    // MARK: Stats

    func testStatsNeedAtLeastThreeDays() {
        XCTAssertNil(RecoveryPeriodStats.make(window: [day(0), day(1)]))
        XCTAssertNotNil(RecoveryPeriodStats.make(window: [day(0), day(1), day(2)]))
    }

    func testStatsAverageOnlyTheDaysThatHaveTheReading() {
        let window = [
            day(0, hrv: 40, sleep: 6), day(1, hrv: 60, sleep: nil), day(2, hrv: nil, sleep: 8),
        ]
        let stats = RecoveryPeriodStats.make(window: window)
        XCTAssertEqual(stats?.avgHRV, 50)
        XCTAssertEqual(stats?.avgSleep, 7)
    }

    func testStatsKeepAMissingVitalMissingInsteadOfZero() {
        let window = (0 ..< 3).map { day($0, hrv: nil, strain: nil) }
        let stats = RecoveryPeriodStats.make(window: window)
        XCTAssertNil(stats?.avgHRV)
        XCTAssertNil(stats?.avgStrain)
        XCTAssertEqual(stats?.totalStrain, 0)
    }

    func testStatsBestWorstAndZones() {
        let window = [
            day(0, recovery: 90), day(1, recovery: 20), day(2, recovery: 50), day(3, recovery: 70),
        ]
        let stats = RecoveryPeriodStats.make(window: window)
        XCTAssertEqual(stats?.best?.score, 90)
        XCTAssertEqual(stats?.worst?.score, 20)
        XCTAssertEqual(stats?.worst?.date, day(1).date)
        XCTAssertEqual(stats?.greenDays, 2)
        XCTAssertEqual(stats?.yellowDays, 1)
        XCTAssertEqual(stats?.redDays, 1)
        XCTAssertEqual(stats?.avgRecovery, 57.5)
    }

    func testStatsSumStrain() {
        let window = [day(0, strain: 8), day(1, strain: 12), day(2, strain: 10)]
        let stats = RecoveryPeriodStats.make(window: window)
        XCTAssertEqual(stats?.totalStrain, 30)
        XCTAssertEqual(stats?.avgStrain, 10)
    }

    func testPreviousAveragesNeedThreeDaysToo() {
        let window = (0 ..< 3).map { day($0) }
        XCTAssertNil(RecoveryPeriodStats.make(window: window, previous: [day(8)])?.previous)

        let earlier = [day(8, recovery: 40, hrv: 50), day(9, recovery: 60, hrv: 70), day(10, recovery: 80, hrv: nil)]
        let previous = RecoveryPeriodStats.make(window: window, previous: earlier)?.previous
        XCTAssertEqual(previous?.recovery, 60)
        // Two HRV readings are not enough to compare against.
        XCTAssertNil(previous?.hrv)
        XCTAssertEqual(previous?.rhr, 50)
    }

    // MARK: Load state

    func testSaveFailureIsAnError() {
        let state = RecoveryLoadResolver.resolve(
            isConnectedToRealData: false, fetchedAnything: false, todayHasReadings: true, saveFailed: true
        )
        guard case .error = state else {
            return XCTFail("expected an error, got \(state)")
        }
    }

    func testUnreachableWhoopWithNothingToShowIsAnError() {
        let state = RecoveryLoadResolver.resolve(
            isConnectedToRealData: true, fetchedAnything: false, todayHasReadings: false, saveFailed: false
        )
        guard case .error = state else {
            return XCTFail("expected an error, got \(state)")
        }
    }

    func testUnreachableWhoopWithStoredNumbersKeepsThem() {
        let state = RecoveryLoadResolver.resolve(
            isConnectedToRealData: true, fetchedAnything: false, todayHasReadings: true, saveFailed: false
        )
        XCTAssertEqual(state, .loaded)
    }

    func testNotConnectedIsNeverAnError() {
        // The "connect WHOOP" state is not a failure.
        let state = RecoveryLoadResolver.resolve(
            isConnectedToRealData: false, fetchedAnything: false, todayHasReadings: false, saveFailed: false
        )
        XCTAssertEqual(state, .loaded)
    }

    func testAnAnswerFromWhoopIsLoaded() {
        let state = RecoveryLoadResolver.resolve(
            isConnectedToRealData: true, fetchedAnything: true, todayHasReadings: true, saveFailed: false
        )
        XCTAssertEqual(state, .loaded)
    }

    // MARK: Balance

    func testBalanceReadsHardTrainingAndGoodRecovery() {
        XCTAssertTrue(RecoveryBalance.assessment(avgRecovery: 75, avgStrain: 13).hasPrefix("Great balance"))
    }

    func testBalanceWarnsWhenStrainOutpacesRecovery() {
        XCTAssertTrue(RecoveryBalance.assessment(avgRecovery: 40, avgStrain: 15).contains("outpacing"))
    }

    func testBalanceFallsBackToModerate() {
        XCTAssertTrue(RecoveryBalance.assessment(avgRecovery: 55, avgStrain: 11).hasPrefix("Moderate balance"))
    }
}
