//
// PredictionHoldoutTests.swift
// Tempo
//
// Step 4 (hold-out honesty check) — the test that can embarrass the system, and
// the one that converts "it's intelligent" from a claim into a measurement.
// Proves the comparison correctly reports whether the personalized engine beats
// the dumb generic baseline on prediction error — including the case where it
// LOSES. Pure — no device/store.
//

@testable import Tempo
import XCTest

final class PredictionHoldoutTests: XCTestCase {

    /// Build a resolved row. `predictedRPE` fixed at 8 (the target).
    /// `actualRPE` / `actualWeight` are the observed outcome at the personalized
    /// weight; `baselineWeight` is what generic would have prescribed.
    private func row(
        predictedRPE: Double = 8.0,
        actualRPE: Double,
        actualWeight: Double,
        baselineWeight: Double?
    ) -> PredictionLog {
        let log = PredictionLog(
            exerciseID: UUID(),
            workoutPlanID: UUID(),
            predictedWeight: actualWeight,
            predictedReps: 8,
            predictedRPE: predictedRPE,
            signalUsedRaw: ProgressionReason.standardProgression.rawValue,
            baselineWeight: baselineWeight
        )
        log.actualRPE = actualRPE
        log.actualWeight = actualWeight
        log.outcomeResolved = true
        return log
    }

    // MARK: - Baseline estimate math

    func testBaselineEstimateHeavierReadsHarder() {
        // Personalized nailed it: actual RPE 8.0 at 100kg, predicted 8.0 → err 0.
        // Baseline would have prescribed 105kg (2 increments heavier) → estimated
        // RPE = 8.0 + 2*2.0 = 12 → baseline error = 12 − 8 = +4.
        let r = row(actualRPE: 8.0, actualWeight: 100, baselineWeight: 105)
        XCTAssertEqual(r.rpeError!, 0.0, accuracy: 0.001)
        XCTAssertEqual(r.baselineRPEErrorEstimate!, 4.0, accuracy: 0.001,
                       "Heavier baseline → larger projected error")
    }

    func testBaselineEstimateNilWithoutBaseline() {
        let r = row(actualRPE: 8.0, actualWeight: 100, baselineWeight: nil)
        XCTAssertNil(r.baselineRPEErrorEstimate)
    }

    // MARK: - Verdict

    func testPersonalizedWinsWhenMoreAccurate() {
        // Personalized lands near target (err ~0); baseline would have been way
        // off (heavier → big projected error). Personalized should WIN.
        let logs = (0 ..< 5).map { _ in
            row(actualRPE: 8.0, actualWeight: 100, baselineWeight: 110)
        }
        let result = PredictionAccuracy.holdout(logs)
        XCTAssertEqual(result.verdict, .personalizedWins)
        XCTAssertLessThan(result.personalizedMeanAbsError, result.baselineMeanAbsError)
    }

    func testBaselineWinsWhenPersonalizedIsWorse() {
        // Personalized missed badly (actual 9.5 vs target 8 → err 1.5), while the
        // baseline weight equals the actual weight → baseline estimate == same
        // 1.5... so make baseline LIGHTER so its projected error is smaller.
        // Baseline 95kg (2 lighter) → est RPE = 9.5 + (−2)*2 = 5.5 → err −2.5,
        // abs 2.5 > personalized 1.5? No — flip it: personalized must be WORSE.
        // Personalized err 1.5 (abs 1.5). Baseline lighter by 0.25 incr → est
        // err = 9.5 + (−0.25*2) − 8 = 1.0 (abs 1.0) < 1.5 → baseline wins.
        let logs = (0 ..< 5).map { _ in
            row(actualRPE: 9.5, actualWeight: 100, baselineWeight: 99.375)
        }
        let result = PredictionAccuracy.holdout(logs)
        XCTAssertEqual(result.verdict, .baselineWins,
                       "When personalized error exceeds baseline's, the check must say so honestly")
    }

    func testTieWhenWithinNoise() {
        // Baseline weight == actual weight → baseline estimate == personalized
        // error exactly → delta 0 → tie.
        let logs = (0 ..< 5).map { _ in
            row(actualRPE: 8.5, actualWeight: 100, baselineWeight: 100)
        }
        let result = PredictionAccuracy.holdout(logs)
        XCTAssertEqual(result.verdict, .tie, "No measurable advantage → honest tie, not a win")
    }

    func testInsufficientBelowMinWindow() {
        let logs = [row(actualRPE: 8, actualWeight: 100, baselineWeight: 105)]
        XCTAssertEqual(PredictionAccuracy.holdout(logs).verdict, .insufficient)
    }

    func testRowsWithoutBaselineExcluded() {
        // 5 rows but only 2 have a baseline → below minWindow → insufficient.
        var logs = (0 ..< 3).map { _ in row(actualRPE: 8, actualWeight: 100, baselineWeight: nil) }
        logs += (0 ..< 2).map { _ in row(actualRPE: 8, actualWeight: 100, baselineWeight: 105) }
        XCTAssertEqual(PredictionAccuracy.holdout(logs).verdict, .insufficient,
                       "Only rows with a baseline estimate count toward the hold-out")
    }
}
