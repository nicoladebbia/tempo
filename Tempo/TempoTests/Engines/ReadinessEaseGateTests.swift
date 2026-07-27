//
// ReadinessEaseGateTests.swift
// Tempo
//
// Pins `ReadinessPicture.easeCrossTrainingToday` — the rich-signal gate that
// steps a HARD cross-training day (conditioning/sprint/tempo run) down to an
// easy flush on the DETERMINISTIC path (cold-start first-30-days + offline/402).
// It uses recovery NUMBER + acute:chronic strain + HRV trend, NOT a 3-bucket,
// so variety intensity tracks recovery before the daily brain is eligible.
//

@testable import Tempo
import XCTest

final class ReadinessEaseGateTests: XCTestCase {

    /// Full-field builder; the three gate inputs are the parameters.
    private func picture(recovery: Double, acwr: Double? = 1.0, hrvTrend: TrendDirection = .flat) -> ReadinessPicture {
        ReadinessPicture(
            recoveryScore: recovery, hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: 0, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: 0, hrvTrend7d: hrvTrend, rhrDeltaBpm: 0, rhrZScore: 0,
            respDeltaBrMin: 0, acuteChronicStrainRatio: acwr, yesterdaySessions: [],
            weightKg: 80, bodyFatPct: 12, leanMassKg: 68, checkIn: nil,
            daysUntilNextMatch: nil, validBaselineSampleCount: 30, historyDayCount: 30
        )
    }

    func testGreenFreshDayKeepsHardCrossTraining() {
        XCTAssertFalse(picture(recovery: 80).easeCrossTrainingToday,
                       "A fresh green day keeps the hard conditioning as planned")
    }

    func testRedRecoveryNumberEases() {
        XCTAssertTrue(picture(recovery: 44).easeCrossTrainingToday,
                      "Recovery below 50 (the NUMBER, not a bucket) eases to a flush")
    }

    func testAcuteLoadSpikeEasesEvenWhenRecoveryLooksOkay() {
        // Recovery 70 alone would pass; a >1.5 acute:chronic strain ratio (the
        // overreaching zone) still eases — this is the signal a bucket misses.
        XCTAssertTrue(picture(recovery: 70, acwr: 1.7).easeCrossTrainingToday,
                      "An acute load spike eases even on a middling-good recovery")
    }

    func testFallingHrvTrendEasesOnlyWhenNotGenuinelyFresh() {
        XCTAssertTrue(picture(recovery: 60, hrvTrend: .falling).easeCrossTrainingToday,
                      "Declining HRV + not-fresh (recovery < 67) eases")
        XCTAssertFalse(picture(recovery: 80, hrvTrend: .falling).easeCrossTrainingToday,
                       "Declining HRV on a genuinely fresh day (recovery ≥ 67) does NOT ease")
    }

    func testMissingAcwrDoesNotCrashAndDoesNotEaseAlone() {
        XCTAssertFalse(picture(recovery: 75, acwr: nil).easeCrossTrainingToday,
                       "No strain-ratio data on a good day is a pass-through, not an ease")
    }
}
