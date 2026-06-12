//
// OutcomeReviewIdempotencyTests.swift
// Tempo
//
// Phase 4 regression — the persisted-guard fix. The weekly outcome review and
// the AI cost-cap guards are keyed on PERSISTED AdaptiveProfile fields, not
// in-memory VM vars, precisely so a cold start within the same week can't
// re-run them. The original bug: an in-memory guard reset every launch, so
// applyOutcome COMPOUNDED against the persisted profile (×1.05 or ×0.9 per
// launch). This test pins the invariant: the same week key applies once.
//

@testable import Tempo
import XCTest

final class OutcomeReviewIdempotencyTests: XCTestCase {

    /// Reproduces the exact guard pattern runWeeklyOutcomeReview uses: only run
    /// (and only apply the outcome) when the persisted key differs from this
    /// week's key, then stamp the key.
    private func runGuardedApply(
        outcome: WeekOutcome,
        weekKey: String,
        profile: AdaptiveProfile
    ) {
        guard profile.lastOutcomeReviewWeekKey != weekKey else { return }
        AdaptiveProfileUpdater.applyOutcome(outcome, to: profile)
        profile.lastOutcomeReviewWeekKey = weekKey
    }

    func testOutcomeAppliesExactlyOncePerWeekAcrossRelaunches() {
        let profile = AdaptiveProfile()
        let exID = UUID()
        profile.learnedIncrements[exID] = 4.0

        let cleanWeek = WeekOutcome(
            progressionHits: 4, overreachEvents: 0, missedSessions: 0,
            netVolumeChange: 300, qualityScore: 0.9
        )

        // First "launch" this week — applies (4.0 → 4.2).
        runGuardedApply(outcome: cleanWeek, weekKey: "2026-06-01", profile: profile)
        let afterFirst = profile.learnedIncrements[exID]!
        XCTAssertGreaterThan(afterFirst, 4.0)

        // Four more "launches" the same week — guard blocks every one.
        for _ in 0 ..< 4 {
            runGuardedApply(outcome: cleanWeek, weekKey: "2026-06-01", profile: profile)
        }
        XCTAssertEqual(profile.learnedIncrements[exID]!, afterFirst, accuracy: 0.0001,
                       "Same week key must apply the outcome exactly once — no compounding")
    }

    func testNewWeekKeyAppliesAgain() {
        let profile = AdaptiveProfile()
        let exID = UUID()
        profile.learnedIncrements[exID] = 4.0
        let cleanWeek = WeekOutcome(
            progressionHits: 4, overreachEvents: 0, missedSessions: 0,
            netVolumeChange: 300, qualityScore: 0.9
        )
        runGuardedApply(outcome: cleanWeek, weekKey: "2026-06-01", profile: profile)
        let afterWeek1 = profile.learnedIncrements[exID]!
        // Next ISO week — a DIFFERENT key → applies again (this is correct).
        runGuardedApply(outcome: cleanWeek, weekKey: "2026-06-08", profile: profile)
        XCTAssertGreaterThan(profile.learnedIncrements[exID]!, afterWeek1,
                             "A genuinely new week should apply its own outcome")
    }
}
