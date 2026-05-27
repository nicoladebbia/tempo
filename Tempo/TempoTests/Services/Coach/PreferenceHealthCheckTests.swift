//
// PreferenceHealthCheckTests.swift
// Tempo
//
// Coach v2.1 Phase 6c — covers contradiction flagging, clearing on
// recovered behavior, exclusion of userVerified + avoidAtAllCosts rows,
// the high-confidence floor, and the pending-review accessor.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PreferenceHealthCheckTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LearnedPreference.self,
            LearnedOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeOutcome(
        prefID: UUID,
        outcome: LearnedOutcome.Outcome,
        daysAgo: Int = 1
    ) -> LearnedOutcome {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return LearnedOutcome(
            decisionPrefID: prefID,
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "moveMeal",
            actionSummary: "x",
            decisionDate: date,
            evaluationDueAt: date,
            outcome: outcome,
            gradedAt: date
        )
    }

    // MARK: - Flagging

    func testScan_flagsHighConfidencePrefWithTwoNegativeOutcomes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "lift Tuesdays",
            subject: "training.match_days",
            source: .observed,
            confidence: 0.85
        )
        context.insert(pref)
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .abandoned))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 1)
        XCTAssertTrue(pref.needsReview)
    }

    func testScan_belowFloorIsNotFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "x",
            subject: "training.match_days",
            source: .observed,
            confidence: 0.50 // below 0.70 floor
        )
        context.insert(pref)
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .abandoned))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 0)
        XCTAssertFalse(pref.needsReview)
    }

    func testScan_singleNegativeBelowThresholdNotFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "x", subject: "training.match_days",
            source: .observed, confidence: 0.85
        )
        context.insert(pref)
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 0)
        XCTAssertFalse(pref.needsReview)
    }

    func testScan_positivesOutweighNegativesNotFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "x", subject: "training.match_days",
            source: .observed, confidence: 0.85
        )
        context.insert(pref)
        // 2 negative, 3 positive → not a contradiction signal.
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .abandoned))
        context.insert(makeOutcome(prefID: pref.id, outcome: .goodSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .goodWorkout))
        context.insert(makeOutcome(prefID: pref.id, outcome: .followedThrough))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 0)
        XCTAssertFalse(pref.needsReview)
    }

    func testScan_oldOutcomesOutsideWindowDoNotCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "x", subject: "training.match_days",
            source: .observed, confidence: 0.85
        )
        context.insert(pref)
        // Both negatives are 30 days ago — outside the 14-day window.
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep, daysAgo: 30))
        context.insert(makeOutcome(prefID: pref.id, outcome: .abandoned, daysAgo: 28))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 0)
        XCTAssertFalse(pref.needsReview)
    }

    // MARK: - Exclusions

    func testScan_userVerifiedNeverFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "vegetarian on Mondays",
            subject: "meal_prefs.cuisines.likes",
            source: .userVerified,
            confidence: 1.0
        )
        context.insert(pref)
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .abandoned))
        context.insert(makeOutcome(prefID: pref.id, outcome: .badWorkout))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 0, "user told us directly — never auto-flag")
        XCTAssertFalse(pref.needsReview)
    }

    func testScan_avoidAtAllCostsNeverFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "never IF",
            subject: "red_lines.never_suggest",
            source: .explicit,
            polarity: .avoidAtAllCosts,
            confidence: 0.95
        )
        context.insert(pref)
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .abandoned))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 0, "safety rails are not auto-flagged")
        XCTAssertFalse(pref.needsReview)
    }

    // MARK: - Clearing

    func testScan_clearsFlagWhenBehaviorRecovers() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "x", subject: "training.match_days",
            source: .observed, confidence: 0.85,
            needsReview: true // previously flagged
        )
        context.insert(pref)
        // Recent outcomes are net positive now → flag should clear.
        context.insert(makeOutcome(prefID: pref.id, outcome: .goodSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .goodWorkout))
        context.insert(makeOutcome(prefID: pref.id, outcome: .followedThrough))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.clearedExistingFlag, 1)
        XCTAssertFalse(pref.needsReview)
    }

    func testScan_doesNotDoubleFlagAlreadyFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "x", subject: "training.match_days",
            source: .observed, confidence: 0.85,
            needsReview: true
        )
        context.insert(pref)
        context.insert(makeOutcome(prefID: pref.id, outcome: .badSleep))
        context.insert(makeOutcome(prefID: pref.id, outcome: .abandoned))
        try context.save()

        let report = try PreferenceHealthCheck.scan(in: context)
        XCTAssertEqual(report.flagged, 0, "already flagged — no new flag fires")
        XCTAssertTrue(pref.needsReview, "but stays flagged")
    }

    // MARK: - Pending-review accessor

    func testPendingReviewPreferences_returnsActiveFlaggedSortedByRecency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()
        let pref1 = LearnedPreference(
            text: "older",
            subject: "tone.style",
            source: .observed,
            needsReview: true
        )
        pref1.lastSeenAt = now.addingTimeInterval(-86_400 * 7)
        let pref2 = LearnedPreference(
            text: "newer",
            subject: "tone.style",
            source: .observed,
            lastSeenAt: now,
            needsReview: true
        )
        let inactive = LearnedPreference(
            text: "inactive flagged",
            subject: "tone.style",
            source: .observed,
            needsReview: true,
            isActive: false
        )
        let unflagged = LearnedPreference(
            text: "active but no flag",
            subject: "tone.style",
            source: .observed
        )
        for p in [pref1, pref2, inactive, unflagged] { context.insert(p) }
        try context.save()

        let queue = PreferenceHealthCheck.pendingReviewPreferences(in: context)
        XCTAssertEqual(queue.count, 2, "inactive + unflagged must be filtered out")
        XCTAssertEqual(queue.first?.id, pref2.id, "most-recent-lastSeen first")
        XCTAssertEqual(queue.last?.id, pref1.id)
    }

    func testPendingReviewPreferences_emptyWhenNoneFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pref = LearnedPreference(
            text: "x", subject: "tone.style", source: .observed
        )
        context.insert(pref)
        try context.save()

        XCTAssertEqual(PreferenceHealthCheck.pendingReviewPreferences(in: context).count, 0)
    }
}
