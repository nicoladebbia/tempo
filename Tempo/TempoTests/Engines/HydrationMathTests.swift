//
// HydrationMathTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class HydrationMathTests: XCTestCase {
    // 931 cal over 134 min (the real football session). Raw sweat:
    // 931 * 0.75 / 580 ≈ 1.204 L. Hourly cap: 1.0 * 134/60 ≈ 2.23 L → not
    // binding. Range = 1.204 ±20% ≈ 0.96 ... 1.44 L.
    func testFootballSessionRange() {
        let range = HydrationMath.sweatLossLitres(caloriesBurned: 931, durationMinutes: 134)
        let r = try! XCTUnwrap(range)
        XCTAssertEqual(r.lowerBound, 0.963, accuracy: 0.02)
        XCTAssertEqual(r.upperBound, 1.444, accuracy: 0.02)
    }

    func testFootballBonusMlUsesLowEnd() {
        let ml = HydrationMath.activityBonusMl(caloriesBurned: 931, durationMinutes: 134)
        // Low end ≈ 0.963 L → ~963 ml.
        XCTAssertEqual(Double(ml), 963, accuracy: 25)
    }

    // Short, very high-calorie burst must be capped to ~1 L/hr replacement.
    // 1200 cal in 20 min → raw ≈ 1.55 L, but cap = 1.0 * 20/60 ≈ 0.33 L.
    func testHourlyCapBinds() {
        let range = HydrationMath.sweatLossLitres(caloriesBurned: 1200, durationMinutes: 20)
        let r = try! XCTUnwrap(range)
        // Capped midpoint ≈ 0.333 L → upper ≈ 0.40 L, well under the raw 1.55.
        XCTAssertLessThan(r.upperBound, 0.45)
    }

    func testNoCaloriesReturnsNil() {
        XCTAssertNil(HydrationMath.sweatLossLitres(caloriesBurned: nil, durationMinutes: 90))
        XCTAssertNil(HydrationMath.sweatLossLitres(caloriesBurned: 0, durationMinutes: 90))
    }

    func testNoCaloriesBonusIsZero() {
        XCTAssertEqual(HydrationMath.activityBonusMl(caloriesBurned: nil, durationMinutes: 90), 0)
        XCTAssertEqual(HydrationMath.activityBonusMl(caloriesBurned: 0, durationMinutes: 90), 0)
    }

    func testElectrolyteThreshold() {
        XCTAssertTrue(HydrationMath.needsElectrolytes(1.2))
        XCTAssertFalse(HydrationMath.needsElectrolytes(0.6))
    }

    // Weather factor scales the estimate (future-proofing the hook).
    func testWeatherFactorScales() {
        let base = HydrationMath.sweatLossLitres(caloriesBurned: 800, durationMinutes: 90)!
        let hot = HydrationMath.sweatLossLitres(caloriesBurned: 800, durationMinutes: 90, weatherFactor: 1.2)!
        XCTAssertGreaterThan(hot.lowerBound, base.lowerBound)
    }
}
