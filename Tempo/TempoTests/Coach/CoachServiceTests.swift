//
// CoachServiceTests.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Tests for the Coach agent loop, tool dispatcher, model selection, and
// CoachConversation transcript encoding. The full `send()` round-trip
// against the backend is verified manually via the chat UI (TempoTests
// can't currently run from CLI). What's covered here is everything that
// doesn't need an HTTP stub: pure logic on inputs we control.
//
// Per `.plans/coach-agent-plan.md` Phase 6.

import Foundation
@testable import Tempo
import SwiftData
import Testing

@MainActor
private func makeServiceContainer() throws -> ModelContainer {
    let schema = Schema([
        LearnedPreference.self,
        CoachConversation.self,
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
struct CoachConversationCodecTests {

    @Test func appendingTurnsRoundTripsThroughJSON() {
        let convo = CoachConversation()
        convo.appendTurn(ChatTurn(role: "user", blocks: [.text("hello")]))
        convo.appendTurn(ChatTurn(role: "assistant", blocks: [
            .toolUse(name: "ask_user", id: "tu_1", inputJSON: "{\"question\":\"x\"}"),
        ]))
        convo.appendTurn(ChatTurn(role: "user", blocks: [
            .toolResult(toolUseID: "tu_1", isError: false, text: "answered"),
        ]))
        let turns = convo.turns()
        #expect(turns.count == 3)
        #expect(turns[0].role == "user")
        if case let .text(s) = turns[0].blocks[0] {
            #expect(s == "hello")
        } else {
            Issue.record("expected text block")
        }
        if case let .toolUse(name, id, _) = turns[1].blocks[0] {
            #expect(name == "ask_user")
            #expect(id == "tu_1")
        } else {
            Issue.record("expected tool_use block")
        }
    }

    @Test func transcriptTextRendersHumanReadable() {
        let convo = CoachConversation()
        convo.appendTurn(ChatTurn(role: "user", blocks: [.text("what's for dinner?")]))
        convo.appendTurn(ChatTurn(role: "assistant", blocks: [.text("pasta tonight.")]))
        let txt = convo.transcriptText()
        #expect(txt.contains("User:"))
        #expect(txt.contains("Assistant:"))
        #expect(txt.contains("pasta tonight"))
    }

    @Test func deriveTitleUsesFirstUserText() {
        let turns = [
            ChatTurn(role: "user", blocks: [.text("Should I skip dinner tonight given my recovery?")]),
            ChatTurn(role: "assistant", blocks: [.text("Let's see.")]),
        ]
        let title = CoachService.deriveTitle(from: turns)
        #expect(title.hasPrefix("Should I skip"))
    }

    @Test func deriveTitleFallsBackWhenEmpty() {
        #expect(CoachService.deriveTitle(from: []) == "Coach session")
    }
}

@MainActor
struct CoachServiceSystemPromptTests {

    @Test func systemPromptEmbedsSnapshot() {
        let prompt = CoachService.systemPrompt(snapshot: "## Identity\nName: Nicola")
        #expect(prompt.contains("Tempo Coach"))
        #expect(prompt.contains("Name: Nicola"))
    }

    @Test func systemPromptMentionsAskUserGuidance() {
        let prompt = CoachService.systemPrompt(snapshot: "")
        #expect(prompt.localizedCaseInsensitiveContains("askUser") || prompt.contains("ask_user"))
    }
}

@MainActor
struct CoachToolSchemaTests {

    @Test func allToolsHasExpectedSet() {
        let names = CoachToolSchema.allTools.map(\.name)
        #expect(names.contains("record_preference"))
        #expect(names.contains("update_preference"))
        #expect(names.contains("ask_user"))
        #expect(names.contains("shift_bedtime"))
        #expect(names.contains("move_meal"))
        #expect(names.contains("skip_meal"))
    }

    @Test func everyToolHasInputSchemaObject() {
        for tool in CoachToolSchema.allTools {
            if case .object = tool.inputSchema {
                continue
            }
            Issue.record("Tool \(tool.name) input_schema must be an object")
        }
    }
}

@MainActor
struct CoachToolDispatcherTests {

    private func string(_ s: String) -> NutritionProxyChatRequest.JSONValue { .string(s) }
    private func number(_ n: Double) -> NutritionProxyChatRequest.JSONValue { .number(n) }

    @Test func dispatchRecordPreferenceInsertsAndPushesUndo() throws {
        let container = try makeServiceContainer()
        let ctx = container.mainContext
        let convo = CoachConversation()
        ctx.insert(convo)
        try ctx.save()

        var undo: [CoachService.Undo] = []
        let input: NutritionProxyChatRequest.JSONValue = .object([
            "text": string("Hates eggs"),
            "subject": string(LearnedPreferenceSubject.mealContentDisliked),
            "confidence": number(0.9),
        ])

        let output = try CoachToolDispatcher.handleRecordPreference(
            dict: CoachToolDispatcher.inputAsDict(input),
            conversation: convo,
            modelContext: ctx,
            undoStack: &undo
        )
        #expect(!output.citedPreferenceIDs.isEmpty)
        #expect(undo.count == 1)
        #expect(BehaviorObserver.fetchActivePreferences(in: ctx).count == 1)
    }

    @Test func dispatchUnknownToolThrows() throws {
        let container = try makeServiceContainer()
        let ctx = container.mainContext
        let convo = CoachConversation()
        ctx.insert(convo)
        var undo: [CoachService.Undo] = []
        do {
            _ = try CoachToolDispatcher.dispatch(
                name: "nope",
                input: .object([:]),
                conversation: convo,
                modelContext: ctx,
                notifications: nil,
                undoStack: &undo
            )
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }

    @Test func dispatchAskUserSurfacesPendingQuestion() throws {
        let container = try makeServiceContainer()
        let ctx = container.mainContext
        let convo = CoachConversation()
        ctx.insert(convo)
        var undo: [CoachService.Undo] = []
        let input: NutritionProxyChatRequest.JSONValue = .object([
            "question": string("dinner at 7 or 8?"),
            "choices": .array([string("7"), string("8")]),
        ])
        let output = CoachToolDispatcher.handleAskUser(
            dict: CoachToolDispatcher.inputAsDict(input)
        )
        #expect(output.pendingQuestion != nil)
        #expect(output.pendingQuestion?.choices?.count == 2)
        _ = undo
    }
}

@MainActor
struct CoachServiceUndoTests {

    @Test func undoLastPopsAndApplies() throws {
        let container = try makeServiceContainer()
        let ctx = container.mainContext
        let service = CoachService(apiClient: APIClient(), modelContext: ctx)
        let convo = CoachConversation()
        ctx.insert(convo)

        // Mint a preference via the dispatcher (also queues an undo entry).
        var stack = service.undoStack
        _ = try CoachToolDispatcher.handleRecordPreference(
            dict: CoachToolDispatcher.inputAsDict(.object([
                "text": .string("Hates onions"),
                "subject": .string(LearnedPreferenceSubject.mealContentDisliked),
                "confidence": .number(0.9),
            ])),
            conversation: convo,
            modelContext: ctx,
            undoStack: &stack
        )
        // Bridge: copy stack onto the service. (CoachService.send() does
        // this internally via `inout`; for the test we drive the helper
        // directly so we replicate the wiring.)
        for entry in stack { service.undoStack.append(entry) }

        #expect(service.undoLabel != nil)
        #expect(BehaviorObserver.fetchActivePreferences(in: ctx).count == 1)
        _ = service.undoLast()
        #expect(BehaviorObserver.fetchActivePreferences(in: ctx).isEmpty)
        #expect(service.undoLabel == nil)
    }
}

