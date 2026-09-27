//
// HeartRateZoneCalculatorTests.swift
// Tempo
//
// Apple Watch run mode §2 — Z1-Z5 zone math, and the max-HR resolution order
// (athlete override > age estimate > generic default).
//

@testable import Tempo
import XCTest

final class HeartRateZoneCalculatorTests: XCTestCase {
    // MARK: - Max HR resolution

    func testMaxHeartRatePrefersOverrideOverAge() {
        XCTAssertEqual(HeartRateZoneCalculator.maxHeartRate(age: 20, override: 200), 200)
    }

    func testMaxHeartRateFallsBackToAgeEstimate() {
        XCTAssertEqual(HeartRateZoneCalculator.maxHeartRate(age: 20, override: nil), 200)
        XCTAssertEqual(HeartRateZoneCalculator.estimatedMaxHeartRate(age: 20), 200)
    }

    func testMaxHeartRateFallsBackToGenericDefaultWithNeither() {
        XCTAssertEqual(HeartRateZoneCalculator.maxHeartRate(age: nil, override: nil), 190, "220 - 30 generic default")
    }

    func testZeroOrNegativeOverrideIsIgnored() {
        XCTAssertEqual(HeartRateZoneCalculator.maxHeartRate(age: 20, override: 0), 200)
        XCTAssertEqual(HeartRateZoneCalculator.maxHeartRate(age: 20, override: -5), 200)
    }

    // MARK: - Zone bands (max = 200 for round numbers)

    func testZoneBands() {
        let max: Double = 200
        XCTAssertEqual(HeartRateZoneCalculator.zone(bpm: 100, maxHeartRate: max), 1, "50% -> Z1")
        XCTAssertEqual(HeartRateZoneCalculator.zone(bpm: 119, maxHeartRate: max), 1, "59.5% -> still Z1")
        XCTAssertEqual(HeartRateZoneCalculator.zone(bpm: 120, maxHeartRate: max), 2, "60% -> Z2")
        XCTAssertEqual(HeartRateZoneCalculator.zone(bpm: 140, maxHeartRate: max), 3, "70% -> Z3")
        XCTAssertEqual(HeartRateZoneCalculator.zone(bpm: 160, maxHeartRate: max), 4, "80% -> Z4")
        XCTAssertEqual(HeartRateZoneCalculator.zone(bpm: 180, maxHeartRate: max), 5, "90% -> Z5")
        XCTAssertEqual(HeartRateZoneCalculator.zone(bpm: 200, maxHeartRate: max), 5, "100% -> Z5")
    }

    func testZoneIsNilForInvalidInput() {
        XCTAssertNil(HeartRateZoneCalculator.zone(bpm: 0, maxHeartRate: 200))
        XCTAssertNil(HeartRateZoneCalculator.zone(bpm: -5, maxHeartRate: 200))
        XCTAssertNil(HeartRateZoneCalculator.zone(bpm: 140, maxHeartRate: 0))
    }

    func testZoneLabel() {
        XCTAssertEqual(HeartRateZoneCalculator.zoneLabel(3), "Z3")
        XCTAssertEqual(HeartRateZoneCalculator.zoneLabel(nil), "—")
    }
}
