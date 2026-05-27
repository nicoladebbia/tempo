//
// CoachMemoryGroupingTests.swift
// Tempo
//
// Coach v2.1 Phase 8b — covers polarity filtering + scope ordering +
// per-bucket sort used by CoachMemoryView's three-tab list. Visual
// rendering itself is verified by build-green + the morning manual-QA.
//

@testable import Tempo
import XCTest

final class CoachMemoryGroupingTests: XCTestCase {
    private func makePref(
        text: String,
        polarity: LearnedPreference.Polarity = .positive,
        scope: LearnedPreference.Scope = .always,
        confidence: Double = 0.7,
        lastSeenAt: Date = Date()
    ) -> LearnedPreference {
        LearnedPreference(
            text: text,
            subject: "tone.style",
            source: .observed,
            polarity: polarity,
            scope: scope,
            confidence: confidence,
            lastSeenAt: lastSeenAt
        )
    }

    // MARK: - Polarity filter

    func testGroup_filtersByPolarity() {
        let prefs = [
            makePref(text: "like", polarity: .positive),
            makePref(text: "dislike", polarity: .negative),
            makePref(text: "avoid", polarity: .avoidAtAllCosts),
        ]
        let likes = CoachMemoryGrouping.group(preferences: prefs, polarity: .positive)
        XCTAssertEqual(likes.flatMap(\.preferences).map(\.text), ["like"])

        let dislikes = CoachMemoryGrouping.group(preferences: prefs, polarity: .negative)
        XCTAssertEqual(dislikes.flatMap(\.preferences).map(\.text), ["dislike"])

        let avoids = CoachMemoryGrouping.group(preferences: prefs, polarity: .avoidAtAllCosts)
        XCTAssertEqual(avoids.flatMap(\.preferences).map(\.text), ["avoid"])
    }

    func testGroup_emptyWhenNoMatchingPolarity() {
        let prefs = [
            makePref(text: "x", polarity: .positive),
        ]
        XCTAssertTrue(
            CoachMemoryGrouping.group(preferences: prefs, polarity: .avoidAtAllCosts).isEmpty
        )
    }

    // MARK: - Scope ordering

    func testGroup_emitsScopeBucketsInCanonicalOrder() {
        let prefs = [
            makePref(text: "summer", scope: .seasonalSummer),
            makePref(text: "always", scope: .always),
            makePref(text: "match", scope: .eventMatch),
            makePref(text: "hard", scope: .dayTypeHard),
        ]
        let groups = CoachMemoryGrouping.group(preferences: prefs, polarity: .positive)
        XCTAssertEqual(groups.map(\.scope), [.always, .dayTypeHard, .eventMatch, .seasonalSummer])
    }

    func testGroup_omitsEmptyScopeBuckets() {
        let prefs = [
            makePref(text: "always-only", scope: .always),
        ]
        let groups = CoachMemoryGrouping.group(preferences: prefs, polarity: .positive)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.scope, .always)
    }

    // MARK: - Per-bucket sort

    func testGroup_sortsHighConfidenceFirstWithinScope() {
        let prefs = [
            makePref(text: "weak", confidence: 0.3),
            makePref(text: "strong", confidence: 0.9),
            makePref(text: "mid", confidence: 0.6),
        ]
        let groups = CoachMemoryGrouping.group(preferences: prefs, polarity: .positive)
        let texts = groups.first?.preferences.map(\.text) ?? []
        XCTAssertEqual(texts, ["strong", "mid", "weak"])
    }

    func testGroup_tieBreaksByRecency() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let weekAgo = now.addingTimeInterval(-86_400 * 7)
        let prefs = [
            makePref(text: "older", confidence: 0.7, lastSeenAt: weekAgo),
            makePref(text: "newer", confidence: 0.7, lastSeenAt: now),
            makePref(text: "middle", confidence: 0.7, lastSeenAt: yesterday),
        ]
        let groups = CoachMemoryGrouping.group(preferences: prefs, polarity: .positive)
        let texts = groups.first?.preferences.map(\.text) ?? []
        XCTAssertEqual(texts, ["newer", "middle", "older"])
    }

    // MARK: - Scope display labels

    func testScopeDisplayLabel_humanReadable() {
        XCTAssertEqual(LearnedPreference.Scope.always.displayLabel, "Always")
        XCTAssertEqual(LearnedPreference.Scope.weekday.displayLabel, "Weekdays")
        XCTAssertEqual(LearnedPreference.Scope.weekend.displayLabel, "Weekend")
        XCTAssertEqual(LearnedPreference.Scope.dayTypeHard.displayLabel, "Hard Training Days")
        XCTAssertEqual(LearnedPreference.Scope.dayTypeRest.displayLabel, "Rest Days")
        XCTAssertEqual(LearnedPreference.Scope.eventTravel.displayLabel, "Travel")
        XCTAssertEqual(LearnedPreference.Scope.eventMatch.displayLabel, "Match Days")
        XCTAssertEqual(LearnedPreference.Scope.seasonalSummer.displayLabel, "Summer")
    }

    func testPolarityDisplayLabel_humanReadable() {
        XCTAssertEqual(LearnedPreference.Polarity.positive.displayLabel, "Like")
        XCTAssertEqual(LearnedPreference.Polarity.negative.displayLabel, "Dislike")
        XCTAssertEqual(LearnedPreference.Polarity.avoidAtAllCosts.displayLabel, "Hard Avoid")
    }

    // MARK: - Canonical order completeness

    func testCanonicalScopeOrder_coversAllScopes() {
        let allKnown = Set(LearnedPreference.Scope.allCases)
        let canonical = Set(CoachMemoryGrouping.canonicalScopeOrder)
        XCTAssertEqual(allKnown, canonical, "canonical ordering must include every Scope case")
    }
}
