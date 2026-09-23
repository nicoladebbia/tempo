//
// TrainingSafetyFloorTests.swift
// Tempo
//
// Adversarial tests for the deterministic safety floor (docs/INTELLIGENT_TRAINING_SYSTEM.md §6.4):
// feed it a "go hard" Claude session + a cooked ReadinessPicture, prove it
// downgrades; feed each route in isolation; feed sub-14-sample history, prove it
// falls back to Route A without crashing. Pure — no device/store/network.
//

@testable import Tempo
import XCTest

final class TrainingSafetyFloorTests: XCTestCase {

    private typealias F = TrainingSafetyFloor

    // MARK: - Fixtures

    /// A neutral, fully-baselined picture (green, no flags). Override per test.
    private func picture(
        recovery: Double = 75,
        hrvZ: Double? = 0,
        rhrDelta: Double? = 0,
        rhrZ: Double? = 0,
        respDelta: Double? = 0,
        sleepDebt: Double? = 0,
        validSamples: Int = 30,
        historyDays: Int = 30,
        daysUntilMatch: Int? = nil
    ) -> ReadinessPicture {
        ReadinessPicture(
            recoveryScore: recovery,
            hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: sleepDebt, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: hrvZ, hrvTrend7d: .flat,
            rhrDeltaBpm: rhrDelta, rhrZScore: rhrZ,
            respDeltaBrMin: respDelta, acuteChronicStrainRatio: 1.0,
            yesterdaySessions: [], weightKg: 80, bodyFatPct: 12, leanMassKg: 68,
            checkIn: nil, daysUntilNextMatch: daysUntilMatch,
            validBaselineSampleCount: validSamples, historyDayCount: historyDays
        )
    }

    /// A "go hard" gym-legs session, the thing the floor must be able to veto.
    private func goHardLegs() -> DailySessionDTO {
        DailySessionDTO(
            modality: "legs", intensity: .hard, durationMin: 75,
            blocks: [SessionBlockDTO(
                kind: .gym, label: "Heavy legs", notes: nil, cue: "Brace hard.",
                scheduledMin: nil,
                split: "legs", reps: nil, distanceM: nil, restSec: nil,
                intensityPct: nil, durationSec: nil, stroke: nil,
                runType: nil, paceSecPerKm: nil, sets: nil
            )],
            shortWhy: "Green light — push.", fullWhy: nil,
            expectedStrain: 14, expectedSessionRPE: 8
        )
    }

    // MARK: - SEVERE routes (each in isolation)

    func testRouteA_redRecoveryIsSevere() {
        XCTAssertEqual(F.classifyFloorTier(picture(recovery: 30)), .severe)
    }

    func testMissingRecoveryIsNotRed() {
        // No sync today (score 0 sentinel) must not force a rest day.
        let p = picture(recovery: 0)
        XCTAssertFalse(p.hasRecoveryScore)
        XCTAssertNotEqual(F.classifyFloorTier(p), .severe)
        XCTAssertFalse(p.easeCrossTrainingToday)
        let decision = F.apply(goHardLegs(), picture: p)
        XCTAssertNotEqual(decision.session.intensity, .recovery)
        // Recovery-conjunct routes: high sleep debt / resp with no synced
        // score is not "non-green".
        XCTAssertNotEqual(F.classifyFloorTier(picture(recovery: 0, sleepDebt: 5)), .severe)
        XCTAssertNotEqual(F.classifyFloorTier(picture(recovery: 0, respDelta: 3)), .severe)
        // …but a real non-green day still trips them.
        XCTAssertEqual(F.classifyFloorTier(picture(recovery: 55, sleepDebt: 5)), .severe)
    }

    func testRouteB_hrvCrashAndRhrSpikeIsSevere() {
        // HRV z ≤ -1.5 AND RHR ≥ +5 bpm → the cooked-day AND-gate.
        let p = picture(recovery: 70, hrvZ: -1.8, rhrDelta: 6)
        XCTAssertEqual(F.classifyFloorTier(p), .severe)
    }

    func testRouteB_hrvCrashAloneIsNotSevere() {
        // HRV crash WITHOUT RHR spike must NOT fire SEVERE (avoids vetoing on noise).
        let p = picture(recovery: 70, hrvZ: -1.8, rhrDelta: 0)
        XCTAssertNotEqual(F.classifyFloorTier(p), .severe)
    }

    func testSleepRoute_highDebtOnYellowIsSevere() {
        let p = picture(recovery: 55, sleepDebt: 4.5)
        XCTAssertEqual(F.classifyFloorTier(p), .severe)
    }

    func testSleepRoute_highDebtOnGreenIsNotSevere() {
        // High sleep debt on a GREEN day downgrades to moderate, not severe.
        let p = picture(recovery: 80, sleepDebt: 4.5)
        XCTAssertNotEqual(F.classifyFloorTier(p), .severe)
    }

    func testIllnessRoute_elevatedRespOnNonGreenIsSevere() {
        let p = picture(recovery: 60, respDelta: 2.5)
        XCTAssertEqual(F.classifyFloorTier(p), .severe)
    }

    // MARK: - The adversarial core: go-hard + cooked → downgraded

    func testGoHardOnCookedDayIsForcedToRecovery() {
        let cooked = picture(recovery: 28) // red
        let decision = F.apply(goHardLegs(), picture: cooked)
        XCTAssertEqual(decision.tier, .severe)
        XCTAssertTrue(decision.wasDowngraded)
        XCTAssertEqual(decision.session.intensity, .recovery)
        XCTAssertEqual(decision.session.modality, "rest")
    }

    // MARK: - MODERATE clamps but keeps modality

    func testModerateClampsHardToModerate() {
        let yellow = picture(recovery: 50, hrvZ: -1.1)
        let decision = F.apply(goHardLegs(), picture: yellow)
        XCTAssertEqual(decision.tier, .moderate)
        XCTAssertEqual(decision.session.intensity, .moderate)
        XCTAssertEqual(decision.session.modality, "legs") // modality preserved
    }

    // MARK: - NORMAL passes through

    func testNormalGreenPassesThroughUnchanged() {
        let green = picture(recovery: 80)
        let decision = F.apply(goHardLegs(), picture: green)
        XCTAssertEqual(decision.tier, .normal)
        XCTAssertFalse(decision.wasDowngraded)
        XCTAssertEqual(decision.session.intensity, .hard)
    }

    // MARK: - Cold-start: sub-14 samples → Route A only, no crash

    func testColdStart_rawRoutesDisabledBelow14Samples() {
        // A picture that WOULD be Route-B severe, but with only 10 valid samples
        // the raw routes are disabled — falls back to Route A (recovery green) → not severe.
        let p = picture(recovery: 70, hrvZ: -1.8, rhrDelta: 6, validSamples: 10)
        XCTAssertFalse(p.hasBaselineForFloor)
        XCTAssertNotEqual(F.classifyFloorTier(p), .severe, "Raw routes must be disabled cold")
    }

    func testColdStart_routeAStillFiresBelow14Samples() {
        // Recovery red still fires SEVERE even with no baseline (Route A is always on).
        let p = picture(recovery: 30, validSamples: 5)
        XCTAssertEqual(F.classifyFloorTier(p), .severe)
    }

    // MARK: - Match protection (T-1)

    func testMatchTMinus1ClampsHardLegs() {
        let green = picture(recovery: 80, daysUntilMatch: 1)
        let decision = F.apply(goHardLegs(), picture: green)
        // Green tier is normal, but match-protection still clamps hard legs down.
        XCTAssertTrue(decision.wasDowngraded)
        XCTAssertEqual(decision.session.intensity, .easy)
    }

    func testNoMatchNoClamp() {
        let green = picture(recovery: 80, daysUntilMatch: nil)
        let decision = F.apply(goHardLegs(), picture: green)
        XCTAssertFalse(decision.wasDowngraded)
    }
}
