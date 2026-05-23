//
// PreferenceExtractorTests.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Tests for the post-conversation preference extractor. The Haiku call
// itself is not mocked — instead we drive `parse` + `persist` directly
// with canned Claude responses, which is where 100% of the dedup /
// supersede / cap-enforcement logic lives.
//
// Per `.plans/coach-agent-plan.md` Phase 4.

import Foundation
@testable import Tempo
import SwiftData
import Testing

@MainActor
private func makeExtractorContainer() throws -> ModelContainer {
    let schema = Schema([
        LearnedPreference.self,
        PlannedMeal.self,
        WeeklyMealPlan.self,
        MealPreset.self,
        MealFoodItem.self,
        MealLog.self,
        NutritionTarget.self,
        DietaryProfile.self,
        Recipe.self,
        RecipeIngredient.self,
        RecipeStep.self,
        CachedFood.self,
        MealFeedback.self,
        PantryItem.self,
        Receipt.self,
        ReceiptLineItem.self,
        GroceryList.self,
        GroceryListItem.self,
        UserProfile.self,
        UserSettings.self,
    ])
    return try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
}

@MainActor
private func makeExtractor() -> PreferenceExtractor {
    PreferenceExtractor(apiClient: APIClient())
}

// MARK: - JSON extraction

@MainActor
struct PreferenceExtractorJSONTests {

    @Test func extractJSONStripsLeadingPreamble() {
        let raw = """
        Sure! Here's the JSON:
        {"preferences": []}
        """
        let cleaned = PreferenceExtractor.extractJSON(raw)
        #expect(cleaned == "{\"preferences\": []}")
    }

    @Test func extractJSONStripsTrailingProse() {
        let raw = "{\"preferences\": [{\"text\":\"x\",\"subject\":\"s\",\"confidence\":0.8,\"source\":\"explicit\"}]}\nLet me know!"
        let cleaned = PreferenceExtractor.extractJSON(raw)
        #expect(cleaned.hasPrefix("{"))
        #expect(cleaned.hasSuffix("}"))
        #expect(!cleaned.contains("Let me know"))
    }

    @Test func parseDecodesValidPayload() throws {
        let extractor = makeExtractor()
        let json = """
        {
          "preferences": [
            {"text":"Bedtime 23:00","subject":"sleep.bedtime","confidence":0.9,"source":"explicit"}
          ]
        }
        """
        let result = try extractor.parse(jsonText: json)
        #expect(result.preferences.count == 1)
        #expect(result.preferences.first?.subject == "sleep.bedtime")
    }

    @Test func parseThrowsOnMalformedJSON() {
        let extractor = makeExtractor()
        do {
            _ = try extractor.parse(jsonText: "not json at all")
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }
}

// MARK: - Persist

@MainActor
struct PreferenceExtractorPersistTests {

    private func makeParsed(_ entries: [PreferenceExtractor.Parsed]) -> PreferenceExtractor.ParsedResponse {
        PreferenceExtractor.ParsedResponse(preferences: entries)
    }

    @Test func persistInsertsNewPreferences() throws {
        let container = try makeExtractorContainer()
        let context = container.mainContext
        let extractor = makeExtractor()
        let parsed = makeParsed([
            .init(
                text: "Lights out by 23:00",
                subject: "sleep.bedtime",
                confidence: 0.9,
                source: "explicit",
                supersedes: nil
            ),
        ])
        let inserted = extractor.persist(
            parsed: parsed,
            existing: [],
            conversationID: UUID(),
            context: context
        )
        #expect(inserted.count == 1)
        #expect(inserted.first?.source == .explicit)
        #expect(inserted.first?.sourceConversationID != nil)
    }

    @Test func persistDedupesIdenticalSubjectAndText() throws {
        let container = try makeExtractorContainer()
        let context = container.mainContext
        let extractor = makeExtractor()
        let existing = LearnedPreference(
            text: "Lights out by 23:00",
            subject: "sleep.bedtime",
            confidence: 0.7,
            source: .observed,
            evidenceCount: 1
        )
        context.insert(existing)

        let parsed = makeParsed([
            .init(
                text: "lights out by 23:00",  // case-insensitive dup
                subject: "sleep.bedtime",
                confidence: 0.9,
                source: "explicit",
                supersedes: nil
            ),
        ])
        let inserted = extractor.persist(
            parsed: parsed,
            existing: [existing],
            conversationID: UUID(),
            context: context
        )
        #expect(inserted.isEmpty)
        #expect(existing.evidenceCount == 2) // reinforced
    }

    @Test func persistSupersedesPriorPreferenceByShortID() throws {
        let container = try makeExtractorContainer()
        let context = container.mainContext
        let extractor = makeExtractor()
        let oldPref = LearnedPreference(
            text: "Bedtime 22:00",
            subject: "sleep.bedtime",
            confidence: 0.8,
            source: .explicit
        )
        context.insert(oldPref)
        let shortID = String(oldPref.id.uuidString.prefix(8))

        let parsed = makeParsed([
            .init(
                text: "Bedtime 23:00 (new)",
                subject: "sleep.bedtime",
                confidence: 0.9,
                source: "explicit",
                supersedes: [shortID]
            ),
        ])
        _ = extractor.persist(
            parsed: parsed,
            existing: [oldPref],
            conversationID: UUID(),
            context: context
        )

        #expect(oldPref.supersededAt != nil)
        #expect(oldPref.isActive == false)
    }

    @Test func persistRejectsUnknownSource() throws {
        let container = try makeExtractorContainer()
        let context = container.mainContext
        let extractor = makeExtractor()
        let parsed = makeParsed([
            .init(
                text: "x", subject: "sleep.bedtime", confidence: 0.5,
                source: "nonsense", supersedes: nil
            ),
        ])
        let inserted = extractor.persist(
            parsed: parsed,
            existing: [],
            conversationID: UUID(),
            context: context
        )
        #expect(inserted.isEmpty)
    }

    @Test func persistCapsAtMaxPerCall() throws {
        let container = try makeExtractorContainer()
        let context = container.mainContext
        let extractor = makeExtractor()
        let parsed = makeParsed(
            (0..<20).map { i in
                .init(
                    text: "Pref \(i)",
                    subject: "meal_timing.dinner",
                    confidence: 0.5,
                    source: "observed",
                    supersedes: nil
                )
            }
        )
        let inserted = extractor.persist(
            parsed: parsed,
            existing: [],
            conversationID: UUID(),
            context: context
        )
        #expect(inserted.count == 8) // maxPreferencesPerCall
    }
}
