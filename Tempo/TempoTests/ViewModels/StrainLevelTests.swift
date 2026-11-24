//
// StrainLevelTests.swift
// TempoTests
//
// One strain number gets one name on the Recovery page and the Body page.
//

@testable import Tempo
import XCTest

final class StrainLevelTests: XCTestCase {
    func testNamesFollowTheWhoopBands() {
        XCTAssertEqual(StrainLevel(strain: 0), .light)
        XCTAssertEqual(StrainLevel(strain: 4.9), .light)
        XCTAssertEqual(StrainLevel(strain: 5), .low)
        XCTAssertEqual(StrainLevel(strain: 9.99), .low)
        XCTAssertEqual(StrainLevel(strain: 10), .moderate)
        XCTAssertEqual(StrainLevel(strain: 13.9), .moderate)
        XCTAssertEqual(StrainLevel(strain: 14), .moderateHigh)
        XCTAssertEqual(StrainLevel(strain: 17.9), .moderateHigh)
        XCTAssertEqual(StrainLevel(strain: 18), .overreaching)
        XCTAssertEqual(StrainLevel(strain: 21), .overreaching)
    }

    func testNoReadingOrNonsenseGivesNoLevel() {
        XCTAssertNil(StrainLevel(strain: nil))
        XCTAssertNil(StrainLevel(strain: -1))
        XCTAssertNil(StrainLevel(strain: .nan))
    }

    func testDisplayNames() {
        XCTAssertEqual(StrainLevel.light.name, "Light")
        XCTAssertEqual(StrainLevel.moderateHigh.name, "Moderate-High")
        XCTAssertEqual(StrainLevel.overreaching.name, "Overreaching")
    }

    func testAdviceFollowsRecovery() {
        XCTAssertNil(StrainLevel.advice(recovery: nil))
        XCTAssertEqual(StrainLevel.advice(recovery: 80), "Push it")
        XCTAssertEqual(StrainLevel.advice(recovery: 79.9), "Moderate")
        XCTAssertEqual(StrainLevel.advice(recovery: 50), "Moderate")
        XCTAssertEqual(StrainLevel.advice(recovery: 49.9), "Take it easy")
    }
}
