//
// ChartScaleTests.swift
// TempoTests
//

@testable import Tempo
import XCTest

final class ChartScaleTests: XCTestCase {
    func testNoValuesGiveNoRange() {
        XCTAssertNil(ChartScale.fitted([]))
        XCTAssertNil(ChartScale.fitted([.nan, .infinity]))
    }

    func testRangeHoldsEveryValueWithRoomAround() throws {
        let range = try XCTUnwrap(ChartScale.fitted([81.0, 82.0, 83.0]))
        XCTAssertLessThan(range.lowerBound, 81)
        XCTAssertGreaterThan(range.upperBound, 83)
        // A 2 kg change must fill most of the chart, not sit in a sliver of 0 to 100.
        XCTAssertLessThan(range.upperBound - range.lowerBound, 5)
    }

    func testFlatSeriesGetsASmallBandAroundIt() throws {
        let range = try XCTUnwrap(ChartScale.fitted([70, 70, 70]))
        XCTAssertLessThan(range.lowerBound, 70)
        XCTAssertGreaterThan(range.upperBound, 70)
        XCTAssertLessThan(range.upperBound - range.lowerBound, 10)
    }

    func testSingleValueIsCentred() throws {
        let range = try XCTUnwrap(ChartScale.fitted([14.5]))
        XCTAssertEqual((range.lowerBound + range.upperBound) / 2, 14.5, accuracy: 0.0001)
    }

    func testPositiveValuesNeverDipBelowZero() throws {
        let range = try XCTUnwrap(ChartScale.fitted([0.4, 0.6]))
        XCTAssertGreaterThanOrEqual(range.lowerBound, 0)
    }

    func testNegativeValuesAreAllowedBelowZero() throws {
        let range = try XCTUnwrap(ChartScale.fitted([-2, 1]))
        XCTAssertLessThan(range.lowerBound, -2)
    }
}
