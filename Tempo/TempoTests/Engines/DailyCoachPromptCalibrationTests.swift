//
// DailyCoachPromptCalibrationTests.swift
// Tempo
//
// Calibrates the harness INSTRUMENT before any live Haiku call (advisor / §19.1).
// The 20-call verdict is only as trustworthy as the fixture judges. These tests
// feed the prompt's OWN exemplars (the known-good target shapes) through the real
// parser and the real judges. If a known-good exemplar fails its judge, the judge
// is broken — and the live verdict would be garbage. Caught here, offline, free.
//
// Exemplars are shared constants on DailyCoachPrompt (interpolated into the system
// prompt), so prompt and test cannot drift.
//

#if DEBUG
@testable import Tempo
import XCTest

final class DailyCoachPromptCalibrationTests: XCTestCase {

    // MARK: - Exemplars parse cleanly (prompt emits valid schema)

    func testGreenExemplarParses() throws {
        let s = try DailySessionParser.parse(DailyCoachPrompt.exemplarGreen)
        XCTAssertEqual(s.modality, "push")
    }

    func testRecoveryExemplarParses() throws {
        let s = try DailySessionParser.parse(DailyCoachPrompt.exemplarRecovery)
        XCTAssertEqual(s.intensity, .recovery)
    }

    func testPreMatchExemplarParses() throws {
        let s = try DailySessionParser.parse(DailyCoachPrompt.exemplarPreMatch)
        XCTAssertEqual(s.modality, "field")
    }

    // MARK: - Each exemplar passes the judge that will grade its live counterpart

    func testRecoveryExemplarPassesRecoveryJudge() throws {
        let s = try DailySessionParser.parse(DailyCoachPrompt.exemplarRecovery)
        XCTAssertTrue(SyntheticPictures.isRecoveryish(s),
                      "Recovery exemplar must satisfy isRecoveryish — else the red-day judge is broken")
    }

    func testPreMatchExemplarPassesNoHardLegsJudge() throws {
        let s = try DailySessionParser.parse(DailyCoachPrompt.exemplarPreMatch)
        XCTAssertTrue(SyntheticPictures.notHardLegs(s),
                      "Pre-match exemplar must satisfy notHardLegs — else the T-1 judge is broken")
    }

    func testGreenExemplarIsAGymPointer() throws {
        let s = try DailySessionParser.parse(DailyCoachPrompt.exemplarGreen)
        XCTAssertTrue(SyntheticPictures.noGymWeights(s),
                      "Green gym exemplar must be a pointer (no sets/weights) — else the gym-pointer judge is broken")
        XCTAssertNotEqual(s.intensity, .recovery, "Green exemplar should be a real training session")
    }

    // MARK: - The judges actually discriminate (a hard-legs session FAILS notHardLegs)

    func testNotHardLegsRejectsHardLegs() throws {
        let hardLegs = #"{"modality":"legs","intensity":"hard","durationMin":70,"blocks":[{"kind":"gym","label":"Heavy legs","split":"legs"}],"shortWhy":"x"}"#
        let s = try DailySessionParser.parse(hardLegs)
        XCTAssertFalse(SyntheticPictures.notHardLegs(s), "A hard legs session MUST fail notHardLegs, or the judge is a no-op")
    }

    func testIsRecoveryishRejectsHardSession() throws {
        let s = try DailySessionParser.parse(DailyCoachPrompt.exemplarGreen) // hard push
        XCTAssertFalse(SyntheticPictures.isRecoveryish(s), "A hard session MUST fail isRecoveryish, or the judge is a no-op")
    }

    // MARK: - There are 20 fixtures (the spec's ~20)

    func testFixtureCount() {
        XCTAssertGreaterThanOrEqual(SyntheticPictures.all.count, 18, "Need ~20 fixtures for a meaningful rate")
    }
}
#endif
