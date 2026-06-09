//
// DailyReadinessCoachTests.swift
// Tempo
//
// Verifies the coach's load-bearing contract (advisor): the floor runs on EVERY
// path, never bypassed — including cold-start (brainEligible=false) and the
// deterministic fallback. The brain-eligible=false path takes NO network, so
// these are pure/offline. The live brain call is exercised by the on-device
// harness (§5.2-FIX), not here.
//

@testable import Tempo
import XCTest

@MainActor
final class DailyReadinessCoachTests: XCTestCase {

    private func coach() -> DailyReadinessCoach {
        // APIClient is never hit on the brainEligible=false paths under test.
        DailyReadinessCoach(apiClient: APIClient())
    }

    private func picture(recovery: Double, hrvZ: Double? = 0, rhrDelta: Double? = 0, validSamples: Int = 30) -> ReadinessPicture {
        ReadinessPicture(
            recoveryScore: recovery, hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: 0, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: hrvZ, hrvTrend7d: .flat, rhrDeltaBpm: rhrDelta, rhrZScore: 0,
            respDeltaBrMin: 0, acuteChronicStrainRatio: 1.0, yesterdaySessions: [],
            weightKg: 80, bodyFatPct: 12, leanMassKg: 68, checkIn: nil,
            daysUntilNextMatch: nil, validBaselineSampleCount: validSamples, historyDayCount: validSamples
        )
    }

    /// A deterministic "go hard legs" candidate — the engine's pick, worst case.
    private func goHardCandidate() -> DailySessionDTO {
        DailySessionDTO(
            modality: "legs", intensity: .hard, durationMin: 70,
            blocks: [SessionBlockDTO(kind: .gym, label: "Legs", notes: nil, cue: nil, split: "legs",
                                     reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                                     durationSec: nil, stroke: nil, runType: nil, paceSecPerKm: nil, sets: nil)],
            shortWhy: "go", fullWhy: nil, expectedStrain: 14, expectedSessionRPE: 8
        )
    }

    // MARK: - The floor runs even in cold-start (brain skipped, floor NOT skipped)

    func testColdStartStillAppliesFloor() async {
        // brainEligible=false (cold-start), but the day is RED → floor must STILL
        // force recovery. This is the bug the advisor warned about: skipping the
        // floor inside the brain-skip branch.
        let result = await coach().session(
            for: picture(recovery: 28), plannedModality: "legs",
            deterministicCandidate: goHardCandidate(), brainEligible: false
        )
        XCTAssertEqual(result.source, .simple)
        XCTAssertEqual(result.decision.tier, .severe)
        XCTAssertTrue(result.decision.wasDowngraded)
        XCTAssertEqual(result.decision.session.intensity, .recovery, "Floor must fire even when the brain is skipped")
    }

    func testColdStartNormalDayPassesThrough() async {
        let result = await coach().session(
            for: picture(recovery: 80), plannedModality: "legs",
            deterministicCandidate: goHardCandidate(), brainEligible: false
        )
        XCTAssertEqual(result.source, .simple)
        XCTAssertEqual(result.decision.tier, .normal)
        XCTAssertEqual(result.decision.session.modality, "legs", "Green cold-start day keeps the deterministic candidate")
    }

    // MARK: - Source provenance is honest

    func testColdStartIsLabelledSimpleNotBrain() async {
        let result = await coach().session(
            for: picture(recovery: 70), plannedModality: nil,
            deterministicCandidate: goHardCandidate(), brainEligible: false
        )
        XCTAssertEqual(result.source, .simple, "Cold-start must NOT be labelled as a brain session")
    }

    // MARK: - Moderate clamps even without the brain

    func testColdStartModerateClamps() async {
        let result = await coach().session(
            for: picture(recovery: 50, hrvZ: -1.1), plannedModality: "legs",
            deterministicCandidate: goHardCandidate(), brainEligible: false
        )
        XCTAssertEqual(result.decision.tier, .moderate)
        XCTAssertEqual(result.decision.session.intensity, .moderate, "Yellow day clamps hard→moderate even in cold-start")
    }
}
