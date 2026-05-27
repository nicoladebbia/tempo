//
// CoachServiceTests.swift
// Tempo
//
// Coach v2.1 Phase 6b — covers the agent loop end-to-end with scripted
// stub clients. Validates model decision tree, tool-use dispatch loop,
// hard caps, undo stack, summarization at the threshold, and tool-error
// recovery.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachServiceTests: XCTestCase {
    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CoachConversation.self,
            LearnedPreference.self,
            LearnedOutcome.self,
            PendingOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Stubs

    /// Scripted AI client. Responses are popped in order on each call.
    final class ScriptedAIClient: CoachChatAIClient, @unchecked Sendable {
        var scripted: [CoachChatResponse] = []
        var receivedRequests: [CoachChatRequest] = []
        func sendChat(request: CoachChatRequest) async throws -> CoachChatResponse {
            receivedRequests.append(request)
            guard !scripted.isEmpty else {
                throw NSError(domain: "test", code: 1)
            }
            return scripted.removeFirst()
        }
    }

    final class FixedSummarizer: ConversationSummarizerAIClient, @unchecked Sendable {
        var calls = 0
        var summary = "Earlier: discussed soccer dinner shift."
        func summarize(request: ConversationSummarizationRequest) async throws -> String {
            calls += 1
            return summary
        }
    }

    /// Tool dispatcher whose behavior is per-call-name. Failure mode:
    /// any name in `failingTools` throws CoachToolError.mealNotFound.
    final class ScriptedDispatcher: CoachToolDispatcher, @unchecked Sendable {
        var outputs: [String: ToolOutput] = [:]
        var failingTools: Set<String> = []
        var receivedCalls: [(name: String, input: Data)] = []
        func dispatch(
            toolName: String,
            inputJSON: Data,
            context _: ModelContext
        ) async throws -> CoachToolDispatchResult {
            receivedCalls.append((toolName, inputJSON))
            if failingTools.contains(toolName) {
                throw CoachToolError.mealNotFound(UUID())
            }
            let output = outputs[toolName] ?? ToolOutput(summary: "ok: \(toolName)")
            return CoachToolDispatchResult(
                output: output,
                undoEntry: CoachService.UndoEntry(
                    description: "undo \(toolName)",
                    reverseAction: { }
                )
            )
        }
    }

    // MARK: - pickModel

    func testPickModel_haikuOnFreshShortMessage() {
        let model = CoachService.pickModel(
            turnIndex: 0,
            toolCallsSoFar: 0,
            userMessage: "soccer at 7pm",
            contradictionFlagPresent: false
        )
        XCTAssertEqual(model, .haiku)
    }

    func testPickModel_sonnetOnThirdTurn() {
        let model = CoachService.pickModel(
            turnIndex: 3,
            toolCallsSoFar: 0,
            userMessage: "x",
            contradictionFlagPresent: false
        )
        XCTAssertEqual(model, .sonnet)
    }

    func testPickModel_sonnetWhenManyToolCalls() {
        let model = CoachService.pickModel(
            turnIndex: 0,
            toolCallsSoFar: 3,
            userMessage: "x",
            contradictionFlagPresent: false
        )
        XCTAssertEqual(model, .sonnet)
    }

    func testPickModel_sonnetOnContradictionFlag() {
        let model = CoachService.pickModel(
            turnIndex: 0,
            toolCallsSoFar: 0,
            userMessage: "x",
            contradictionFlagPresent: true
        )
        XCTAssertEqual(model, .sonnet)
    }

    func testPickModel_sonnetOnEscalationKeyword() {
        XCTAssertEqual(
            CoachService.pickModel(
                turnIndex: 0, toolCallsSoFar: 0,
                userMessage: "plan my week", contradictionFlagPresent: false
            ),
            .sonnet
        )
        XCTAssertEqual(
            CoachService.pickModel(
                turnIndex: 0, toolCallsSoFar: 0,
                userMessage: "why did I sleep badly?", contradictionFlagPresent: false
            ),
            .sonnet
        )
    }

    func testEscalation_wholeWordMatching() {
        XCTAssertTrue(CoachService.userMessageTriggersEscalation("plan my day"))
        XCTAssertTrue(CoachService.userMessageTriggersEscalation("Explain dinner"))
        XCTAssertFalse(CoachService.userMessageTriggersEscalation("planet was nice"),
                       "substring within a longer token must not match — bag-of-words is split by space")
    }

    // MARK: - sendMessage — happy path

    func testSendMessage_endTurnAppendsAssistantAndStops() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        ai.scripted = [
            CoachChatResponse(
                content: [.text("Got it. Dinner shifted.")],
                stopReason: .endTurn
            ),
        ]
        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: ScriptedDispatcher()
        )
        let report = try await service.sendMessage(
            "soccer at 7pm",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(report.turnsUsed, 1)
        XCTAssertEqual(report.toolCallsUsed, 0)
        XCTAssertNil(report.capReached)
        let messages = conversation.messages
        XCTAssertEqual(messages.count, 2, "user + assistant")
        XCTAssertEqual(messages[0].role, "user")
        XCTAssertEqual(messages[1].role, "assistant")
        XCTAssertEqual(messages[1].text, "Got it. Dinner shifted.")
    }

    func testSendMessage_emptyInputShortCircuits() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()
        let ai = ScriptedAIClient()
        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: ScriptedDispatcher()
        )
        let report = try await service.sendMessage(
            "   ",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertTrue(report.skippedEmptyInput)
        XCTAssertEqual(ai.receivedRequests.count, 0)
    }

    // MARK: - Tool-use loop

    func testSendMessage_toolUseLoopDispatchesAndAppendsToolResult() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        // Turn 1: tool_use for moveMeal. Turn 2: end_turn.
        ai.scripted = [
            CoachChatResponse(
                content: [
                    .text("Moving dinner now."),
                    .toolUse(id: "tc-1", name: "moveMeal", input: Data(#"{"x":1}"#.utf8)),
                ],
                stopReason: .toolUse
            ),
            CoachChatResponse(
                content: [.text("Done. Dinner is at 20:30.")],
                stopReason: .endTurn
            ),
        ]
        let dispatcher = ScriptedDispatcher()
        dispatcher.outputs["moveMeal"] = ToolOutput(summary: "Moved dinner 19:30 → 20:30")

        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: dispatcher
        )
        let report = try await service.sendMessage(
            "move dinner later",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(report.turnsUsed, 2)
        XCTAssertEqual(report.toolCallsUsed, 1)
        XCTAssertEqual(report.toolsSucceeded, 1)
        XCTAssertEqual(dispatcher.receivedCalls.first?.name, "moveMeal")
        // Conversation layout: user, assistant+tool_use, tool_result, assistant.
        let messages = conversation.messages
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[2].role, "user")
        XCTAssertEqual(messages[2].toolResults?.first?.outputText, "Moved dinner 19:30 → 20:30")
        XCTAssertFalse(messages[2].toolResults?.first?.isError ?? true)
        XCTAssertEqual(service.undoStack.count, 1)
    }

    func testSendMessage_toolErrorAppendsErrorResultAndAgentRecovers() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        ai.scripted = [
            CoachChatResponse(
                content: [.toolUse(id: "tc-1", name: "moveMeal", input: Data())],
                stopReason: .toolUse
            ),
            CoachChatResponse(
                content: [.text("That meal is already eaten — anything else?")],
                stopReason: .endTurn
            ),
        ]
        let dispatcher = ScriptedDispatcher()
        dispatcher.failingTools = ["moveMeal"]

        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: dispatcher
        )
        let report = try await service.sendMessage(
            "move dinner",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(report.toolsFailed, 1)
        let resultMsg = conversation.messages.first { $0.role == "user" && $0.toolResults != nil }
        XCTAssertTrue(resultMsg?.toolResults?.first?.isError ?? false)
        XCTAssertEqual(service.undoStack.count, 0, "failed tools must not push undo")
    }

    // MARK: - Hard caps

    func testSendMessage_turnCapStopsLoopWithFallbackMessage() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        // 8 tool-use turns in a row → after turn 8 the cap fires before the next loop.
        for i in 0..<8 {
            ai.scripted.append(CoachChatResponse(
                content: [.toolUse(id: "tc-\(i)", name: "moveMeal", input: Data())],
                stopReason: .toolUse
            ))
        }
        let dispatcher = ScriptedDispatcher()
        dispatcher.outputs["moveMeal"] = ToolOutput(summary: "x")

        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: dispatcher
        )
        let report = try await service.sendMessage(
            "x",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(report.capReached, .turns)
        XCTAssertEqual(report.turnsUsed, CoachService.maxTurnsPerConversation)
        // Last assistant message is the cap-reached fallback copy.
        XCTAssertTrue(conversation.messages.last?.text?.contains("turn limit") ?? false)
    }

    func testSendMessage_toolCallCapStopsLoop() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        // 5 tool calls per turn × 5 turns = 25 > 20 cap; cap fires on the
        // turn whose cumulative count would exceed the threshold.
        for i in 0..<5 {
            let calls = (0..<5).map { j in
                CoachChatContentBlock.toolUse(id: "t-\(i)-\(j)", name: "moveMeal", input: Data())
            }
            ai.scripted.append(CoachChatResponse(content: calls, stopReason: .toolUse))
        }
        let dispatcher = ScriptedDispatcher()
        dispatcher.outputs["moveMeal"] = ToolOutput(summary: "ok")

        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: dispatcher
        )
        let report = try await service.sendMessage(
            "x",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(report.capReached, .toolCalls)
        XCTAssertLessThanOrEqual(report.toolCallsUsed, CoachService.maxToolCallsPerConversation)
        XCTAssertTrue(conversation.messages.last?.text?.contains("tool-call cap") ?? false)
    }

    // MARK: - Undo

    func testUndo_popsAndRunsReverseAction() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        ai.scripted = [
            CoachChatResponse(
                content: [.toolUse(id: "tc-1", name: "moveMeal", input: Data())],
                stopReason: .toolUse
            ),
            CoachChatResponse(content: [.text("ok")], stopReason: .endTurn),
        ]
        let dispatcher = ScriptedDispatcher()
        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: dispatcher
        )
        _ = try await service.sendMessage(
            "x",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(service.undoStack.count, 1)
        let popped = await service.undoLast()
        XCTAssertEqual(popped?.description, "undo moveMeal")
        XCTAssertEqual(service.undoStack.count, 0)
        // Pop again on empty → nil.
        let empty = await service.undoLast()
        XCTAssertNil(empty)
    }

    func testClearUndoStack_drainsEverything() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        ai.scripted = [
            CoachChatResponse(
                content: [
                    .toolUse(id: "tc-1", name: "moveMeal", input: Data()),
                    .toolUse(id: "tc-2", name: "swapDayType", input: Data()),
                ],
                stopReason: .toolUse
            ),
            CoachChatResponse(content: [.text("done")], stopReason: .endTurn),
        ]
        let service = CoachService(
            aiClient: ai,
            summarizerClient: FixedSummarizer(),
            toolDispatcher: ScriptedDispatcher()
        )
        _ = try await service.sendMessage(
            "x",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(service.undoStack.count, 2)
        service.clearUndoStack()
        XCTAssertEqual(service.undoStack.count, 0)
    }

    // MARK: - Summarization

    func testSummarization_firesAtThreshold() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Seed conversation with 11 messages already — one more user turn
        // (no tool dispatch) will push to 13 and trigger the summarizer.
        let conversation = CoachConversation()
        for i in 0..<11 {
            conversation.append(CoachMessage(role: "user", text: "old \(i)"))
        }
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        ai.scripted = [
            CoachChatResponse(content: [.text("ack")], stopReason: .endTurn),
        ]
        let summarizer = FixedSummarizer()
        summarizer.summary = "Earlier: a lot of stuff."
        let service = CoachService(
            aiClient: ai,
            summarizerClient: summarizer,
            toolDispatcher: ScriptedDispatcher()
        )
        _ = try await service.sendMessage(
            "new turn",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(summarizer.calls, 1)
        XCTAssertEqual(conversation.messages.first?.role, "system_summary")
        XCTAssertEqual(conversation.messages.first?.text, "Earlier: a lot of stuff.")
        // 11 + 1 user + 1 assistant = 13 messages. Collapse takes 6 → 1 summary.
        // Final count: 1 summary + 7 preserved messages = 8.
        XCTAssertEqual(conversation.messages.count, 8)
    }

    func testSummarization_doesNotRefireOnAlreadyCollapsed() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = CoachConversation()
        // Pre-existing collapsed state: starts with a system_summary.
        conversation.append(CoachMessage(role: "system_summary", text: "old"))
        for i in 0..<11 {
            conversation.append(CoachMessage(role: "user", text: "later \(i)"))
        }
        context.insert(conversation)
        try context.save()

        let ai = ScriptedAIClient()
        ai.scripted = [
            CoachChatResponse(content: [.text("ack")], stopReason: .endTurn),
        ]
        let summarizer = FixedSummarizer()
        let service = CoachService(
            aiClient: ai,
            summarizerClient: summarizer,
            toolDispatcher: ScriptedDispatcher()
        )
        _ = try await service.sendMessage(
            "again",
            conversation: conversation,
            systemPrompt: "sys",
            context: context
        )
        XCTAssertEqual(summarizer.calls, 0, "already-collapsed conversations skip summarization")
    }
}
