//
// StrengthStandardsTests.swift
// Tempo
//
// Cold-start strength estimation. Pure (no SwiftData) — these lock the e1RM
// currency math, the bodyweight/experience differentiation that fixes the "some
// weights too high, others too low" flat-table bug, and the conservative
// classification/rounding rules.
//

@testable import Tempo
import XCTest

final class StrengthStandardsTests: XCTestCase {
    // MARK: - Fixtures

    private func exercise(
        name: String = "Lift",
        equipment: Equipment,
        pattern: MovementPattern,
        compound: Bool
    ) -> Exercise {
        Exercise(
            name: name,
            muscleGroup: .quads,
            equipment: equipment,
            movementPattern: pattern,
            isCompound: compound
        )
    }

    // MARK: - Epley round-trip (the anchor of the whole system)

    func testInverseEpleyIsExactInverseOfEpley() {
        for reps in [1, 3, 5, 8, 12, 15] {
            let e1RM = StrengthStandards.epleyE1RM(weight: 100, reps: reps)
            let back = StrengthStandards.inverseEpleyWeight(e1RM: e1RM, reps: reps)
            XCTAssertEqual(back, 100, accuracy: 0.0001, "reps=\(reps): weight must round-trip through e1RM")
        }
    }

    func testEpleyKnownValues() {
        XCTAssertEqual(StrengthStandards.epleyE1RM(weight: 100, reps: 8), 126.667, accuracy: 0.01)
        XCTAssertEqual(StrengthStandards.inverseEpleyWeight(e1RM: 126.667, reps: 8), 100, accuracy: 0.01)
    }

    func testSingleRepIsIdentity() {
        XCTAssertEqual(StrengthStandards.epleyE1RM(weight: 140, reps: 1), 140, accuracy: 0.0001)
        XCTAssertEqual(StrengthStandards.inverseEpleyWeight(e1RM: 140, reps: 1), 140, accuracy: 0.0001)
    }

    // MARK: - Experience multiplier (unknown → beginner, biased low)

    func testExperienceMultiplierOrdering() {
        let beginner = StrengthStandards.experienceMultiplier("Beginner")
        let intermediate = StrengthStandards.experienceMultiplier("Intermediate")
        let advanced = StrengthStandards.experienceMultiplier("Advanced")
        XCTAssertLessThan(beginner, intermediate)
        XCTAssertLessThan(intermediate, advanced)
    }

    func testUnknownAndNilExperienceFallToBeginner() {
        let beginner = StrengthStandards.experienceMultiplier("Beginner")
        XCTAssertEqual(StrengthStandards.experienceMultiplier(nil), beginner)
        XCTAssertEqual(StrengthStandards.experienceMultiplier("gibberish"), beginner)
        XCTAssertEqual(StrengthStandards.experienceMultiplier("BEGINNER"), beginner, "case-insensitive")
    }

    // MARK: - Cold-start differentiation (the actual bug being fixed)

    func testDifferentBarbellLiftsGetDifferentStarts() {
        // The old flat table gave a barbell squat and a barbell overhead press
        // the SAME 40 kg. They must now differ (squat >> OHP).
        let squat = exercise(equipment: .barbell, pattern: .squat, compound: true)
        let ohp = exercise(equipment: .barbell, pattern: .verticalPush, compound: true)
        let squatE1RM = StrengthStandards.baselineE1RM(for: squat, bodyweightKg: 70, experienceLevel: "Intermediate")
        let ohpE1RM = StrengthStandards.baselineE1RM(for: ohp, bodyweightKg: 70, experienceLevel: "Intermediate")
        XCTAssertGreaterThan(squatE1RM, ohpE1RM, "Squat baseline must exceed overhead-press baseline")
    }

    func testBarbellBaselineScalesWithBodyweight() {
        let squat = exercise(equipment: .barbell, pattern: .squat, compound: true)
        let light = StrengthStandards.baselineE1RM(for: squat, bodyweightKg: 60, experienceLevel: "Intermediate")
        let heavy = StrengthStandards.baselineE1RM(for: squat, bodyweightKg: 90, experienceLevel: "Intermediate")
        XCTAssertGreaterThan(heavy, light, "Heavier lifter starts heavier on a bodyweight-relative lift")
    }

    func testExperienceScalesBaseline() {
        let squat = exercise(equipment: .barbell, pattern: .squat, compound: true)
        let beginner = StrengthStandards.baselineE1RM(for: squat, bodyweightKg: 70, experienceLevel: "Beginner")
        let advanced = StrengthStandards.baselineE1RM(for: squat, bodyweightKg: 70, experienceLevel: "Advanced")
        XCTAssertLessThan(beginner, advanced)
    }

    func testDumbbellIsolationUsesAbsoluteSeedNotBodyweight() {
        // Non-barbell / isolation must NOT scale with bodyweight (a machine/DB
        // number is not comparable to a barbell load).
        let curl = exercise(equipment: .dumbbell, pattern: .isolation, compound: false)
        let atLightBW = StrengthStandards.baselineE1RM(for: curl, bodyweightKg: 55, experienceLevel: "Intermediate")
        let atHeavyBW = StrengthStandards.baselineE1RM(for: curl, bodyweightKg: 95, experienceLevel: "Intermediate")
        XCTAssertEqual(atLightBW, atHeavyBW, accuracy: 0.0001, "Absolute-seed lifts ignore bodyweight")
    }

    func testBarbellFallsBackToAbsoluteSeedWhenBodyweightUnknown() {
        let squat = exercise(equipment: .barbell, pattern: .squat, compound: true)
        let e1RM = StrengthStandards.baselineE1RM(for: squat, bodyweightKg: nil, experienceLevel: "Intermediate")
        XCTAssertGreaterThan(e1RM, 0, "No bodyweight → conservative absolute seed, not a crash or zero")
    }

    // MARK: - Bodyweight-movement path

    func testBodyweightMovementUsesBodyweight() {
        let pullUp = exercise(equipment: .pullUpBar, pattern: .verticalPull, compound: true)
        let e1RM = StrengthStandards.baselineE1RM(for: pullUp, bodyweightKg: 70, experienceLevel: "Intermediate")
        XCTAssertGreaterThan(e1RM, 0)
        // Effective 1RM anchors near bodyweight for an intermediate.
        XCTAssertLessThan(abs(e1RM - 70), 30, "Bodyweight pull-up e1RM should be in the neighborhood of bodyweight")
    }

    // MARK: - Sibling inference

    func testSiblingRatioHaircut() {
        let flat = exercise(name: "Flat", equipment: .barbell, pattern: .horizontalPush, compound: true)
        let inclineSameEq = exercise(name: "Incline", equipment: .barbell, pattern: .horizontalPush, compound: true)
        let inclineCrossEq = exercise(name: "DB Incline", equipment: .dumbbell, pattern: .horizontalPush, compound: true)
        let sameEq = StrengthStandards.siblingE1RM(target: inclineSameEq, sibling: flat, siblingE1RM: 100)
        let crossEq = StrengthStandards.siblingE1RM(target: inclineCrossEq, sibling: flat, siblingE1RM: 100)
        XCTAssertEqual(sameEq, 95, accuracy: 0.01, "Same-equipment sibling: gentle haircut")
        XCTAssertEqual(crossEq, 85, accuracy: 0.01, "Cross-equipment sibling: bigger haircut")
        XCTAssertLessThan(crossEq, sameEq)
    }

    // MARK: - Classification + rounding

    func testEquipmentClassification() {
        XCTAssertTrue(StrengthStandards.isBodyweightLoaded(.bodyweight))
        XCTAssertTrue(StrengthStandards.isBodyweightLoaded(.pullUpBar))
        XCTAssertFalse(StrengthStandards.isBodyweightLoaded(.barbell))
        XCTAssertTrue(StrengthStandards.isBarbellFamily(.barbell))
        XCTAssertTrue(StrengthStandards.isBarbellFamily(.smithMachine))
        XCTAssertFalse(StrengthStandards.isBarbellFamily(.dumbbell))
    }

    func testRounding() {
        XCTAssertEqual(StrengthStandards.roundToIncrement(93.7, equipment: .barbell), 92.5, accuracy: 0.001)
        XCTAssertEqual(StrengthStandards.roundToIncrement(11.3, equipment: .dumbbell), 12, accuracy: 0.001)
        XCTAssertEqual(StrengthStandards.roundToIncrement(-5, equipment: .barbell), 0, accuracy: 0.001, "Never negative")
    }

    func testShareLoadBasis() {
        let bar = exercise(equipment: .barbell, pattern: .squat, compound: true)
        let db = exercise(equipment: .dumbbell, pattern: .squat, compound: true)
        let pull = exercise(equipment: .pullUpBar, pattern: .verticalPull, compound: true)
        XCTAssertTrue(StrengthStandards.shareLoadBasis(bar, db), "Both non-bodyweight → same basis")
        XCTAssertFalse(StrengthStandards.shareLoadBasis(bar, pull), "Free-weight vs bodyweight → different basis")
    }
}
