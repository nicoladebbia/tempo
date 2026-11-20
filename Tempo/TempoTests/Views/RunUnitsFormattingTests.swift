//
// RunUnitsFormattingTests.swift
// Tempo
//
// Run surfaces follow one km/mi rule (lbs → miles) and typed run numbers
// accept "," decimals.
//

@testable import Tempo
import XCTest

final class RunUnitsFormattingTests: XCTestCase {
    func testUseMilesFollowsWeightUnitThenLocale() {
        XCTAssertTrue(GuidedRunFormatting.useMiles(weightUnit: .lbs))
        XCTAssertFalse(GuidedRunFormatting.useMiles(weightUnit: .kg, locale: Locale(identifier: "en_US")))
        XCTAssertTrue(GuidedRunFormatting.useMiles(weightUnit: nil, locale: Locale(identifier: "en_US")))
        XCTAssertFalse(GuidedRunFormatting.useMiles(weightUnit: nil, locale: Locale(identifier: "it_IT")))
    }

    func testTotalDistanceInEachUnit() {
        XCTAssertEqual(GuidedRunFormatting.totalDistance(meters: 12_400, useMiles: false), "12.4 km")
        XCTAssertEqual(GuidedRunFormatting.totalDistance(meters: 16_093.44, useMiles: true), "10.0 mi")
    }

    func testPaceConvertsToMiles() {
        XCTAssertEqual(GuidedRunFormatting.pace(secondsPerKm: 300, useMiles: false), "5:00/km")
        XCTAssertEqual(GuidedRunFormatting.pace(secondsPerKm: 300, useMiles: true), "8:03/mi")
    }

    func testConditioningRepTimesAcceptCommaAndQuoteMark() {
        XCTAssertEqual(ConditioningLogSheet.parseSeconds("58,5"), 58.5)
        XCTAssertEqual(ConditioningLogSheet.parseSeconds("1:05,5"), 65.5)
        XCTAssertEqual(ConditioningLogSheet.parseSeconds("58\""), 58)
        XCTAssertNil(ConditioningLogSheet.parseSeconds("abc"))
    }
}
