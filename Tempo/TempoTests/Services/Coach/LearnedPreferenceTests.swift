//
// LearnedPreferenceTests.swift
// Tempo
//
// Coach v2.1 Phase 2 — model behavior for LearnedPreference.
// Covers enum raw round-tripping, defaults-by-source/subject, reinforcement
// caps, decay differential between userVerified vs others, supersession,
// and below-floor deactivation.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class LearnedPreferenceTests: XCTestCase {
    // MARK: - Container helper

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LearnedPreference.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Defaults

    func testDefaultConfidence_bySource() {
        XCTAssertEqual(LearnedPreference.defaultConfidence(for: .explicit), 0.9, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultConfidence(for: .userVerified), 1.0, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultConfidence(for: .observed), 0.5, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultConfidence(for: .inferred), 0.4, accuracy: 0.001)
    }

    func testDefaultDecayRate_redLinesNeverDecay() {
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "red_lines.never_suggest"), 1.0, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "red_lines.medical_conditions"), 1.0, accuracy: 0.001)
    }

    func testDefaultDecayRate_goalsNeverDecay() {
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "goals.primary"), 1.0, accuracy: 0.001)
    }

    func testDefaultDecayRate_perPrefix() {
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "digestion.before_bed"), 0.99, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "meal_timing.breakfast"), 0.98, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "meal_prefs.cuisines.likes"), 0.97, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "dislikes.food.raisins"), 0.98, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "training.match_days"), 0.97, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "sleep.bedtime.actual"), 0.96, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "schedule.exceptions"), 0.95, accuracy: 0.001)
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "tone.style"), 0.99, accuracy: 0.001)
    }

    func testDefaultDecayRate_unknownPrefixFallback() {
        XCTAssertEqual(LearnedPreference.defaultDecayRate(for: "something.random"), 0.99, accuracy: 0.001)
    }

    func testInit_setsDefaultsFromSourceAndSubject() {
        let pref = LearnedPreference(
            text: "user dislikes raisins",
            subject: "dislikes.food.raisins",
            source: .explicit
        )
        XCTAssertEqual(pref.confidence, 0.9, accuracy: 0.001)
        XCTAssertEqual(pref.decayRate, 0.98, accuracy: 0.001)
        XCTAssertEqual(pref.source, .explicit)
        XCTAssertEqual(pref.polarity, .positive)
        XCTAssertEqual(pref.scope, .always)
        XCTAssertTrue(pref.isActive)
        XCTAssertEqual(pref.evidenceCount, 1)
    }

    func testInit_callerCanOverrideDefaults() {
        let pref = LearnedPreference(
            text: "needs 2.5h between dinner and sleep",
            subject: "digestion.before_bed",
            source: .observed,
            confidence: 0.65,
            decayRate: 1.0
        )
        XCTAssertEqual(pref.confidence, 0.65, accuracy: 0.001)
        XCTAssertEqual(pref.decayRate, 1.0, accuracy: 0.001)
    }

    func testInit_evidenceCountFloorOne() {
        let pref = LearnedPreference(
            text: "x",
            subject: "tone.style",
            source: .explicit,
            evidenceCount: 0
        )
        XCTAssertEqual(pref.evidenceCount, 1)
    }

    // MARK: - Enum raw round-trip via SwiftData

    func testSwiftDataRoundTrip_preservesEnumValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let prefID = UUID()
        let pref = LearnedPreference(
            id: prefID,
            text: "never suggest IF",
            subject: "red_lines.never_suggest",
            source: .userVerified,
            polarity: .avoidAtAllCosts,
            scope: .always
        )
        context.insert(pref)
        try context.save()

        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { $0.id == prefID }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        let row = try XCTUnwrap(fetched.first)
        XCTAssertEqual(row.source, .userVerified)
        XCTAssertEqual(row.polarity, .avoidAtAllCosts)
        XCTAssertEqual(row.scope, .always)
        XCTAssertEqual(row.decayRate, 1.0, accuracy: 0.001)
        XCTAssertEqual(row.confidence, 1.0, accuracy: 0.001)
    }

    // MARK: - markReinforced

    func testReinforced_bumpsConfidenceAndCount() {
        let pref = LearnedPreference(
            text: "lifts Tuesdays",
            subject: "training.match_days",
            source: .observed,
            confidence: 0.6,
            evidenceCount: 3
        )
        pref.markReinforced()
        XCTAssertEqual(pref.confidence, 0.65, accuracy: 0.001)
        XCTAssertEqual(pref.evidenceCount, 4)
    }

    func testReinforced_capsAtOne() {
        let pref = LearnedPreference(
            text: "x",
            subject: "tone.style",
            source: .observed,
            confidence: 0.98
        )
        pref.markReinforced()
        XCTAssertEqual(pref.confidence, 1.0, accuracy: 0.001)
        pref.markReinforced()
        XCTAssertEqual(pref.confidence, 1.0, accuracy: 0.001, "confidence must not exceed 1.0")
    }

    func testReinforced_userVerifiedStaysAtOneButAdvancesLastSeen() {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let pref = LearnedPreference(
            text: "vegetarian on Mondays",
            subject: "meal_prefs.cuisines.likes",
            source: .userVerified,
            confidence: 1.0,
            lastSeenAt: oldDate
        )
        pref.markReinforced()
        XCTAssertEqual(pref.confidence, 1.0, accuracy: 0.001)
        XCTAssertEqual(pref.evidenceCount, 2)
        XCTAssertGreaterThan(pref.lastSeenAt, oldDate)
    }

    // MARK: - supersede

    func testSupersede_marksInactiveAndRecordsReplacement() {
        let pref = LearnedPreference(
            text: "needs 2.5h dinner-to-sleep",
            subject: "digestion.before_bed",
            source: .observed,
            confidence: 0.8
        )
        XCTAssertTrue(pref.isActive)
        XCTAssertNil(pref.supersededBy)

        let newID = UUID()
        pref.supersede(by: newID)
        XCTAssertFalse(pref.isActive)
        XCTAssertEqual(pref.supersededBy, newID)
    }

    // MARK: - deactivate

    func testDeactivate_setsInactive() {
        let pref = LearnedPreference(
            text: "x",
            subject: "tone.style",
            source: .observed
        )
        pref.deactivate()
        XCTAssertFalse(pref.isActive)
    }

    // MARK: - markUserVerified

    func testMarkUserVerified_liftsConfidenceAndClearsReview() {
        let pref = LearnedPreference(
            text: "x",
            subject: "tone.style",
            source: .observed,
            confidence: 0.5,
            needsReview: true
        )
        pref.markUserVerified()
        XCTAssertEqual(pref.source, .userVerified)
        XCTAssertEqual(pref.confidence, 1.0, accuracy: 0.001)
        XCTAssertFalse(pref.needsReview)
    }

    // MARK: - applyDailyDecay

    func testDecay_singleDay() {
        let pref = LearnedPreference(
            text: "x",
            subject: "training.match_days",
            source: .observed,
            confidence: 1.0
        )
        // training.* decays at 0.97/day.
        pref.applyDailyDecay()
        XCTAssertEqual(pref.confidence, 0.97, accuracy: 0.001)
        XCTAssertTrue(pref.isActive)
    }

    func testDecay_userVerifiedImmune() {
        let pref = LearnedPreference(
            text: "vegetarian on Mondays",
            subject: "meal_prefs.cuisines.likes",
            source: .userVerified,
            confidence: 1.0
        )
        pref.applyDailyDecay(daysElapsed: 30)
        XCTAssertEqual(pref.confidence, 1.0, accuracy: 0.001, "userVerified rows are immune to decay")
        XCTAssertTrue(pref.isActive)
    }

    func testDecay_redLinesNeverDecay() {
        let pref = LearnedPreference(
            text: "tried IF, killed lifts",
            subject: "red_lines.never_suggest",
            source: .explicit,
            confidence: 0.9
        )
        // red_lines.* have decayRate 1.0 — no decay.
        pref.applyDailyDecay(daysElapsed: 365)
        XCTAssertEqual(pref.confidence, 0.9, accuracy: 0.001)
        XCTAssertTrue(pref.isActive)
    }

    func testDecay_belowFloorDeactivates() {
        let pref = LearnedPreference(
            text: "x",
            subject: "schedule.exceptions",
            source: .inferred,
            // schedule.* decays at 0.95/day. Starting at 0.21, one day →
            // 0.21 * 0.95 = 0.1995, which crosses below the 0.2 floor.
            confidence: 0.21
        )
        pref.applyDailyDecay()
        XCTAssertLessThan(pref.confidence, 0.2)
        XCTAssertFalse(pref.isActive, "below-floor confidence must auto-deactivate")
    }

    func testDecay_aboveFloorStaysActive() {
        let pref = LearnedPreference(
            text: "x",
            subject: "schedule.exceptions",
            source: .inferred,
            confidence: 0.50
        )
        pref.applyDailyDecay()
        XCTAssertGreaterThan(pref.confidence, 0.2)
        XCTAssertTrue(pref.isActive)
    }

    func testDecay_batchedAcrossMultipleDays() {
        let pref = LearnedPreference(
            text: "x",
            subject: "digestion.before_bed",
            source: .observed,
            confidence: 1.0
        )
        // digestion.* decays at 0.99/day. 7 days → 1.0 * 0.99^7 ≈ 0.932.
        pref.applyDailyDecay(daysElapsed: 7)
        XCTAssertEqual(pref.confidence, pow(0.99, 7.0), accuracy: 0.001)
        XCTAssertTrue(pref.isActive)
    }

    func testDecay_zeroDaysIsNoOp() {
        let pref = LearnedPreference(
            text: "x",
            subject: "tone.style",
            source: .observed,
            confidence: 0.7
        )
        pref.applyDailyDecay(daysElapsed: 0)
        XCTAssertEqual(pref.confidence, 0.7, accuracy: 0.001)
    }
}
