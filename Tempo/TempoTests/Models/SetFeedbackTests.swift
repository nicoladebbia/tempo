//
// SetFeedbackTests.swift
// Tempo
//
// Created by Tempo on 19/05/2026.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - SetFeedback Tests

// Phase 3 (Training session layer) — model behavior for SetFeedback and the
// PlannedSet link, plus the RPE clamp and enum raw-value round-tripping.

final class SetFeedbackTests: XCTestCase {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkoutPlan.self,
            PlannedExercise.self,
            PlannedSet.self,
            SetFeedback.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    func testFeedbackLinksToPlannedSetAndDenormalizesID() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let set = PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 60)
        ctx.insert(set)

        let fb = SetFeedback(
            plannedSet: set,
            rpe: 8,
            breathDifficulty: .gassed,
            formQuality: .sloppy,
            note: "left knee"
        )
        ctx.insert(fb)
        try ctx.save()

        XCTAssertEqual(fb.plannedSet?.id, set.id)
        // setID is denormalized from the linked set so it survives pruning.
        XCTAssertEqual(fb.setID, set.id)
        XCTAssertEqual(fb.breathDifficulty, .gassed)
        XCTAssertEqual(fb.formQuality, .sloppy)
        XCTAssertEqual(fb.note, "left knee")
    }

    @MainActor
    func testRPEIsClampedToValidRange() throws {
        let low = SetFeedback(rpe: -3)
        let high = SetFeedback(rpe: 99)
        let ok = SetFeedback(rpe: 7)

        XCTAssertEqual(low.rpe, 1, "RPE below 1 clamps to 1")
        XCTAssertEqual(high.rpe, 10, "RPE above 10 clamps to 10")
        XCTAssertEqual(ok.rpe, 7)
    }

    @MainActor
    func testEnumRawValueRoundTrip() throws {
        let fb = SetFeedback(rpe: 5, breathDifficulty: .moderate, formQuality: .failed)
        XCTAssertEqual(fb.breathDifficultyRaw, "moderate")
        XCTAssertEqual(fb.formQualityRaw, "failed")

        fb.breathDifficulty = .easy
        fb.formQuality = .clean
        XCTAssertEqual(fb.breathDifficultyRaw, "easy")
        XCTAssertEqual(fb.formQualityRaw, "clean")
    }

    @MainActor
    func testSetIDSurvivesPlannedSetDeletion() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let set = PlannedSet(setNumber: 2, targetReps: 5, targetWeight: 100)
        ctx.insert(set)
        let capturedID = set.id

        let fb = SetFeedback(plannedSet: set, rpe: 9)
        ctx.insert(fb)
        try ctx.save()

        ctx.delete(set)
        try ctx.save()

        // Relationship nullified, but the denormalized id remains for AI lookup.
        XCTAssertNil(fb.plannedSet)
        XCTAssertEqual(fb.setID, capturedID)
    }

    @MainActor
    func testDTOCarriesStableSetID() throws {
        let set = PlannedSet(setNumber: 1, targetReps: 10)
        let fb = SetFeedback(
            plannedSet: set,
            rpe: 6,
            breathDifficulty: .easy,
            formQuality: .clean
        )
        let dto = fb.toDTO()
        XCTAssertEqual(dto.set_id, set.id)
        XCTAssertEqual(dto.rpe, 6)
        XCTAssertEqual(dto.breath_difficulty, "easy")
        XCTAssertEqual(dto.form_quality, "clean")
    }

    func testEnumNegativeSignals() {
        XCTAssertTrue(BreathDifficulty.gassed.isNegativeSignal)
        XCTAssertFalse(BreathDifficulty.easy.isNegativeSignal)
        XCTAssertTrue(FormQuality.failed.isNegativeSignal)
        XCTAssertTrue(FormQuality.sloppy.isNegativeSignal)
        XCTAssertFalse(FormQuality.clean.isNegativeSignal)
    }
}
