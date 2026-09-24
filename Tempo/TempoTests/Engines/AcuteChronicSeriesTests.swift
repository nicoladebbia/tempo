//
// AcuteChronicSeriesTests.swift
// Tempo
//
// The Progress training-load chart must plot exactly what the readiness brain
// saw each day: the last point equals acuteChronicRatio over the same window.
//

@testable import Tempo
import XCTest

final class AcuteChronicSeriesTests: XCTestCase {
    func testLastPointMatchesSingleDayRatio() {
        let strain: [Double?] = (0 ..< 60).map { Double(8 + $0 % 7) }
        let series = ReadinessTrendMath.acuteChronicSeries(strainByDay: strain, days: 28)
        XCTAssertEqual(series.count, 28)
        let expected = ReadinessTrendMath.acuteChronicRatio(strainSeries: Array(strain.suffix(30)))
        XCTAssertEqual(series.last ?? nil, expected)
    }

    func testSparseHistoryYieldsNil() {
        let strain: [Double?] = Array(repeating: nil, count: 50) + [10, 12, 9]
        XCTAssertTrue(ReadinessTrendMath.acuteChronicSeries(strainByDay: strain, days: 10).allSatisfy { $0 == nil })
    }

    func testRampShowsRisingRatio() {
        let steady: [Double?] = Array(repeating: 8, count: 40)
        let ramp: [Double?] = (1 ... 10).map { 8 + Double($0) * 1.5 }
        let series = ReadinessTrendMath.acuteChronicSeries(strainByDay: steady + ramp, days: 10).compactMap { $0 }
        XCTAssertEqual(series.count, 10)
        XCTAssertGreaterThan(series.last ?? 0, series.first ?? 0)
        XCTAssertGreaterThan(series.last ?? 0, 1.0)
    }

    func testShortInputAndZeroDays() {
        XCTAssertEqual(ReadinessTrendMath.acuteChronicSeries(strainByDay: [1, 2], days: 5).count, 2)
        XCTAssertTrue(ReadinessTrendMath.acuteChronicSeries(strainByDay: [1, 2], days: 0).isEmpty)
    }
}
