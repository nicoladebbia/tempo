//
// CompositeDayTests.swift
// Tempo
//
// Proves the §21 T1 composite-day machinery: the parts grouping (untimed
// blocks join the earliest part; pre-§21 sessions are one untimed part), the
// scheduledMin parser round-trip, and — the safety core — the floor's §21.4
// composite gate, adversarially: legs+field stripped, <6h gap stripped,
// hard+hard stripped, ACWR cap, match-T0 primer rule, and the anchor-always-
// survives guarantee. Single-part sessions must pass through byte-identical.
//

@testable import Tempo
import XCTest

final class CompositeDayTests: XCTestCase {
    // MARK: - Builders

    private func block(
        kind: BlockKind, label: String = "x", scheduledMin: Int? = nil,
        split: String? = nil, reps: Int? = nil, intensityPct: Double? = nil
    ) -> SessionBlockDTO {
        SessionBlockDTO(
            kind: kind, label: label, notes: nil, cue: nil, scheduledMin: scheduledMin,
            split: split, reps: reps, distanceM: nil, restSec: nil,
            intensityPct: intensityPct, durationSec: nil, stroke: nil,
            runType: nil, paceSecPerKm: nil, sets: nil
        )
    }

    private func session(intensity: SessionIntensity, blocks: [SessionBlockDTO]) -> DailySessionDTO {
        DailySessionDTO(
            modality: "pull", intensity: intensity, durationMin: 60, blocks: blocks,
            shortWhy: "Test.", fullWhy: nil, expectedStrain: nil, expectedSessionRPE: 7
        )
    }

    private func picture(acwr: Double? = 1.0, daysUntilMatch: Int? = nil) -> ReadinessPicture {
        ReadinessPicture(
            recoveryScore: 80,
            hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: 0, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: 0, hrvTrend7d: .flat,
            rhrDeltaBpm: 0, rhrZScore: 0,
            respDeltaBrMin: 0, acuteChronicStrainRatio: acwr,
            yesterdaySessions: [], weightKg: 80, bodyFatPct: 12, leanMassKg: 68,
            checkIn: nil, daysUntilNextMatch: daysUntilMatch,
            validBaselineSampleCount: 30, historyDayCount: 30
        )
    }

    // MARK: - Parts grouping

    func testUntimedSessionIsOnePart() {
        let blocks = [block(kind: .gym, split: "pull"), block(kind: .mobility)]
        XCTAssertEqual(blocks.parts.count, 1)
        XCTAssertNil(blocks.parts[0].scheduledMin)
    }

    func testUntimedBlocksJoinEarliestPart() {
        let blocks = [
            block(kind: .mobility, label: "warmup"),
            block(kind: .gym, scheduledMin: 960, split: "pull"),
            block(kind: .field, label: "tempo runs", scheduledMin: 1200, reps: 6),
        ]
        let parts = blocks.parts
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].scheduledMin, 960)
        XCTAssertEqual(parts[0].blocks.map { $0.label }, ["warmup", "x"], "Untimed warmup joins the 16:00 anchor")
        XCTAssertEqual(parts[1].scheduledMin, 1200)
    }

    func testPartsOrderedByStartTime() {
        let blocks = [
            block(kind: .field, scheduledMin: 1200, reps: 4),
            block(kind: .gym, scheduledMin: 960, split: "pull"),
        ]
        XCTAssertEqual(blocks.parts.map { $0.scheduledMin }, [960, 1200])
    }

    // MARK: - Parser round-trip

    func testParserRoundTripsScheduledMin() throws {
        let json = """
        {"modality":"pull","intensity":"hard","durationMin":80,
         "blocks":[{"kind":"gym","label":"Pull","split":"pull","scheduledMin":960},
                   {"kind":"mobility","label":"Evening flow","scheduledMin":1230}],
         "shortWhy":"Lift now, loosen up tonight."}
        """
        let s = try DailySessionParser.parse(json)
        XCTAssertTrue(s.isComposite)
        XCTAssertEqual(s.blocks.compactMap(\.scheduledMin), [960, 1230])
    }

    func testOldJSONWithoutScheduledMinStillParses() throws {
        let json = """
        {"modality":"pull","intensity":"moderate","durationMin":50,
         "blocks":[{"kind":"gym","label":"Pull","split":"pull"}],"shortWhy":"x"}
        """
        let s = try DailySessionParser.parse(json)
        XCTAssertFalse(s.isComposite)
        XCTAssertNil(s.blocks[0].scheduledMin)
    }

    // MARK: - Floor §21.4: pass-through cases

    func testSinglePartSessionPassesUntouched() {
        let s = session(intensity: .hard, blocks: [block(kind: .gym, split: "legs")])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture())
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.session, s)
    }

    func testLegalCompositeSurvives() {
        // Hard pull 10:00 + easy mobility 20:30 — ≥6h apart, second part easy.
        let s = session(intensity: .hard, blocks: [
            block(kind: .gym, scheduledMin: 600, split: "pull"),
            block(kind: .mobility, label: "evening flow", scheduledMin: 1230),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture())
        XCTAssertFalse(result.changed, "10:00 lift + 20:30 mobility is legal: ≥6h, second part easy")
    }

    func testEasyFieldSecondPartSurvivesOnHardDayWhenMarkedEasy() {
        let s = session(intensity: .hard, blocks: [
            block(kind: .gym, scheduledMin: 600, split: "pull"),
            block(kind: .field, label: "easy touches", scheduledMin: 1230, reps: 6, intensityPct: 60),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture())
        XCTAssertFalse(result.changed, "Upper lift + explicitly-easy field work is the U1 use case")
    }

    // MARK: - Floor §21.4: strips

    func testGapUnderSixHoursStripsLaterPart() {
        let s = session(intensity: .moderate, blocks: [
            block(kind: .gym, scheduledMin: 960, split: "pull"),
            block(kind: .mobility, label: "flow", scheduledMin: 1200), // 4h later
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture())
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.session.blocks.count, 1)
        XCTAssertEqual(result.session.blocks[0].kind, .gym, "Anchor survives; later part stripped")
        XCTAssertTrue(result.reason.contains("6h"), "Reason names the spacing rule")
    }

    func testHeavyLegsPlusFieldSprintStripped() {
        let s = session(intensity: .hard, blocks: [
            block(kind: .gym, scheduledMin: 600, split: "legs"),
            block(kind: .field, label: "sprints", scheduledMin: 1230, reps: 8, intensityPct: 95),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture())
        XCTAssertTrue(result.changed)
        XCTAssertFalse(result.session.blocks.contains { $0.kind == .field }, "Field part stripped — interference")
        XCTAssertTrue(result.session.blocks.contains { $0.split == "legs" }, "Anchor legs part survives")
    }

    func testHardPlusHardStripped() {
        let s = session(intensity: .hard, blocks: [
            block(kind: .gym, scheduledMin: 600, split: "pull"),
            block(kind: .run, label: "intervals", scheduledMin: 1230, intensityPct: 90),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture())
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.session.blocks.count, 1)
        XCTAssertTrue(result.reason.contains("Two hard sessions"), "One hard effort per day")
    }

    func testUnmarkedSecondPartOnHardDayStrippedConservatively() {
        // No intensityPct on the second part of a hard day → can't prove it's
        // easy → conservative strip.
        let s = session(intensity: .hard, blocks: [
            block(kind: .gym, scheduledMin: 600, split: "pull"),
            block(kind: .field, label: "field work", scheduledMin: 1230, reps: 6),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture())
        XCTAssertTrue(result.changed, "Unprovably-easy second part on a hard day must not survive")
    }

    func testHighACWRStripsSecondPart() {
        let s = session(intensity: .moderate, blocks: [
            block(kind: .gym, scheduledMin: 600, split: "pull"),
            block(kind: .mobility, label: "flow", scheduledMin: 1230),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture(acwr: 1.5))
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.session.blocks.count, 1)
        XCTAssertTrue(result.reason.contains("ACWR") || result.reason.contains("load"), "Reason names the load budget")
    }

    func testMatchTodayDropsLegLoadingKeepsMatchPart() {
        let s = session(intensity: .moderate, blocks: [
            block(kind: .gym, scheduledMin: 540, split: "legs"),
            block(kind: .field, label: "MATCH", scheduledMin: 1200, reps: 1),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture(daysUntilMatch: 0))
        XCTAssertTrue(result.changed)
        XCTAssertFalse(result.session.blocks.contains { $0.split == "legs" }, "No leg loading before kickoff")
        XCTAssertTrue(result.session.blocks.contains { $0.label == "MATCH" }, "The match itself is never stripped")
    }

    func testAnchorAlwaysSurvives() {
        // Every rule firing at once must still leave the anchor standing.
        let s = session(intensity: .hard, blocks: [
            block(kind: .gym, scheduledMin: 960, split: "pull"),
            block(kind: .field, label: "sprints", scheduledMin: 1100, reps: 8, intensityPct: 95),
            block(kind: .run, label: "intervals", scheduledMin: 1150, intensityPct: 90),
        ])
        let result = TrainingSafetyFloor.applyCompositeDayRules(s, picture: picture(acwr: 1.6))
        XCTAssertTrue(result.changed)
        XCTAssertFalse(result.session.blocks.isEmpty, "Strip never empties the session")
        XCTAssertEqual(result.session.blocks[0].split, "pull", "Anchor part survives")
    }

    // MARK: - Floor integration (full apply path)

    func testSevereDayStillForcesSingleRecoverySession() {
        // The SEVERE veto dominates §21 — a composite prescription on a crashed
        // day collapses to ONE recovery session, not a stripped composite.
        let p = ReadinessPicture(
            recoveryScore: 25,
            hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: 0, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: -1.8, hrvTrend7d: .falling,
            rhrDeltaBpm: 6, rhrZScore: 2,
            respDeltaBrMin: 0, acuteChronicStrainRatio: 1.0,
            yesterdaySessions: [], weightKg: 80, bodyFatPct: 12, leanMassKg: 68,
            checkIn: nil, daysUntilNextMatch: nil,
            validBaselineSampleCount: 30, historyDayCount: 30
        )
        let s = session(intensity: .hard, blocks: [
            block(kind: .gym, scheduledMin: 600, split: "pull"),
            block(kind: .field, label: "evening", scheduledMin: 1230, reps: 6, intensityPct: 60),
        ])
        let decision = TrainingSafetyFloor.apply(s, picture: p)
        XCTAssertEqual(decision.tier, .severe)
        XCTAssertEqual(decision.session.modality, "rest")
        XCTAssertFalse(decision.session.isComposite)
    }
}
