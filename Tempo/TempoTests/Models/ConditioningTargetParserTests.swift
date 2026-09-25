//
// ConditioningTargetParserTests.swift
// Tempo
//
// Fix #7 — the trainer writes conditioning prescriptions as free text
// (ProgramExercise.detail). These pin the parser against real strings pulled
// from actual imported programs, plus Italian units and malformed input.
//

@testable import Tempo
import XCTest

final class ConditioningTargetParserTests: XCTestCase {
    // MARK: - reps × distance (+ cap)

    func testRepsOfDistanceWithSecondsCap() {
        let target = ConditioningTargetParser.parse(detail: "4 reps of 25y out and back in < 65\"")
        guard case let .repsDistance(reps, distance, unit, cap) = target.kind else {
            return XCTFail("expected repsDistance, got \(target.kind)")
        }
        XCTAssertEqual(reps, 4)
        XCTAssertEqual(distance, 25)
        XCTAssertEqual(unit, .yards)
        XCTAssertEqual(cap, 65)
    }

    func testRepsOfDistanceMetersCap() {
        let target = ConditioningTargetParser.parse(detail: "6 reps of 40m in < 7 sec")
        guard case let .repsDistance(reps, distance, unit, cap) = target.kind else {
            return XCTFail("expected repsDistance, got \(target.kind)")
        }
        XCTAssertEqual(reps, 6)
        XCTAssertEqual(distance, 40)
        XCTAssertEqual(unit, .meters)
        XCTAssertEqual(cap, 7)
    }

    func testRepsOfDistanceNoCapStillParses() {
        let target = ConditioningTargetParser.parse(detail: "4 reps of 25y out and back")
        guard case let .repsDistance(reps, distance, unit, cap) = target.kind else {
            return XCTFail("expected repsDistance, got \(target.kind)")
        }
        XCTAssertEqual(reps, 4)
        XCTAssertEqual(distance, 25)
        XCTAssertEqual(unit, .yards)
        XCTAssertNil(cap)
    }

    func testItalianRipetuteDaWithSecondiCap() {
        let target = ConditioningTargetParser.parse(detail: "4 ripetute da 25m in < 65 secondi")
        guard case let .repsDistance(reps, distance, unit, cap) = target.kind else {
            return XCTFail("expected repsDistance, got \(target.kind)")
        }
        XCTAssertEqual(reps, 4)
        XCTAssertEqual(distance, 25)
        XCTAssertEqual(unit, .meters)
        XCTAssertEqual(cap, 65)
    }

    // MARK: - duration

    func testApostropheMinutesWithParentheticalBreakdown() {
        let target = ConditioningTargetParser.parse(detail: "35' (2' slow - 1' fast - 30\" walk + juggling)")
        guard case let .duration(minutes) = target.kind else {
            return XCTFail("expected duration, got \(target.kind)")
        }
        XCTAssertEqual(minutes, 35, "takes the FIRST duration marker, not the parenthetical breakdown")
    }

    func testApostropheMinutesWithTrailingWord() {
        let target = ConditioningTargetParser.parse(detail: "15' easy")
        guard case let .duration(minutes) = target.kind else {
            return XCTFail("expected duration, got \(target.kind)")
        }
        XCTAssertEqual(minutes, 15)
    }

    func testMinAbbreviation() {
        let target = ConditioningTargetParser.parse(detail: "10 min")
        guard case let .duration(minutes) = target.kind else {
            return XCTFail("expected duration, got \(target.kind)")
        }
        XCTAssertEqual(minutes, 10)
    }

    func testItalianMinuti() {
        let target = ConditioningTargetParser.parse(detail: "20 minuti facili")
        guard case let .duration(minutes) = target.kind else {
            return XCTFail("expected duration, got \(target.kind)")
        }
        XCTAssertEqual(minutes, 20)
    }

    func testDecimalMinutesWithComma() {
        let target = ConditioningTargetParser.parse(detail: "12,5 min easy jog")
        guard case let .duration(minutes) = target.kind else {
            return XCTFail("expected duration, got \(target.kind)")
        }
        XCTAssertEqual(minutes, 12.5)
    }

    // MARK: - interval sets

    func testIntervalSetsWithTimesAndSideSplitAndDistances() {
        let target = ConditioningTargetParser.parse(detail: "2 x 10times (5R-5L) 10m+5m")
        guard case let .intervalSets(sets, reps) = target.kind else {
            return XCTFail("expected intervalSets, got \(target.kind)")
        }
        XCTAssertEqual(sets, 2)
        XCTAssertEqual(reps, 10)
    }

    func testIntervalSetsCompactNotation() {
        let target = ConditioningTargetParser.parse(detail: "3x8")
        guard case let .intervalSets(sets, reps) = target.kind else {
            return XCTFail("expected intervalSets, got \(target.kind)")
        }
        XCTAssertEqual(sets, 3)
        XCTAssertEqual(reps, 8)
    }

    func testIntervalSetsWithMultiplicationSign() {
        let target = ConditioningTargetParser.parse(detail: "4 × 6 reps")
        guard case let .intervalSets(sets, reps) = target.kind else {
            return XCTFail("expected intervalSets, got \(target.kind)")
        }
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(reps, 6)
    }

    // MARK: - distance only

    func testDistanceKilometers() {
        let target = ConditioningTargetParser.parse(detail: "5 km")
        guard case let .distance(value, unit) = target.kind else {
            return XCTFail("expected distance, got \(target.kind)")
        }
        XCTAssertEqual(value, 5)
        XCTAssertEqual(unit, .kilometers)
    }

    func testDistanceMetersNoSpace() {
        let target = ConditioningTargetParser.parse(detail: "800m")
        guard case let .distance(value, unit) = target.kind else {
            return XCTFail("expected distance, got \(target.kind)")
        }
        XCTAssertEqual(value, 800)
        XCTAssertEqual(unit, .meters)
    }

    func testDistanceYardsNoSpace() {
        let target = ConditioningTargetParser.parse(detail: "300y")
        guard case let .distance(value, unit) = target.kind else {
            return XCTFail("expected distance, got \(target.kind)")
        }
        XCTAssertEqual(value, 300)
        XCTAssertEqual(unit, .yards)
    }

    func testDistanceDoesNotConfuseMinWithMetersUnit() {
        // "min" must never parse as the "m" (meters) unit.
        let target = ConditioningTargetParser.parse(detail: "10 min easy")
        guard case .duration = target.kind else {
            return XCTFail("expected duration, got \(target.kind)")
        }
    }

    // MARK: - freeform / malformed

    func testEmptyStringIsFreeform() {
        XCTAssertEqual(ConditioningTargetParser.parse(detail: "").kind, .freeform)
    }

    func testNilDetailIsFreeform() {
        XCTAssertEqual(ConditioningTargetParser.parse(detail: nil).kind, .freeform)
    }

    func testWhitespaceOnlyIsFreeform() {
        XCTAssertEqual(ConditioningTargetParser.parse(detail: "   \n\t  ").kind, .freeform)
    }

    func testUnrecognizedProseIsFreeform() {
        let target = ConditioningTargetParser.parse(detail: "Ladder drills, focus on knee drive and arm action")
        XCTAssertEqual(target.kind, .freeform)
        XCTAssertEqual(target.rawText, "Ladder drills, focus on knee drive and arm action")
    }

    func testGarbagePunctuationDoesNotCrashAndIsFreeform() {
        let target = ConditioningTargetParser.parse(detail: "!!! ### <<< >>> ???")
        XCTAssertEqual(target.kind, .freeform)
    }

    func testRawTextIsAlwaysPreservedVerbatimTrimmed() {
        let target = ConditioningTargetParser.parse(detail: "  35' (2' slow - 1' fast)  ")
        XCTAssertEqual(target.rawText, "35' (2' slow - 1' fast)")
    }
}
