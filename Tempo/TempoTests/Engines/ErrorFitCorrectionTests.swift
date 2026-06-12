//
// ErrorFitCorrectionTests.swift
// Tempo
//
// Step 3 (measure → correct) — proves the engine adapts to MEASURED error
// rather than a hand-tuned constant, and does so CONSERVATIVELY: a partial step
// toward the error-implied target, clamped, noise-banded. This is the
// "adapts correctly" half of the user's definition. Pure — no device/store.
//

@testable import Tempo
import XCTest

final class ErrorFitCorrectionTests: XCTestCase {

    private typealias U = AdaptiveProfileUpdater

    // MARK: - Direction

    func testTooEasyRaisesIncrement() {
        // Negative signed error = sessions easier than the ~8 target = under-loaded.
        let corrected = U.correctedIncrement(current: 2.5, meanSignedRPEError: -2.0)
        XCTAssertGreaterThan(corrected, 2.5, "Consistently too-easy → raise the step")
    }

    func testTooHardLowersIncrement() {
        let corrected = U.correctedIncrement(current: 5.0, meanSignedRPEError: 2.0)
        XCTAssertLessThan(corrected, 5.0, "Consistently too-hard → lower the step")
    }

    // MARK: - Conservative (partial, not full)

    func testCorrectionIsPartialNotFull() {
        // error −2.0 RPE, rpePerIncrement 2.0 → 1 increment of mis-load = 2.5kg
        // full correction. Gain 0.4 → applied = +1.0kg. NOT the full +2.5.
        let corrected = U.correctedIncrement(current: 2.5, meanSignedRPEError: -2.0)
        XCTAssertEqual(corrected, 3.5, accuracy: 0.01, "Only ~40% of the error-implied step applies per session")
    }

    func testSingleNoisySessionMovesLittle() {
        // A one-off −1.0 RPE blip moves the step only modestly, not a full jump.
        let corrected = U.correctedIncrement(current: 2.5, meanSignedRPEError: -1.0)
        let move = corrected - 2.5
        XCTAssertLessThan(move, 1.0, "A single noisy session must not swing the weight hard")
        XCTAssertGreaterThan(move, 0)
    }

    // MARK: - Noise band

    func testWithinNoiseBandNoChange() {
        let corrected = U.correctedIncrement(current: 4.0, meanSignedRPEError: 0.2)
        XCTAssertEqual(corrected, 4.0, accuracy: 0.0001, "Error inside the noise band → don't chase jitter")
    }

    // MARK: - Clamps hold

    func testCorrectionRespectsCeiling() {
        // Huge under-load error can't push the increment past the max.
        let corrected = U.correctedIncrement(current: U.maxIncrement, meanSignedRPEError: -20)
        XCTAssertLessThanOrEqual(corrected, U.maxIncrement)
    }

    func testCorrectionRespectsFloor() {
        let corrected = U.correctedIncrement(current: U.minIncrement, meanSignedRPEError: 20)
        XCTAssertGreaterThanOrEqual(corrected, U.minIncrement)
    }

    // MARK: - Convergence (the point of conservative correction)

    func testConvergesTowardTargetOverSessions() {
        // Simulate: the "true" right increment is ~5.0. Start at 2.5, and each
        // session the remaining under-load shows up as proportional negative
        // error. Conservative correction should climb toward ~5 and settle,
        // never overshooting wildly.
        var increment = 2.5
        let target = 5.0
        var prev = increment
        for i in 0 ..< 12 {
            // Error proportional to how far below target we still are (negative
            // = too easy), scaled into RPE space by rpePerIncrement.
            let misloadIncrements = (target - increment) / 2.5
            let signedError = -misloadIncrements * U.rpePerIncrement
            increment = U.correctedIncrement(current: increment, meanSignedRPEError: signedError)
            XCTAssertGreaterThanOrEqual(increment, prev - 0.0001, "Monotonic climb toward target (step \(i))")
            XCTAssertLessThanOrEqual(increment, target + 0.5, "Never wildly overshoots target")
            prev = increment
        }
        XCTAssertGreaterThan(increment, 4.0, "After 12 sessions it should be near the true target")
        XCTAssertLessThanOrEqual(increment, target + 0.5)
    }
}
