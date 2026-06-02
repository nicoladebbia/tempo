//
// TDEEGoalWeightTests.swift
// Tempo
//
// §1 goal-weight guard — the rate-vs-enum double-count trap. When a goal
// weight + weekly rate are set, the rate sets the deficit/surplus MAGNITUDE
// and REPLACES the cut/gain/maintain enum offset. They must never stack, or
// the deficit double-counts (the same bug class as the carryover overlap).
// These pin: rate mode replaces (not adds to) the enum, direction follows
// goal-vs-current, at-goal = maintain, and safety rails still clamp.
//

@testable import Tempo
import XCTest

final class TDEEGoalWeightTests: XCTestCase {

    private func calc(
        goal: DietaryGoal,
        currentKg: Double = 82,
        goalKg: Double? = nil,
        rate: Double? = nil
    ) -> TDEEResult {
        TDEECalculator.calculate(
            weightKg: currentKg,
            heightCm: 183,
            age: 22,
            biologicalSex: .male,
            bodyFatPercent: 14,
            trainingFrequency: 5,
            whoopAverageTDEE: nil,
            goal: goal,
            goalWeightKg: goalKg,
            weeklyRateKg: rate
        )
    }

    // MARK: - Rate REPLACES the enum (no double-count)

    func testRateModeDoesNotStackWithEnumOffset() {
        // Same goal (cut) and same current weight; one with rate, one without.
        // The rate-mode deficit must be exactly the rate-derived amount off the
        // TDEE — NOT the enum offset PLUS the rate. We assert rate-mode lands
        // at tdee - (0.5*7700/7 ≈ 550), independent of the enum's -300..-500.
        let r = calc(goal: .cut, currentKg: 82, goalKg: 78, rate: 0.5)
        let expectedDailyDeficit = 0.5 * 7700.0 / 7.0 // ≈ 550
        let expected = Int((r.tdee - expectedDailyDeficit).rounded())
        XCTAssertEqual(r.adjustedCalories, expected,
                       "Rate mode must use ONLY the rate-derived deficit, not enum+rate")
    }

    func testEnumModeUnchangedWhenNoRate() {
        // No goal weight / rate → legacy enum offset path. For cut at BF 14
        // (≤15) the conservative-cut offset is -300. adjustedCalories should
        // be tdee - 300 (within the safety rails, which don't bind here).
        let r = calc(goal: .cut)
        let expected = Int((r.tdee - 300).rounded())
        XCTAssertEqual(r.adjustedCalories, expected,
                       "With no rate, the enum offset path is unchanged (regression guard)")
    }

    // MARK: - Direction follows goal vs current, not the enum

    func testDirectionIsDeficitWhenGoalBelowCurrent() {
        let r = calc(goal: .cut, currentKg: 82, goalKg: 75, rate: 0.5)
        XCTAssertLessThan(r.adjustedCalories, Int(r.tdee.rounded()),
                          "Goal below current → deficit")
    }

    func testDirectionIsSurplusWhenGoalAboveCurrent() {
        let r = calc(goal: .leanGain, currentKg: 75, goalKg: 82, rate: 0.5)
        XCTAssertGreaterThan(r.adjustedCalories, Int(r.tdee.rounded()),
                             "Goal above current → surplus")
    }

    func testAtGoalWeightIsMaintenance() {
        // Within 0.25 kg of goal → no adjustment regardless of the enum.
        let r = calc(goal: .cut, currentKg: 80, goalKg: 80.1, rate: 0.5)
        XCTAssertEqual(r.adjustedCalories, Int(r.tdee.rounded()),
                       "At goal weight → maintain, no deficit applied")
    }

    // MARK: - Safety rails still clamp an aggressive rate

    func testAggressiveRateIsClampedToMaxDeficit() {
        // A 0.75 kg/wk deficit (~825 kcal) on a modest TDEE could exceed the
        // 25% floor; the result must never drop below tdee * 0.75.
        let r = calc(goal: .cut, currentKg: 60, goalKg: 50, rate: 0.75)
        XCTAssertGreaterThanOrEqual(Double(r.adjustedCalories), r.tdee * 0.75 - 1,
                                    "Deficit must be clamped to the 25% safety floor")
    }
}
