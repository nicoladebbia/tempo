//
// PreferenceRetrieverTests.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Unit tests for the ranker that selects which LearnedPreferences land in
// the assembler's context block. Pure logic — no SwiftData container needed.
//
// Per `.plans/coach-agent-plan.md` Phase 4.

import Foundation
@testable import Tempo
import Testing

@MainActor
struct PreferenceRetrieverTests {

    private func makePref(
        text: String,
        subject: String,
        confidence: Double = 0.7,
        source: LearnedPreference.Source = .observed,
        userVerified: Bool = false,
        lastSeenDaysAgo: Double = 0,
        isActive: Bool = true,
        supersededAt: Date? = nil
    ) -> LearnedPreference {
        let lastSeen = Date().addingTimeInterval(-lastSeenDaysAgo * 86_400)
        return LearnedPreference(
            text: text,
            subject: subject,
            confidence: confidence,
            source: source,
            firstSeenAt: lastSeen,
            lastSeenAt: lastSeen,
            supersededAt: supersededAt,
            isActive: isActive,
            userVerified: userVerified
        )
    }

    // MARK: - Tokenize

    @Test func tokenizeDropsStopwordsAndShortTokens() {
        let tokens = PreferenceRetriever.tokenize("What should I eat for dinner tonight?")
        #expect(tokens.contains("dinner"))
        #expect(tokens.contains("eat"))
        #expect(tokens.contains("tonight"))
        #expect(!tokens.contains("what"))     // stopword
        #expect(!tokens.contains("should"))   // stopword
        #expect(!tokens.contains("for"))      // stopword
        #expect(!tokens.contains("i"))        // short
    }

    @Test func tokenizeLowercasesAndStripsPunctuation() {
        let tokens = PreferenceRetriever.tokenize("Eggs, bacon — RIGHT?")
        #expect(tokens.contains("eggs"))
        #expect(tokens.contains("bacon"))
        #expect(tokens.contains("right"))
    }

    // MARK: - Filtering inactive

    @Test func retrieveExcludesInactivePreferences() {
        let prefs = [
            makePref(text: "Loves pasta", subject: "meal_content.cuisine"),
            makePref(
                text: "Old pasta hate",
                subject: "meal_content.cuisine",
                isActive: false
            ),
        ]
        let out = PreferenceRetriever.retrieve(for: "pasta tonight?", from: prefs)
        #expect(out.count == 1)
        #expect(out.first?.text == "Loves pasta")
    }

    @Test func retrieveExcludesSupersededPreferences() {
        let prefs = [
            makePref(
                text: "Dinner at 7pm (old)",
                subject: "meal_timing.dinner",
                supersededAt: Date()
            ),
            makePref(text: "Dinner at 8pm", subject: "meal_timing.dinner"),
        ]
        let out = PreferenceRetriever.retrieve(for: "what time is dinner", from: prefs)
        #expect(out.count == 1)
        #expect(out.first?.text == "Dinner at 8pm")
    }

    // MARK: - Ranking signals

    @Test func subjectOverlapRanksHigherThanGeneric() {
        let prefs = [
            makePref(text: "Hates mushrooms", subject: "meal_content.ingredients.disliked"),
            makePref(text: "Bedtime 23:00", subject: "sleep.bedtime"),
        ]
        let out = PreferenceRetriever.retrieve(for: "what should I eat — no mushrooms please", from: prefs)
        #expect(out.first?.text == "Hates mushrooms")
    }

    @Test func userVerifiedFlagBoostsScore() {
        let pinned = makePref(
            text: "Always bedtime 23:00",
            subject: "sleep.bedtime",
            confidence: 0.5,
            userVerified: true
        )
        let unrelated = makePref(
            text: "Likes spicy food",
            subject: "meal_content.cuisine",
            confidence: 0.5
        )
        let out = PreferenceRetriever.retrieve(for: "anything to know about me?", from: [unrelated, pinned])
        #expect(out.first?.id == pinned.id)
    }

    @Test func recentEvidenceBeatsStale() {
        let recent = makePref(
            text: "Dinner around 20:00",
            subject: "meal_timing.dinner",
            confidence: 0.6,
            lastSeenDaysAgo: 1
        )
        let stale = makePref(
            text: "Dinner around 19:00",
            subject: "meal_timing.dinner",
            confidence: 0.6,
            lastSeenDaysAgo: 180
        )
        let out = PreferenceRetriever.retrieve(for: "when do I eat dinner", from: [stale, recent])
        #expect(out.first?.id == recent.id)
    }

    // MARK: - Limit

    @Test func retrieveRespectsCustomLimit() {
        let prefs = (0..<20).map { i in
            makePref(text: "Pref \(i)", subject: "meal_timing.dinner")
        }
        let out = PreferenceRetriever.retrieve(for: "dinner", from: prefs, limit: 5)
        #expect(out.count == 5)
    }

    @Test func retrieveDefaultLimitIsTwelve() {
        let prefs = (0..<20).map { i in
            makePref(text: "Pref \(i)", subject: "meal_timing.dinner")
        }
        let out = PreferenceRetriever.retrieve(for: "dinner", from: prefs)
        #expect(out.count == 12)
    }

    // MARK: - Determinism

    @Test func retrieveIsDeterministicForTiedScores() {
        let a = makePref(text: "Same A", subject: "sleep.bedtime", confidence: 0.5)
        let b = makePref(text: "Same B", subject: "sleep.bedtime", confidence: 0.5)
        let firstRun = PreferenceRetriever.retrieve(for: "anything?", from: [a, b])
        let secondRun = PreferenceRetriever.retrieve(for: "anything?", from: [b, a])
        #expect(firstRun.map(\.id) == secondRun.map(\.id))
    }
}
