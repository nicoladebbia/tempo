//
// PlanResolutionTests.swift
// Tempo
//
// Tier 3.1 — the data-loss invariant. planResolution decides whether an
// existing persisted day-row is KEPT or REPLACED when the week template
// disagrees (e.g. after editing football days / split). A completed or
// in-progress row is sacred and must NEVER be replaced. This is the failure
// mode that would silently eat logged training, so it's pinned by test.
//

@testable import Tempo
import XCTest

final class PlanResolutionTests: XCTestCase {

    // MARK: - Sacred rows are never replaced (the data-loss guard)

    func testCompletedIsNeverReplacedEvenWhenTypeDiffers() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .completed, existingType: .pull, templateType: .push
        )
        XCTAssertEqual(r, .keep, "A completed session is sacred — never replaced")
    }

    func testInProgressIsNeverReplaced() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .inProgress, existingType: .pull, templateType: .legs
        )
        XCTAssertEqual(r, .keep, "An in-progress session is sacred — never replaced")
    }

    func testSkippedIsNeverReplaced() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .skipped, existingType: .pull, templateType: .push
        )
        XCTAssertEqual(r, .keep, "A skipped row is not regenerated")
    }

    // MARK: - Planned rows regenerate only on a real type change

    func testPlannedWithDifferentTypeIsReplaced() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .pull, templateType: .push
        )
        XCTAssertEqual(r, .replace, "A still-planned row that disagrees with the template re-personalizes")
    }

    func testPlannedWithSameTypeIsKept() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .push, templateType: .push
        )
        XCTAssertEqual(r, .keep, "No change needed when the planned type already matches")
    }

    // MARK: - §8 connect — brain-reshaped rows survive the resolution

    func testBrainReshapedRowIsKept() {
        // Planned pool → brain moved the day to rest, stashing "pool". The
        // template still says pool — the mismatch is deliberate, keep it.
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .rest,
            existingPlannedTypeRaw: WorkoutType.pool.rawValue, templateType: .pool
        )
        XCTAssertEqual(r, .keep, "A brain-reshaped day must not be stomped on the next app-open")
    }

    func testBrainReshapedRowReplacedWhenTemplateChanged() {
        // The user edited the weekly schedule after the reshape: the stash no
        // longer matches the template → the schedule edit wins.
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .rest,
            existingPlannedTypeRaw: WorkoutType.pool.rawValue, templateType: .legs
        )
        XCTAssertEqual(r, .replace, "A real schedule edit outranks a stale daily reshape")
    }

    // MARK: - §8 connect — modality → plan-type mapping

    func testModalityMapsDirectRawValues() {
        XCTAssertEqual(WorkoutType.fromModality("rest"), .rest)
        XCTAssertEqual(WorkoutType.fromModality("pool"), .pool)
        XCTAssertEqual(WorkoutType.fromModality("push"), .push)
    }

    func testModalityMapsBrainSynonyms() {
        XCTAssertEqual(WorkoutType.fromModality("recovery"), .rest)
        XCTAssertEqual(WorkoutType.fromModality("swim"), .pool)
        XCTAssertEqual(WorkoutType.fromModality("field"), .conditioning)
    }

    func testUnknownModalityIsNilNotAGuess() {
        XCTAssertNil(WorkoutType.fromModality("yoga"),
                     "Unmappable modality must leave the plan row alone")
    }
}
