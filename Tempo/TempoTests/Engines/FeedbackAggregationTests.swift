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
}
