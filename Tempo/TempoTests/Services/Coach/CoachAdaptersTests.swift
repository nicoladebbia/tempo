//
// CoachAdaptersTests.swift
// Tempo
//
// Coach v2.1 Phase 7a — covers the three concrete adapters: chat AI,
// summarizer, and tool dispatcher. Adapters wire Phase 6b protocols
// against APIClient + CoachTools.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachAdaptersTests: XCTestCase {
    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WeeklyMealPlan.self,
            PlannedMeal.self,
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            LearnedPreference.self,
            LearnedOutcome.self,
            PendingOutcome.self,
            CoachConversation.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Stub requester

    final class StubRequester: APIRequester, @unchecked Sendable {
        var lastEndpointPath: String?
        var lastBodyJSON: Data?
        var responseProvider: (Any) -> Any = { _ in NSNull() }

        func request<Response: Decodable & Sendable, Body: Encodable & Sendable>(
            _ endpoint: APIEndpoint<Response>,
            body: Body
        ) async throws -> Response {
            lastEndpointPath = endpoint.path
            lastBodyJSON = try? JSONEncoder().encode(body)
            let result = responseProvider(body)
            if let typed = result as? Response { return typed }
            throw NSError(domain: "test", code: 1)
        }
    }

    // MARK: - CoachChatAIClientAdapter

    func testChatAdapter_sendsToCorrectEndpointAndMapsResponse() async throws {
        let requester = StubRequester()
        let responseBody = CoachChatProxyResponse(
            content: [
                .text("Got it."),
                .toolUse(id: "tc-1", name: "moveMeal", inputJSON: Data(#"{"mealID":"abc","newTimeHHmm":"20:30"}"#.utf8)),
            ],
            stopReason: "tool_use",
            usage: .init(inputTokens: 100, outputTokens: 50),
            model: "claude-haiku-4-5-20251001"
        )
        requester.responseProvider = { _ in responseBody }

        let adapter = CoachChatAIClientAdapter(requester: requester)
        let request = CoachChatRequest(
            systemPrompt: "sys",
            history: [CoachMessage(role: "user", text: "soccer at 7pm")],
            model: .haiku
        )
        let response = try await adapter.sendChat(request: request)

        XCTAssertEqual(requester.lastEndpointPath, "/v1/nutrition/ai/coach/chat")
        XCTAssertEqual(response.stopReason, .toolUse)
        XCTAssertEqual(response.content.count, 2)
        if case let .text(text) = response.content[0] {
            XCTAssertEqual(text, "Got it.")
        } else {
            XCTFail("expected text block first")
        }
        if case let .toolUse(id, name, _) = response.content[1] {
            XCTAssertEqual(id, "tc-1")
            XCTAssertEqual(name, "moveMeal")
        } else {
            XCTFail("expected tool_use block second")
        }
    }

    func testChatAdapter_skipsSystemSummaryTurns() async throws {
        let requester = StubRequester()
        requester.responseProvider = { _ in
            CoachChatProxyResponse(
                content: [.text("ok")],
                stopReason: "end_turn",
                usage: .init(inputTokens: 0, outputTokens: 0),
                model: "haiku"
            )
        }
        let adapter = CoachChatAIClientAdapter(requester: requester)
        let request = CoachChatRequest(
            systemPrompt: "sys",
            history: [
                CoachMessage(role: "system_summary", text: "earlier"),
                CoachMessage(role: "user", text: "hi"),
            ],
            model: .haiku
        )
        _ = try await adapter.sendChat(request: request)

        // Decode the wire body and confirm system_summary was filtered.
        let decoded = try JSONDecoder().decode(CoachChatProxyRequest.self, from: requester.lastBodyJSON!)
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.messages.first?.role, "user")
    }

    func testChatAdapter_mapsModelTierToMaxTokens() async throws {
        let requester = StubRequester()
        requester.responseProvider = { _ in
            CoachChatProxyResponse(
                content: [.text("ok")],
                stopReason: "end_turn",
                usage: .init(inputTokens: 0, outputTokens: 0),
                model: "sonnet"
            )
        }
        let adapter = CoachChatAIClientAdapter(requester: requester)
        let request = CoachChatRequest(
            systemPrompt: "sys",
            history: [CoachMessage(role: "user", text: "x")],
            model: .sonnet
        )
        _ = try await adapter.sendChat(request: request)
        let decoded = try JSONDecoder().decode(CoachChatProxyRequest.self, from: requester.lastBodyJSON!)
        XCTAssertEqual(decoded.maxTokens, 1024, "sonnet tier should pass 1024 max tokens")
    }

    func testChatAdapter_unknownStopReasonDefaultsToEndTurn() async throws {
        let requester = StubRequester()
        requester.responseProvider = { _ in
            CoachChatProxyResponse(
                content: [.text("ok")],
                stopReason: nil,
                usage: .init(inputTokens: 0, outputTokens: 0),
                model: "haiku"
            )
        }
        let adapter = CoachChatAIClientAdapter(requester: requester)
        let request = CoachChatRequest(
            systemPrompt: "sys",
            history: [CoachMessage(role: "user", text: "x")],
            model: .haiku
        )
        let response = try await adapter.sendChat(request: request)
        XCTAssertEqual(response.stopReason, .endTurn)
    }

    // MARK: - ConversationSummarizerAIClientAdapter

    func testSummarizerAdapter_postsToTextProxyWithCoachSummaryCaller() async throws {
        let requester = StubRequester()
        requester.responseProvider = { _ in
            NutritionProxyTextResponse(text: "Earlier: a brief summary.")
        }
        let adapter = ConversationSummarizerAIClientAdapter(requester: requester)
        let summary = try await adapter.summarize(
            request: ConversationSummarizationRequest(messages: [
                CoachMessage(role: "user", text: "first"),
                CoachMessage(role: "assistant", text: "hi"),
            ])
        )
        XCTAssertEqual(summary, "Earlier: a brief summary.")
        XCTAssertEqual(requester.lastEndpointPath, "/v1/nutrition/ai/proxy/text")
        let body = try JSONDecoder().decode(NutritionProxyTextRequest.self, from: requester.lastBodyJSON!)
        XCTAssertEqual(body.caller, "coach_summary")
        XCTAssertEqual(body.model, "haiku")
        XCTAssertEqual(body.temperature, 0.0)
    }

    // MARK: - CoachToolDispatcherAdapter

    private func seedPlannedMeal(in context: ModelContext) throws -> PlannedMeal {
        let plan = WeeklyMealPlan(
            startDate: Calendar.current.startOfDay(for: Date()),
            endDate: Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 * 6),
            isActive: true
        )
        context.insert(plan)
        let meal = PlannedMeal(
            dayDate: Calendar.current.startOfDay(for: Date()),
            mealNumber: 3,
            mealName: "Dinner",
            scheduledTime: "19:30",
            totalCalories: 600,
            totalProtein: 35,
            totalCarbs: 60,
            totalFat: 18
        )
        meal.mealPlan = plan
        context.insert(meal)
        try context.save()
        return meal
    }

    func testDispatcher_moveMealHappyPath() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = try seedPlannedMeal(in: context)

        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(),
            turnIndex: 0
        )
        let inputJSON = Data("""
        {"mealID":"\(meal.id.uuidString)","newTimeHHmm":"20:30"}
        """.utf8)
        let result = try await dispatcher.dispatch(
            toolName: "moveMeal",
            inputJSON: inputJSON,
            context: context
        )
        XCTAssertTrue(result.output.summary.contains("20:30"))
        let reloaded = try CoachToolHelpers.plannedMeal(id: meal.id, in: context)
        XCTAssertEqual(reloaded.scheduledTime, "20:30")
        XCTAssertNotNil(result.undoEntry, "moveMeal must register an undo entry")

        // PendingOutcome row created.
        let pending = try context.fetch(FetchDescriptor<PendingOutcome>())
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.actionToolName, "moveMeal")
    }

    func testDispatcher_undoRestoresScheduledTime() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = try seedPlannedMeal(in: context)

        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(),
            turnIndex: 0
        )
        let result = try await dispatcher.dispatch(
            toolName: "moveMeal",
            inputJSON: Data("""
            {"mealID":"\(meal.id.uuidString)","newTimeHHmm":"21:00"}
            """.utf8),
            context: context
        )
        XCTAssertEqual(meal.scheduledTime, "21:00")
        try await result.undoEntry?.reverseAction()
        XCTAssertEqual(meal.scheduledTime, "19:30")
    }

    func testDispatcher_skipMealRegistersUndoAndPending() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = try seedPlannedMeal(in: context)

        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(),
            turnIndex: 0
        )
        let result = try await dispatcher.dispatch(
            toolName: "skipMeal",
            inputJSON: Data(#"{"mealID":"\#(meal.id.uuidString)"}"#.utf8),
            context: context
        )
        XCTAssertEqual(meal.status, .skipped)
        XCTAssertNotNil(result.undoEntry)
        let pending = try context.fetch(FetchDescriptor<PendingOutcome>())
        XCTAssertEqual(pending.first?.actionToolName, "skipMeal")
        // undo restores .planned
        try await result.undoEntry?.reverseAction()
        XCTAssertEqual(meal.status, .planned)
    }

    func testDispatcher_swapToQuickerMealNoPendingOutcome() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = try seedPlannedMeal(in: context)

        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(),
            turnIndex: 0
        )
        let result = try await dispatcher.dispatch(
            toolName: "swapToQuickerMeal",
            inputJSON: Data(#"{"mealID":"\#(meal.id.uuidString)","maxPrepMin":20}"#.utf8),
            context: context
        )
        XCTAssertNil(result.undoEntry, "non-mutating tool has no undo")
        let pending = try context.fetch(FetchDescriptor<PendingOutcome>())
        XCTAssertEqual(pending.count, 0, "non-grading tool emits no PendingOutcome")
    }

    func testDispatcher_askUserEmitsPendingQuestion() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = try seedPlannedMeal(in: context)

        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(),
            turnIndex: 0
        )
        let result = try await dispatcher.dispatch(
            toolName: "askUser",
            inputJSON: Data(#"{"question":"Still lifting Tuesdays?","choices":["Yes","No"]}"#.utf8),
            context: context
        )
        XCTAssertNotNil(result.output.pendingQuestion)
        XCTAssertEqual(result.output.pendingQuestion?.choices, ["Yes", "No"])
    }

    func testDispatcher_recordPreferencePersistsRow() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let convID = UUID()
        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: convID,
            turnIndex: 3
        )
        let inputJSON = Data("""
        {"text":"user never eats before 11am","subject":"meal_timing.breakfast.skipped","source":"explicit","polarity":"positive","scope":"always"}
        """.utf8)
        _ = try await dispatcher.dispatch(
            toolName: "recordPreference",
            inputJSON: inputJSON,
            context: context
        )
        let rows = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.subject, "meal_timing.breakfast.skipped")
        XCTAssertEqual(rows.first?.evidenceConvId, convID)
        XCTAssertEqual(rows.first?.evidenceTurnIndex, 3)
    }

    func testDispatcher_unknownToolThrows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(),
            turnIndex: 0
        )
        do {
            _ = try await dispatcher.dispatch(
                toolName: "doesNotExist",
                inputJSON: Data(),
                context: context
            )
            XCTFail("expected DispatchError.unknownTool")
        } catch DispatchError.unknownTool(let name) {
            XCTAssertEqual(name, "doesNotExist")
        }
    }

    func testDispatcher_malformedUUIDThrows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(),
            turnIndex: 0
        )
        do {
            _ = try await dispatcher.dispatch(
                toolName: "moveMeal",
                inputJSON: Data(#"{"mealID":"not-a-uuid","newTimeHHmm":"20:30"}"#.utf8),
                context: context
            )
            XCTFail("expected DispatchError.malformedUUID")
        } catch DispatchError.malformedUUID {
            // expected
        }
    }
}
