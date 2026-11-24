//
// BodyProgressTests.swift
// Tempo
//
// The Body progress page's trend maths: which daily snapshots are real
// measurements, the series per metric, and the fitted trend.
//

@testable import Tempo
import XCTest

final class BodyProgressTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    private func day(_ d: Int, hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    private func snapshot(
        _ d: Int, measured: Int? = nil, kg: Double? = nil, fat: Double? = nil, lean: Double? = nil
    ) -> BodySnapshot {
        BodySnapshot(
            date: day(d), measurementDate: measured.map { day($0, hour: 6) },
            weightKg: kg, bodyFatPercent: fat, leanMassKg: lean
        )
    }

    // MARK: measurements

    func testASnapshotThatCopiesAnOldReadingIsNotANewMeasurement() {
        // Weighed in on the 3rd; the 4th and 5th just carry that reading forward.
        let snapshots = [snapshot(3, measured: 3, kg: 80), snapshot(4, measured: 3, kg: 80), snapshot(5, measured: 3, kg: 80)]
        let measurements = BodyProgress.measurements(from: snapshots, calendar: calendar)
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements.first?.date, calendar.startOfDay(for: day(3)))
    }

    func testTheNewestCopyOfADaysMeasurementWins() {
        let snapshots = [snapshot(3, measured: 3, kg: 80, fat: nil), snapshot(4, measured: 3, kg: 80, fat: 18)]
        let measurements = BodyProgress.measurements(from: snapshots, calendar: calendar)
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements.first?.bodyFatPercent, 18)
    }

    func testASnapshotWithoutAMeasurementDateCountsOnItsOwnDay() {
        let measurements = BodyProgress.measurements(from: [snapshot(3, kg: 80), snapshot(4, kg: 79.5)], calendar: calendar)
        XCTAssertEqual(measurements.map(\.weightKg), [80, 79.5])
    }

    func testImplausibleReadingsAreDroppedPerMetric() {
        // A 0 kg scale glitch and a 150% body fat must not reach a chart.
        let snapshots = [snapshot(3, kg: 0, fat: 150, lean: 62), snapshot(4, kg: 80, fat: 18, lean: 62)]
        let measurements = BodyProgress.measurements(from: snapshots, calendar: calendar)
        XCTAssertEqual(measurements.count, 2)
        XCTAssertNil(measurements[0].weightKg)
        XCTAssertNil(measurements[0].bodyFatPercent)
        XCTAssertEqual(measurements[0].leanMassKg, 62)
    }

    func testADayWithNothingLeftIsDropped() {
        XCTAssertTrue(BodyProgress.measurements(from: [snapshot(3, kg: 0), snapshot(4)], calendar: calendar).isEmpty)
    }

    func testMeasurementsComeOldestFirst() {
        let measurements = BodyProgress.measurements(from: [snapshot(9, kg: 79), snapshot(2, kg: 80)], calendar: calendar)
        XCTAssertEqual(measurements.map(\.weightKg), [80, 79])
    }

    // MARK: series

    func testSeriesKeepsOnlyTheMetricAndTheWindow() {
        let measurements = BodyProgress.measurements(
            from: [snapshot(1, kg: 82, fat: 20), snapshot(10, kg: 80), snapshot(14, kg: 79, fat: 18)], calendar: calendar
        )
        let now = day(14, hour: 12)
        let weight = BodyProgress.series(.weight, from: measurements, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(weight.map(\.value), [80, 79])
        let fat = BodyProgress.series(.bodyFat, from: measurements, days: nil, now: now, calendar: calendar)
        XCTAssertEqual(fat.map(\.value), [20, 18])
    }

    // MARK: trend

    private func points(_ values: [(day: Int, kg: Double)]) -> [BodyProgress.Point] {
        values.map { BodyProgress.Point(date: calendar.startOfDay(for: day($0.day)), value: $0.kg) }
    }

    func testAWeekAcrossTheSpringClockChangeStillCountsAsAWeek() throws {
        // Europe/Rome puts its clocks forward on 2026-03-29: 25 Mar to 1 Apr is 7
        // calendar days but one hour short of 7 x 24 h in seconds.
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Rome"))
        func at(_ month: Int, _ d: Int) -> Date {
            rome.date(from: DateComponents(year: 2026, month: month, day: d))!
        }
        let points = [
            BodyProgress.Point(date: at(3, 25), value: 80),
            BodyProgress.Point(date: at(3, 28), value: 79.8),
            BodyProgress.Point(date: at(4, 1), value: 79.6),
        ]
        XCTAssertNotNil(BodyProgress.trend(of: points, calendar: rome)?.weeklyRate)

        // Six calendar days is still not a week.
        let short = [
            BodyProgress.Point(date: at(3, 25), value: 80),
            BodyProgress.Point(date: at(3, 28), value: 79.8),
            BodyProgress.Point(date: at(3, 31), value: 79.6),
        ]
        XCTAssertNil(BodyProgress.trend(of: short, calendar: rome)?.weeklyRate)
    }

    func testNoPointsMeansNoTrend() {
        XCTAssertNil(BodyProgress.trend(of: []))
    }

    func testOneOrTwoReadingsGiveTheLatestButNoTrend() {
        let trend = BodyProgress.trend(of: points([(1, 80), (10, 79)]))
        XCTAssertEqual(trend?.latest.value, 79)
        XCTAssertNil(trend?.fittedChange)
        XCTAssertNil(trend?.weeklyRate)
    }

    func testReadingsWithinAWeekGiveNoTrend() {
        let trend = BodyProgress.trend(of: points([(1, 80), (3, 79.8), (5, 79.6)]))
        XCTAssertEqual(trend?.pointCount, 3)
        XCTAssertNil(trend?.fittedChange)
    }

    func testAStraightLineGivesItsExactSlope() {
        // 0.5 kg lost every 7 days, over 21 days.
        let trend = BodyProgress.trend(of: points([(1, 80), (8, 79.5), (15, 79), (22, 78.5)]))
        XCTAssertEqual(trend?.weeklyRate ?? 0, -0.5, accuracy: 1e-9)
        XCTAssertEqual(trend?.fittedChange ?? 0, -1.5, accuracy: 1e-9)
        XCTAssertEqual(trend?.first.value, 80)
        XCTAssertEqual(trend?.latest.value, 78.5)
    }

    func testOneNoisyReadingDoesNotMakeTheTrend() {
        // A water-weight spike on the last day: last minus first would say +1.2 kg gained.
        let trend = BodyProgress.trend(of: points([(1, 80), (5, 79.8), (9, 79.6), (13, 79.4), (17, 79.2), (21, 81.2)]))
        XCTAssertNotNil(trend?.fittedChange)
        XCTAssertLessThan(trend?.fittedChange ?? 99, 1.2)
    }

    func testPointsAreSortedBeforeTheTrendIsRead() {
        let trend = BodyProgress.trend(of: points([(22, 78.5), (1, 80), (15, 79), (8, 79.5)]))
        XCTAssertEqual(trend?.first.value, 80)
        XCTAssertEqual(trend?.latest.value, 78.5)
    }

    func testSlopeNeedsTwoDistinctDays() {
        XCTAssertNil(BodyProgress.leastSquaresSlope(points([(1, 80)])))
        XCTAssertNil(BodyProgress.leastSquaresSlope(points([(1, 80), (1, 81)])))
    }

    // MARK: direction

    func testAFlatLineIsSteady() {
        let trend = BodyProgress.trend(of: points([(1, 80), (8, 80.1), (15, 80), (22, 80.1)]))
        XCTAssertEqual(trend.flatMap(BodyProgress.direction(of:)), .steady)
    }

    func testARateThatWouldShowAsZeroPointZeroIsSteady() {
        // 0.04 kg a week shows as "0.0": not "up".
        let trend = BodyProgress.trend(of: points([(1, 80), (8, 80.04), (15, 80.08), (22, 80.12)]))
        XCTAssertEqual(trend.flatMap(BodyProgress.direction(of:)), .steady)
    }

    func testClearMovementHasADirection() {
        let down = BodyProgress.trend(of: points([(1, 80), (8, 79.5), (15, 79), (22, 78.5)]))
        XCTAssertEqual(down.flatMap(BodyProgress.direction(of:)), .down)
        let up = BodyProgress.trend(of: points([(1, 78.5), (8, 79), (15, 79.5), (22, 80)]))
        XCTAssertEqual(up.flatMap(BodyProgress.direction(of:)), .up)
    }

    func testWithoutARateThereIsNoDirection() throws {
        let trend = try XCTUnwrap(BodyProgress.trend(of: points([(1, 80), (3, 79)])))
        XCTAssertNil(BodyProgress.direction(of: trend))
    }

    // MARK: display

    func testWeightAndLeanMassConvertToPoundsButBodyFatStaysAPercent() {
        XCTAssertEqual(BodyProgress.displayNumber(80, metric: .weight, unit: .kg), "80")
        XCTAssertEqual(BodyProgress.displayNumber(80, metric: .weight, unit: .lbs), "176.4")
        XCTAssertEqual(BodyProgress.displayNumber(65.7, metric: .leanMass, unit: .kg), "65.7")
        XCTAssertEqual(BodyProgress.displayNumber(18.1, metric: .bodyFat, unit: .lbs), "18.1")
        XCTAssertEqual(BodyProgress.unitLabel(metric: .weight, unit: .lbs), "lbs")
        XCTAssertEqual(BodyProgress.unitLabel(metric: .leanMass, unit: .kg), "kg")
        XCTAssertEqual(BodyProgress.unitLabel(metric: .bodyFat, unit: .lbs), "%")
    }
}
