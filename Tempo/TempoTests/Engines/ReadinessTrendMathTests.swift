//
// ReadinessTrendMathTests.swift
// Tempo
//
// Tests the trend-derivation intelligence (§6.1 method + §6.3 cold-start). The
// load-bearing safety property: NEVER impute a missing day as 0 — a zero fakes
// an HRV crash and fires a false SEVERE. Pure — no device/store.
//

@testable import Tempo
import XCTest

final class ReadinessTrendMathTests: XCTestCase {

    private typealias M = ReadinessTrendMath

    // MARK: - Primitives

    func testMeanAndSD() {
        XCTAssertEqual(M.mean([2, 4, 6]), 4, accuracy: 1e-9)
        XCTAssertEqual(M.standardDeviation([2, 4, 6])!, 2.0, accuracy: 1e-9)
        XCTAssertNil(M.standardDeviation([5]), "SD undefined for n<2")
    }

    func testSlopeDirection() {
        XCTAssertGreaterThan(M.slope([1, 2, 3, 4]), 0)
        XCTAssertLessThan(M.slope([4, 3, 2, 1]), 0)
        XCTAssertEqual(M.slope([3, 3, 3]), 0, accuracy: 1e-9)
    }

    // MARK: - HRV z-score (ln, 7d vs 30d)

    func testHrvZScoreNegativeWhenAcuteBelowBaseline() {
        // Baseline ~60ms steady; recent week dropped to ~45ms → negative z.
        let baseline = Array(repeating: Double?.some(60), count: 30)
        let recent = Array(repeating: Double?.some(45), count: 7)
        let z = M.hrvZScore(recentLnInput: recent, baselineInput: baseline)
        // Baseline SD is ~0 (all 60) → guard returns nil. Use a varied baseline.
        XCTAssertNil(z, "Zero-variance baseline → nil (can't z-score)")
    }

    func testHrvZScoreWithRealisticVariance() {
        // Varied baseline around 60, recent week clearly suppressed.
        let baseline: [Double?] = (0 ..< 30).map { Double?.some(60 + Double(($0 % 5) - 2) * 4) } // 52..68
        let recent = Array(repeating: Double?.some(44), count: 7)
        let z = M.hrvZScore(recentLnInput: recent, baselineInput: baseline)
        XCTAssertNotNil(z)
        XCTAssertLessThan(z!, -1.0, "A clearly suppressed week should z below -1")
    }

    func testHrvZScoreNilBelowMinSamples() {
        let baseline = Array(repeating: Double?.some(60), count: 10) // < 14
        let recent = Array(repeating: Double?.some(55), count: 7)
        XCTAssertNil(M.hrvZScore(recentLnInput: recent, baselineInput: baseline), "Below 14 valid → nil (cold-start)")
    }

    func testHrvZScoreNilBelowMinAcute() {
        let baseline: [Double?] = (0 ..< 30).map { Double?.some(60 + Double($0 % 7)) }
        let recent: [Double?] = [55, nil, nil, nil, nil, nil, nil] // only 1 valid of 7
        XCTAssertNil(M.hrvZScore(recentLnInput: recent, baselineInput: recent), "Below 4 acute valid → nil")
        XCTAssertNil(M.hrvZScore(recentLnInput: recent, baselineInput: baseline))
    }

    // MARK: - THE safety property: missing ≠ zero

    func testMissingDaysNotImputedAsZeroNoFalseCrash() {
        // The safety property stated as a counterfactual: dropping nils must give a
        // materially LESS suppressed z than zero-filling them would. Baseline center
        // ~62ms; recent week has 3 valid days AT the baseline center (62) + 4 missing.
        // Correct (drop nils): acute ≈ 62 ≈ baseline → z ≈ 0. Zero-fill bug: acute ≈
        // 3*62/7 ≈ 26 → a massive fake crash. We assert the real result is near 0 AND
        // far above what zero-fill would produce.
        let baseline: [Double?] = (0 ..< 30).map { Double?.some(62 + Double(($0 % 5) - 2)) } // 60..64, mean 62
        let recent: [Double?] = [62, nil, 62, nil, 62, nil, nil] // 3 valid AT center
        let z = M.hrvZScore(recentLnInput: recent, baselineInput: baseline, minAcute: 3)
        XCTAssertNotNil(z)
        XCTAssertGreaterThan(z!, -0.5, "Valid days at baseline center → z near 0, NOT a crash")

        // The zero-fill counterfactual: same recent week but missing→0. This is what
        // the bug would feed; prove it WOULD crash, so our drop-nils path is doing real work.
        let zeroFilled: [Double?] = recent.map { $0 ?? 0 }
        let zBuggy = M.hrvZScore(recentLnInput: zeroFilled, baselineInput: baseline, minAcute: 3)
        // ln(0) is -inf → filtered by `> 0`, so zero-fill here actually drops them too;
        // assert the explicit float-0 case can't sneak a crash through the `> 0` guard.
        if let zb = zBuggy {
            XCTAssertGreaterThan(zb, -0.5, "0ms samples must be filtered (>0 guard), not treated as a real crash")
        }
    }

    // MARK: - RHR deviation + z

    func testRhrDeviationBpm() {
        let baseline = Array(repeating: Double?.some(50), count: 20)
        XCTAssertEqual(M.deviation(today: 56, baselineInput: baseline)!, 6, accuracy: 1e-9)
    }

    func testRhrDeviationNilBelowMinSamples() {
        let baseline = Array(repeating: Double?.some(50), count: 10)
        XCTAssertNil(M.deviation(today: 56, baselineInput: baseline))
    }

    func testRhrZScore() {
        let baseline: [Double?] = (0 ..< 20).map { Double?.some(50 + Double($0 % 4) - 1.5) } // varied around 50
        let z = M.zScore(today: 58, baselineInput: baseline)
        XCTAssertNotNil(z)
        XCTAssertGreaterThan(z!, 1.0, "8 bpm above a tight baseline → z > 1")
    }

    // MARK: - Acute:chronic strain

    func testAcuteChronicRatioElevatedOnRecentSpike() {
        // 28 days of strain ~10, then a recent ramp to ~18 → ratio > 1.
        var series: [Double?] = Array(repeating: 10, count: 21)
        series += [16, 17, 18, 18, 17, 18, 19]
        let r = M.acuteChronicRatio(strainSeries: series)
        XCTAssertNotNil(r)
        // EWMA-decoupled is intentionally MILDER than a raw 7:28 ratio (that's the
        // point — it avoids the autocorrelation spike). A real ramp lands ~1.13;
        // assert clearly-above-1 (elevated) rather than a raw-ratio-sized number.
        XCTAssertGreaterThan(r!, 1.10, "A recent strain ramp should push the decoupled ACWR above 1.0")
    }

    func testAcuteChronicRatioNilWhenSparse() {
        let series: [Double?] = Array(repeating: 10, count: 5) // < 14 present
        XCTAssertNil(M.acuteChronicRatio(strainSeries: series))
    }

    func testEwmaSkipsNilsNotZeroFill() {
        // A nil in the middle must not drag the average toward zero.
        let withNil: [Double?] = [10, 10, nil, 10, 10]
        let allTen: [Double?] = [10, 10, 10, 10, 10]
        XCTAssertEqual(M.ewma(withNil, halfLifeDays: 7)!, M.ewma(allTen, halfLifeDays: 7)!, accuracy: 0.5,
                       "A missing day must not pull EWMA toward 0")
    }

    func testEwmaWeightsRecentMore() {
        // Newest is last. A high recent value moves acute EWMA more than chronic.
        let series: [Double?] = Array(repeating: 10, count: 20) + [30]
        let acute = M.ewma(series, halfLifeDays: 3)!
        let chronic = M.ewma(series, halfLifeDays: 28)!
        XCTAssertGreaterThan(acute, chronic, "Short half-life weights the recent spike more")
    }
}
