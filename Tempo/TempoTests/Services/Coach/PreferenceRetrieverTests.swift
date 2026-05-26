//
// PreferenceRetrieverTests.swift
// Tempo
//
// Coach v2.1 Phase 4a — covers LearnedOutcome computed accessors AND the
// PreferenceRetriever's ranking + scope-filtering + outcome-adjustment +
// safety-rail-always-surface behavior.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PreferenceRetrieverTests: XCTestCase {
    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LearnedPreference.self, LearnedOutcome.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - LearnedOutcome

    func testOutcome_isGradedReflectsBothFields() {
        let pending = LearnedOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "moveMeal",
            actionSummary: "x",
            evaluationDueAt: Date()
        )
        XCTAssertFalse(pending.isGraded)

        pending.outcome = .goodSleep
        pending.gradedAt = Date()
        XCTAssertTrue(pending.isGraded)
    }

    func testOutcome_polarityMaps() {
        let row = LearnedOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "x",
            actionSummary: "x",
            evaluationDueAt: Date(),
            outcome: .goodSleep,
            gradedAt: Date()
        )
        XCTAssertTrue(row.isPositive)
        XCTAssertFalse(row.isNegative)

        row.outcome = .badSleep
        XCTAssertFalse(row.isPositive)
        XCTAssertTrue(row.isNegative)

        row.outcome = .unclear
        XCTAssertFalse(row.isPositive)
        XCTAssertFalse(row.isNegative)
    }

    func testOutcome_userOverrideForcesNegative() {
        let row = LearnedOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "x",
            actionSummary: "x",
            evaluationDueAt: Date(),
            outcome: .goodSleep,
            gradedAt: Date(),
            userOverride: true
        )
        XCTAssertTrue(row.isNegative, "user-flagged regret must be negative even if AI graded positive")
    }

    // MARK: - Scope matching

    func testScopes_alwaysIncluded() {
        let scopes = PreferenceRetriever.scopes(matchingToday: Date(), dayType: nil)
        XCTAssertTrue(scopes.contains(.always))
    }

    func testScopes_weekdayVsWeekend() {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 25 // Monday
        let monday = Calendar(identifier: .gregorian).date(from: components)!
        let mondayScopes = PreferenceRetriever.scopes(matchingToday: monday, dayType: nil)
        XCTAssertTrue(mondayScopes.contains(.weekday))
        XCTAssertFalse(mondayScopes.contains(.weekend))

        components.day = 23 // Saturday
        let saturday = Calendar(identifier: .gregorian).date(from: components)!
        let satScopes = PreferenceRetriever.scopes(matchingToday: saturday, dayType: nil)
        XCTAssertTrue(satScopes.contains(.weekend))
        XCTAssertFalse(satScopes.contains(.weekday))
    }

    func testScopes_dayTypeMapping() {
        let date = Date()
        let strength = PreferenceRetriever.scopes(matchingToday: date, dayType: .strength)
        XCTAssertTrue(strength.contains(.dayTypeHard))

        let rest = PreferenceRetriever.scopes(matchingToday: date, dayType: .rest)
        XCTAssertTrue(rest.contains(.dayTypeRest))

        let soccer = PreferenceRetriever.scopes(matchingToday: date, dayType: .soccer)
        XCTAssertTrue(soccer.contains(.dayTypeHard))
        XCTAssertTrue(soccer.contains(.eventMatch))
    }

    func testScopes_seasonalSummer() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        let summer = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertTrue(PreferenceRetriever.scopes(matchingToday: summer, dayType: nil).contains(.seasonalSummer))

        components.month = 1
        let winter = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertFalse(PreferenceRetriever.scopes(matchingToday: winter, dayType: nil).contains(.seasonalSummer))
    }

    // MARK: - Tokenizer + subjectRelevance

    func testTokenize_lowercaseAndPunctuationStripping() {
        let tokens = PreferenceRetriever.tokenize("Soccer, AT 7pm! tonight?")
        XCTAssertTrue(tokens.contains("soccer"), "lowercased")
        XCTAssertTrue(tokens.contains("tonight"), "trailing ? stripped")
        XCTAssertTrue(tokens.contains("7pm"), "numerics + alphabet preserved")
        XCTAssertTrue(tokens.contains("at"), "two-letter words pass the >=2 filter (am/pm/ok useful too)")
        // Single-character tokens dropped:
        let oneCharTokens = tokens.filter { $0.count == 1 }
        XCTAssertTrue(oneCharTokens.isEmpty, "single-char tokens filtered")
    }

    func testSubjectRelevance_directMatchScoresHigh() {
        let tokens = PreferenceRetriever.tokenize("what should I do for dinner tonight")
        let score = PreferenceRetriever.subjectRelevance(
            subject: "meal_timing.dinner",
            messageTokens: tokens
        )
        XCTAssertGreaterThan(score, 0.0)
    }

    func testSubjectRelevance_synonymExpansion() {
        // The word "lift" should match training.* via synonym map.
        let tokens = PreferenceRetriever.tokenize("can I lift today")
        let score = PreferenceRetriever.subjectRelevance(
            subject: "training.match_days",
            messageTokens: tokens
        )
        XCTAssertGreaterThan(score, 0.0, "training synonyms must boost relevance")
    }

    func testSubjectRelevance_emptyMessageNoMatch() {
        let score = PreferenceRetriever.subjectRelevance(
            subject: "meal_timing.dinner",
            messageTokens: []
        )
        XCTAssertEqual(score, 0.0)
    }

    // MARK: - recencyWeight

    func testRecencyWeight_seenTodayIsOne() {
        let now = Date()
        let weight = PreferenceRetriever.recencyWeight(lastSeen: now, today: now)
        XCTAssertEqual(weight, 1.0, accuracy: 0.001)
    }

    func testRecencyWeight_halfLifeDecay() {
        let now = Date()
        let fourteenDaysAgo = now.addingTimeInterval(-14 * 86_400)
        let weight = PreferenceRetriever.recencyWeight(lastSeen: fourteenDaysAgo, today: now)
        // half-life at 14 days → ~0.5
        XCTAssertEqual(weight, 0.5, accuracy: 0.01)
    }

    func testRecencyWeight_floor() {
        let now = Date()
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let weight = PreferenceRetriever.recencyWeight(lastSeen: yearAgo, today: now)
        XCTAssertEqual(weight, 0.1, accuracy: 0.001, "must clamp at 0.1 floor")
    }

    // MARK: - outcomeAdjustment

    func testOutcomeAdjustment_positiveBoosts() {
        let good = LearnedOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "x",
            actionSummary: "x",
            evaluationDueAt: Date(),
            outcome: .goodSleep,
            gradedAt: Date()
        )
        let adjust = PreferenceRetriever.outcomeAdjustment(from: [good])
        XCTAssertEqual(adjust, PreferenceRetriever.outcomeBoostPerPositive, accuracy: 0.001)
    }

    func testOutcomeAdjustment_negativeDrags() {
        let bad = LearnedOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "x",
            actionSummary: "x",
            evaluationDueAt: Date(),
            outcome: .badSleep,
            gradedAt: Date()
        )
        let adjust = PreferenceRetriever.outcomeAdjustment(from: [bad])
        XCTAssertEqual(adjust, -PreferenceRetriever.outcomeDragPerNegative, accuracy: 0.001)
    }

    func testOutcomeAdjustment_capsAt30Percent() {
        // 10 bad outcomes would naively drag by 1.0; the cap clamps to 0.30.
        let many: [LearnedOutcome] = (0..<10).map { _ in
            LearnedOutcome(
                decisionConvID: UUID(),
                decisionTurnIndex: 0,
                actionToolName: "x",
                actionSummary: "x",
                evaluationDueAt: Date(),
                outcome: .badSleep,
                gradedAt: Date()
            )
        }
        let adjust = PreferenceRetriever.outcomeAdjustment(from: many)
        XCTAssertEqual(adjust, -0.30, accuracy: 0.001)
    }

    func testOutcomeAdjustment_pendingOutcomesIgnored() {
        let pending = LearnedOutcome(
            decisionConvID: UUID(),
            decisionTurnIndex: 0,
            actionToolName: "x",
            actionSummary: "x",
            evaluationDueAt: Date()
            // outcome: nil, gradedAt: nil
        )
        let adjust = PreferenceRetriever.outcomeAdjustment(from: [pending])
        XCTAssertEqual(adjust, 0.0)
    }

    // MARK: - retrieve — end-to-end

    func testRetrieve_filtersInactive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let active = LearnedPreference(text: "x", subject: "tone.style", source: .explicit)
        let inactive = LearnedPreference(text: "y", subject: "tone.style", source: .explicit, isActive: false)
        context.insert(active)
        context.insert(inactive)
        try context.save()

        let results = PreferenceRetriever.retrieve(forContext: context)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, active.id)
    }

    func testRetrieve_alwaysScopeAlwaysIncluded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let always = LearnedPreference(text: "x", subject: "tone.style", source: .explicit, scope: .always)
        context.insert(always)
        try context.save()

        let results = PreferenceRetriever.retrieve(forContext: context, today: Date(), dayType: nil)
        XCTAssertTrue(results.contains { $0.id == always.id })
    }

    func testRetrieve_avoidAtAllCostsSurfacesEvenOnOffScopeDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // dayTypeRest-scoped avoid that wouldn't normally match a strength day.
        let rail = LearnedPreference(
            text: "never IF",
            subject: "red_lines.never_suggest",
            source: .userVerified,
            polarity: .avoidAtAllCosts,
            scope: .dayTypeRest
        )
        context.insert(rail)
        try context.save()

        let results = PreferenceRetriever.retrieve(
            forContext: context,
            today: Date(),
            dayType: .strength
        )
        XCTAssertTrue(
            results.contains { $0.id == rail.id },
            "avoidAtAllCosts must surface regardless of scope match"
        )
    }

    func testRetrieve_scopeFilteredOutWhenMismatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let restOnly = LearnedPreference(
            text: "easy day fuel",
            subject: "meal_prefs.cuisines.likes",
            source: .observed,
            polarity: .positive,
            scope: .dayTypeRest
        )
        context.insert(restOnly)
        try context.save()

        let resultsOnHardDay = PreferenceRetriever.retrieve(
            forContext: context,
            today: Date(),
            dayType: .strength
        )
        XCTAssertFalse(resultsOnHardDay.contains { $0.id == restOnly.id })

        let resultsOnRestDay = PreferenceRetriever.retrieve(
            forContext: context,
            today: Date(),
            dayType: .rest
        )
        XCTAssertTrue(resultsOnRestDay.contains { $0.id == restOnly.id })
    }

    func testRetrieve_rankedByConfidenceAndRecency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()
        let monthAgo = now.addingTimeInterval(-30 * 86_400)

        // High confidence but old → outranked by mid confidence + fresh.
        let stale = LearnedPreference(
            text: "stale",
            subject: "tone.style",
            source: .observed,
            confidence: 0.95,
            lastSeenAt: monthAgo
        )
        let fresh = LearnedPreference(
            text: "fresh",
            subject: "tone.style",
            source: .observed,
            confidence: 0.70,
            lastSeenAt: now
        )
        context.insert(stale)
        context.insert(fresh)
        try context.save()

        let results = PreferenceRetriever.retrieve(forContext: context, today: now)
        XCTAssertEqual(results.first?.id, fresh.id, "freshness must beat slightly higher stale confidence")
    }

    func testRetrieve_outcomeDragLowersRanking() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()

        // Two same-everything prefs; only outcomes differ.
        let goodHistory = LearnedPreference(
            text: "good",
            subject: "tone.style",
            source: .observed,
            confidence: 0.70,
            lastSeenAt: now
        )
        let badHistory = LearnedPreference(
            text: "bad",
            subject: "tone.style",
            source: .observed,
            confidence: 0.70,
            lastSeenAt: now
        )
        context.insert(goodHistory)
        context.insert(badHistory)

        // Three bad outcomes on badHistory → drag (capped).
        for _ in 0..<3 {
            let outcome = LearnedOutcome(
                decisionPrefID: badHistory.id,
                decisionConvID: UUID(),
                decisionTurnIndex: 0,
                actionToolName: "moveMeal",
                actionSummary: "x",
                evaluationDueAt: now,
                outcome: .badSleep,
                gradedAt: now
            )
            context.insert(outcome)
        }
        try context.save()

        let results = PreferenceRetriever.retrieve(forContext: context, today: now)
        let goodIndex = results.firstIndex { $0.id == goodHistory.id } ?? .max
        let badIndex = results.firstIndex { $0.id == badHistory.id } ?? .max
        XCTAssertLessThan(goodIndex, badIndex, "preference with negative outcomes must rank lower")
    }

    func testRetrieve_limitCapped() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for i in 0..<50 {
            let pref = LearnedPreference(
                text: "p\(i)",
                subject: "tone.style",
                source: .observed
            )
            context.insert(pref)
        }
        try context.save()

        let results = PreferenceRetriever.retrieve(forContext: context, limit: 10)
        XCTAssertEqual(results.count, 10)
    }
}
