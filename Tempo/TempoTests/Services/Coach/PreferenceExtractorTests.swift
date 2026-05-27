//
// PreferenceExtractorTests.swift
// Tempo
//
// Coach v2.1 Phase 4c — covers extractor dedupe, confidence floor,
// cap enforcement, silent-AI-failure, and Jaccard-based duplicate detection.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PreferenceExtractorTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LearnedPreference.self, LearnedOutcome.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Deterministic AI stub returning a hardcoded candidate list.
    private struct StubAIClient: PreferenceExtractionAIClient {
        let candidates: [PreferenceCandidate]
        func extractPreferences(prompt _: String) async throws -> [PreferenceCandidate] {
            candidates
        }
    }

    private struct FailingAIClient: PreferenceExtractionAIClient {
        struct Failure: Error {}
        func extractPreferences(prompt _: String) async throws -> [PreferenceCandidate] {
            throw Failure()
        }
    }

    private func makeTranscript(turns: Int = 3) -> CoachTranscript {
        let lines = (0..<turns).map { i in
            CoachTranscript.Turn(
                role: i.isMultiple(of: 2) ? "user" : "assistant",
                text: "turn \(i) text"
            )
        }
        return CoachTranscript(id: UUID(), turns: lines)
    }

    // MARK: - Happy path

    func testExtract_persistsCandidatesAsPreferences() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = makeTranscript()
        let candidates = [
            PreferenceCandidate(
                text: "user never eats before 11am",
                subject: "meal_timing.breakfast.skipped",
                confidence: 0.9,
                source: .explicit,
                polarity: .positive,
                scope: .always,
                turnIndex: 0,
                evidence: "I never eat before 11"
            )
        ]
        let stub = StubAIClient(candidates: candidates)
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: stub,
            context: context
        )
        XCTAssertEqual(report.proposed, 1)
        XCTAssertEqual(report.reinforced, 0)
        let rows = try context.fetch(FetchDescriptor<LearnedPreference>())
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.subject, "meal_timing.breakfast.skipped")
        XCTAssertEqual(row.source, .explicit)
        XCTAssertEqual(row.evidenceConvId, transcript.id)
        XCTAssertEqual(row.evidenceTurnIndex, 0)
    }

    // MARK: - Confidence floor

    func testExtract_filtersBelowExplicitFloor() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = makeTranscript()
        // explicit floor is 0.6 — 0.55 should be skipped.
        let candidates = [
            PreferenceCandidate(
                text: "weak signal",
                subject: "tone.style",
                confidence: 0.55,
                source: .explicit,
                polarity: .positive,
                scope: .always,
                turnIndex: nil,
                evidence: nil
            )
        ]
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: StubAIClient(candidates: candidates),
            context: context
        )
        XCTAssertEqual(report.skippedBelowFloor, 1)
        XCTAssertEqual(report.proposed, 0)
    }

    func testExtract_acceptsInferredAt0p4Floor() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = makeTranscript()
        let candidates = [
            PreferenceCandidate(
                text: "soft inference",
                subject: "tone.style",
                confidence: 0.40,
                source: .inferred,
                polarity: .positive,
                scope: .always,
                turnIndex: nil,
                evidence: nil
            )
        ]
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: StubAIClient(candidates: candidates),
            context: context
        )
        XCTAssertEqual(report.proposed, 1)
    }

    // MARK: - Cap

    func testExtract_capsAtMaxPerConversation() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = makeTranscript()
        // 10 candidates → cap at 5.
        let candidates = (0..<10).map { i in
            PreferenceCandidate(
                text: "preference \(i)",
                subject: "tone.note_\(i)",
                confidence: 0.9,
                source: .explicit,
                polarity: .positive,
                scope: .always,
                turnIndex: nil,
                evidence: nil
            )
        }
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: StubAIClient(candidates: candidates),
            context: context
        )
        XCTAssertEqual(report.proposed, PreferenceExtractor.maxPerConversation)
    }

    // MARK: - Dedupe + reinforcement

    func testExtract_reinforcesDuplicateInsteadOfInserting() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = makeTranscript()
        // Pre-seed an active pref with the same subject + similar text.
        let existing = LearnedPreference(
            text: "user never eats before 11am",
            subject: "meal_timing.breakfast.skipped",
            source: .explicit,
            confidence: 0.85,
            evidenceCount: 2
        )
        context.insert(existing)
        try context.save()

        let candidates = [
            PreferenceCandidate(
                text: "user never eats before 11am", // exact duplicate
                subject: "meal_timing.breakfast.skipped",
                confidence: 0.9,
                source: .explicit,
                polarity: .positive,
                scope: .always,
                turnIndex: 0,
                evidence: nil
            )
        ]
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: StubAIClient(candidates: candidates),
            context: context
        )
        XCTAssertEqual(report.reinforced, 1)
        XCTAssertEqual(report.proposed, 0)
        XCTAssertEqual(existing.evidenceCount, 3)
        let rows = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertEqual(rows.count, 1)
    }

    func testExtract_doesNotDedupeAcrossDifferentSubjects() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = makeTranscript()
        let existing = LearnedPreference(
            text: "user prefers chicken",
            subject: "meal_prefs.cuisines.likes",
            source: .explicit,
            confidence: 0.85
        )
        context.insert(existing)
        try context.save()

        let candidates = [
            PreferenceCandidate(
                text: "user prefers chicken", // same text, different subject
                subject: "dislikes.food.fish",
                confidence: 0.85,
                source: .explicit,
                polarity: .negative,
                scope: .always,
                turnIndex: nil,
                evidence: nil
            )
        ]
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: StubAIClient(candidates: candidates),
            context: context
        )
        XCTAssertEqual(report.proposed, 1, "different subject → not a dupe")
    }

    // MARK: - Failure mode

    func testExtract_silentFailureReturnsReportWithoutThrow() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = makeTranscript()
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: FailingAIClient(),
            context: context
        )
        XCTAssertTrue(report.aiFailed)
        XCTAssertEqual(report.proposed, 0)
        let rows = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertEqual(rows.count, 0)
    }

    func testExtract_emptyTranscriptShortCircuits() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transcript = CoachTranscript(id: UUID(), turns: [])
        // Even with a failing client, no AI call should fire on empty transcript.
        let report = try await PreferenceExtractor.extract(
            from: transcript,
            using: FailingAIClient(),
            context: context
        )
        XCTAssertEqual(report, PreferenceExtractor.RunReport())
    }

    // MARK: - Jaccard

    func testJaccard_disjointSetsScoreZero() {
        let a: Set<String> = ["never", "eats", "breakfast"]
        let b: Set<String> = ["lifts", "tuesdays"]
        XCTAssertEqual(PreferenceExtractor.jaccard(a, b), 0.0, accuracy: 0.001)
    }

    func testJaccard_identicalSetsScoreOne() {
        let a: Set<String> = ["never", "eats", "breakfast"]
        XCTAssertEqual(PreferenceExtractor.jaccard(a, a), 1.0, accuracy: 0.001)
    }

    func testJaccard_partialOverlap() {
        let a: Set<String> = ["one", "two", "three", "four"]
        let b: Set<String> = ["three", "four", "five", "six"]
        // |intersection| = 2, |union| = 6 → 2/6 = 0.333…
        XCTAssertEqual(PreferenceExtractor.jaccard(a, b), 2.0 / 6.0, accuracy: 0.001)
    }

    // MARK: - Prompt shape

    func testExtractionPrompt_includesTranscriptAndSchema() {
        let transcript = CoachTranscript(
            id: UUID(),
            turns: [
                .init(role: "user", text: "I never eat before 11am"),
                .init(role: "assistant", text: "Got it.")
            ]
        )
        let prompt = PreferenceExtractor.extractionPrompt(for: transcript)
        XCTAssertTrue(prompt.contains("I never eat before 11am"))
        XCTAssertTrue(prompt.contains("Output JSON array"))
        XCTAssertTrue(prompt.contains("explicit"))
        XCTAssertTrue(prompt.contains("Cap at 5"))
    }
}
