//
// FeedbackAggregationTests.swift
// Tempo
//
// Tier 2.1 — the WRITE path. Verifies TrainingViewModel.aggregateFeedback
// (pure helper extracted from persistCompletion) produces the right
// ExerciseHistory aggregates: entered-only filter, mean RPE, worst form,
// and that the SetFeedback setID → PlannedSet.id lookup matches.
//

@testable import Tempo
import XCTest

final class FeedbackAggregationTests: XCTestCase {

    private func set() -> PlannedSet {
        PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 60)
    }

    /// A feedback row keyed to a set's id, as logSet creates it.
    private func feedback(
        for set: PlannedSet,
        rpe: Int,
        form: FormQuality = .clean,
        entered: Bool
    ) -> SetFeedback {
        let fb = SetFeedback(plannedSet: set, rpe: rpe, formQuality: form)
        fb.userProvidedFeedback = entered
        fb.perFieldFlagsRecorded = entered
        fb.rpeProvided = entered
        fb.formProvided = entered
        return fb
    }

    /// Mirror persistCompletion's map build (entered-only, keyed by setID).
    private func enteredMap(_ rows: [SetFeedback]) -> [UUID: SetFeedback] {
        Dictionary(rows.filter(\.userProvidedFeedback).map { ($0.setID, $0) }) { a, _ in a }
    }

    func testNoEnteredFeedbackReturnsNoSignal() {
        let s1 = set(); let s2 = set()
        // Both default (not entered) — must be excluded entirely.
        let rows = [feedback(for: s1, rpe: 7, entered: false),
                    feedback(for: s2, rpe: 7, entered: false)]
        let agg = TrainingViewModel.aggregateFeedback(
            completedSets: [s1, s2], enteredFeedback: enteredMap(rows)
        )
        XCTAssertNil(agg.avgRPE)
        XCTAssertNil(agg.worstFormRaw)
        XCTAssertEqual(agg.count, 0)
    }

    func testEnteredOnlyExcludesDefaults() {
        let s1 = set(); let s2 = set()
        // s1 entered RPE 9, s2 still default 7 — only s1 should count.
        let rows = [feedback(for: s1, rpe: 9, entered: true),
                    feedback(for: s2, rpe: 7, entered: false)]
        let agg = TrainingViewModel.aggregateFeedback(
            completedSets: [s1, s2], enteredFeedback: enteredMap(rows)
        )
        XCTAssertEqual(agg.avgRPE, 9, "Default row must be excluded from the mean")
        XCTAssertEqual(agg.count, 1)
    }

    func testMeanRPEAcrossEnteredRows() {
        let s1 = set(); let s2 = set()
        let rows = [feedback(for: s1, rpe: 8, entered: true),
                    feedback(for: s2, rpe: 10, entered: true)]
        let agg = TrainingViewModel.aggregateFeedback(
            completedSets: [s1, s2], enteredFeedback: enteredMap(rows)
        )
        XCTAssertEqual(agg.avgRPE!, 9, accuracy: 0.001)
        XCTAssertEqual(agg.count, 2)
    }

    func testWorstFormIsPicked() {
        let s1 = set(); let s2 = set(); let s3 = set()
        let rows = [feedback(for: s1, rpe: 7, form: .clean, entered: true),
                    feedback(for: s2, rpe: 7, form: .failed, entered: true),
                    feedback(for: s3, rpe: 7, form: .sloppy, entered: true)]
        let agg = TrainingViewModel.aggregateFeedback(
            completedSets: [s1, s2, s3], enteredFeedback: enteredMap(rows)
        )
        XCTAssertEqual(agg.worstFormRaw, FormQuality.failed.rawValue, "Worst of clean/failed/sloppy = failed")
    }

    func testSetIDLookupMatchesPlannedSetID() {
        // logSet creates SetFeedback(plannedSet: set) → setID defaults to set.id;
        // persistCompletion looks up enteredFeedback[set.id]. Pin that match.
        let s = set()
        let fb = feedback(for: s, rpe: 9, entered: true)
        XCTAssertEqual(fb.setID, s.id, "SetFeedback.setID must equal its PlannedSet.id")
        let agg = TrainingViewModel.aggregateFeedback(
            completedSets: [s], enteredFeedback: enteredMap([fb])
        )
        XCTAssertEqual(agg.count, 1, "Lookup by set.id must find the row")
        XCTAssertEqual(agg.avgRPE, 9)
    }

    // MARK: - Per-field flags (a partial entry is not a full one)

    func testBreathOnlyTapDoesNotInventAnRPE() {
        let s = set()
        let fb = SetFeedback(plannedSet: s, rpe: 7, breathDifficulty: .gassed)
        fb.userProvidedFeedback = true
        fb.perFieldFlagsRecorded = true
        fb.breathProvided = true
        let agg = TrainingViewModel.aggregateFeedback(completedSets: [s], enteredFeedback: enteredMap([fb]))
        XCTAssertNil(agg.avgRPE, "The default 7 was never entered")
        XCTAssertNil(agg.worstFormRaw, "Neither was the default 'Clean'")
        XCTAssertEqual(agg.gassedFraction, 1)
        XCTAssertEqual(agg.count, 1)
    }

    func testRPEOnlyEntryLeavesFormAndBreathUnknown() {
        let s = set()
        let fb = SetFeedback(plannedSet: s, rpe: 9)
        fb.userProvidedFeedback = true
        fb.perFieldFlagsRecorded = true
        fb.rpeProvided = true
        let agg = TrainingViewModel.aggregateFeedback(completedSets: [s], enteredFeedback: enteredMap([fb]))
        XCTAssertEqual(agg.avgRPE, 9)
        XCTAssertNil(agg.worstFormRaw)
        XCTAssertNil(agg.gassedFraction, "No breath answer is not 'never gassed'")
    }

    func testSetRPEFromTheWatchCountsWithoutPanelInput() {
        let s = set()
        s.rpe = 8
        let agg = TrainingViewModel.aggregateFeedback(completedSets: [s], enteredFeedback: [:])
        XCTAssertEqual(agg.avgRPE, 8)
        XCTAssertEqual(agg.count, 1)
    }

    func testEnteredSummaryShowsOnlyEnteredFields() {
        let fb = SetFeedback(plannedSet: set(), rpe: 7)
        XCTAssertNil(fb.enteredSummary, "Untouched row shows nothing")
        fb.breathProvided = true
        fb.breathDifficulty = .gassed
        XCTAssertEqual(fb.enteredSummary, "Gassed")
        fb.rpeProvided = true
        fb.rpe = 8
        XCTAssertEqual(fb.enteredSummary, "RPE 8 · Gassed")
    }

    func testRowRatedBeforeFlagsExistedKeepsAllItsFields() {
        let s = set()
        let fb = SetFeedback(plannedSet: s, rpe: 9, breathDifficulty: .gassed, formQuality: .sloppy)
        fb.userProvidedFeedback = true // rated by an older build: no per-field flags
        let agg = TrainingViewModel.aggregateFeedback(completedSets: [s], enteredFeedback: enteredMap([fb]))
        XCTAssertEqual(agg.avgRPE, 9)
        XCTAssertEqual(agg.worstFormRaw, FormQuality.sloppy.rawValue)
        XCTAssertEqual(agg.gassedFraction, 1)
        XCTAssertNotNil(fb.enteredSummary)
    }
}
