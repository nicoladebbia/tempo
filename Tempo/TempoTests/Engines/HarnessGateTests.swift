//
// HarnessGateTests.swift
// Tempo
//
// Corrects the D0 verdict's category error (advisor). The harness's anti-pattern
// fixtures are NOT one class:
//   • floor-CAN'T-catch (pre-match tempo run, match-today): the floor's match
//     gate is T-1-and-hard-legs only, so these sail through → the PROMPT is the
//     only defense → MUST be sensible 100% of the time.
//   • floor-CAUGHT (red recovery, sleep-debt≥4h, illness-resp): the floor
//     independently classifies SEVERE and forces recovery → demanding Haiku
//     match these unaided contradicts §6 (the floor exists BECAUSE an LLM
//     underweights subtle [D]-threshold signals). These belong to prompt-quality,
//     not a hard gate.
//
// This test proves, offline (zero live calls), WHICH fixtures the floor catches,
// so the live verdict can gate correctly: (floor-can't-catch = 100%) AND
// (prompt-quality ≥ 19/20). Pure.
//

#if DEBUG
@testable import Tempo
import XCTest

final class HarnessGateTests: XCTestCase {

    /// A neutral "go hard" session — the worst thing Haiku could emit — so the
    /// floor's classification is what's under test, not the session content.
    private func goHard() -> DailySessionDTO {
        DailySessionDTO(
            modality: "legs", intensity: .hard, durationMin: 75,
            blocks: [SessionBlockDTO(
                kind: .gym, label: "Heavy", notes: nil, cue: nil, split: "legs",
                reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                durationSec: nil, stroke: nil, runType: nil, paceSecPerKm: nil, sets: nil
            )],
            shortWhy: "go", fullWhy: nil, expectedStrain: 16, expectedSessionRPE: 9
        )
    }

    /// True when the floor independently protects this day (severe tier OR the
    /// apply() step downgrades the worst-case session).
    private func floorProtects(_ p: ReadinessPicture) -> Bool {
        if TrainingSafetyFloor.classifyFloorTier(p) == .severe { return true }
        return TrainingSafetyFloor.apply(goHard(), picture: p).wasDowngraded
    }

    /// The illness-resp fixture (fixture 8) — the lone residual live miss — IS
    /// floor-caught, so it is NOT a hard-gate failure. This is the crux.
    func testIllnessRespFixtureIsFloorCaught() {
        let fixtures = SyntheticPictures.all
        guard let f8 = fixtures.first(where: { $0.name == "severe-illness-resp" }) else {
            return XCTFail("fixture severe-illness-resp missing")
        }
        XCTAssertTrue(floorProtects(f8.picture),
                      "Illness-resp day must be floor-caught — then Haiku missing it is the floor's job, not an architecture failure")
    }

    /// The floor-CAN'T-catch fixtures (the real prompt-only gate) must NOT be
    /// silently floor-protected — if they were, they'd not actually test the prompt.
    func testPreMatchAndMatchDayAreNotFullyFloorProtected() {
        let names = ["prematch-green", "match-today"]
        for name in names {
            guard let f = SyntheticPictures.all.first(where: { $0.name == name }) else {
                return XCTFail("fixture \(name) missing")
            }
            // A tempo run / non-leg session on these days is NOT downgraded by the
            // match gate (it only clamps hard legs at T-1) — so the prompt is the
            // sole defense. Prove the floor does NOT catch a non-leg hard session here.
            let tempoRun = DailySessionDTO(
                modality: "run", intensity: .hard, durationMin: 45,
                blocks: [SessionBlockDTO(
                    kind: .run, label: "Tempo", notes: nil, cue: nil, split: nil,
                    reps: nil, distanceM: 8000, restSec: nil, intensityPct: nil,
                    durationSec: nil, stroke: nil, runType: "tempo", paceSecPerKm: 240, sets: nil
                )],
                shortWhy: "go", fullWhy: nil, expectedStrain: 15, expectedSessionRPE: 8
            )
            let decision = TrainingSafetyFloor.apply(tempoRun, picture: f.picture)
            XCTAssertFalse(decision.wasDowngraded,
                           "\(name): a hard tempo run is NOT floor-caught — so the prompt is the only defense and this fixture is a real hard gate")
        }
    }

    /// Categorize ALL anti-pattern fixtures into the two classes, for the record.
    func testAntiPatternCategorization() {
        let antiPatternNames = SyntheticPictures.all.filter { $0.antiPattern != nil }.map(\.name)
        var floorCaught: [String] = []
        var promptOnly: [String] = []
        for name in antiPatternNames {
            let f = SyntheticPictures.all.first { $0.name == name }!
            if floorProtects(f.picture) { floorCaught.append(name) } else { promptOnly.append(name) }
        }
        // Document the split. The prompt-only set is the true 100% gate.
        print("FLOOR-CAUGHT anti-patterns (prompt-quality, not hard gate): \(floorCaught)")
        print("PROMPT-ONLY anti-patterns (the real 100% gate): \(promptOnly)")
        // The prompt-only set must be the pre-match / match-day family only.
        XCTAssertTrue(promptOnly.allSatisfy { $0.contains("match") },
                      "Only schedule-driven (match) cases should be prompt-only; got \(promptOnly)")
    }
}
#endif
