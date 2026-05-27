//
// CoachService.swift
// Tempo
//
// Coach v2.1 Phase 6b — the agent loop.
//
// Owns the multi-turn orchestration for a single user message:
//   1. Pick model tier (Haiku default; Sonnet on escalation triggers).
//   2. POST the request through CoachChatAIClient.
//   3. Parse stop_reason. On end_turn → append assistant + return.
//      On tool_use → dispatch each call to CoachTools, append tool_result,
//      loop. Hard caps: 8 turns / 20 tool calls cumulative.
//   4. Summarize at message 12 (replace messages[0..6] with a single
//      Haiku-generated digest pseudo-message).
//   5. Track undo state in-memory (NOT persisted) — UI can pop the last
//      successful tool call.
//
// Network is behind a Sendable protocol so tests inject a deterministic
// scripted stub. Tool dispatch is the same code path Phase 3 shipped.
//
// Per .plans/coach-v2.1/04-ai-architecture.md "Model decision tree" +
// "Tool-use protocol" + "Conversation summarization" + "Undo stack".
//

import Foundation
import SwiftData

// MARK: - CoachService

@MainActor
final class CoachService {
    // MARK: - Configuration

    /// Hard cap on assistant turns per conversation (per v2.1 plan §04).
    static let maxTurnsPerConversation = 8

    /// Hard cap on cumulative tool calls per conversation.
    static let maxToolCallsPerConversation = 20

    /// Messages threshold that triggers conversation summarization.
    /// At this many messages, the earliest 6 are collapsed into a single
    /// system_summary pseudo-message.
    static let summarizationThreshold = 12
    static let summarizationCollapseCount = 6

    /// Escalation keywords that force Sonnet for the turn.
    /// Lowercase whole-word match.
    static let escalationKeywords: Set<String> = [
        "plan", "week", "days", "whole", "everything",
        "why", "because", "explain", "reorganize",
    ]

    // MARK: - Dependencies

    private let aiClient: CoachChatAIClient
    private let summarizerClient: ConversationSummarizerAIClient
    private let toolDispatcher: CoachToolDispatcher

    /// Per-session undo stack. Each entry is the human-readable action
    /// summary; reverseAction is fired by UI on user tap.
    private(set) var undoStack: [UndoEntry] = []

    init(
        aiClient: CoachChatAIClient,
        summarizerClient: ConversationSummarizerAIClient,
        toolDispatcher: CoachToolDispatcher
    ) {
        self.aiClient = aiClient
        self.summarizerClient = summarizerClient
        self.toolDispatcher = toolDispatcher
    }

    // MARK: - Public — send a user message

    /// Sends one user message and runs the tool-use loop until end_turn
    /// or a hard cap. Returns the run report so the UI can surface caps
    /// reached / errors / undo availability. Throws on network or
    /// persistence failure that the loop can't self-recover from.
    @discardableResult
    func sendMessage(
        _ userText: String,
        conversation: CoachConversation,
        systemPrompt: String,
        context: ModelContext
    ) async throws -> RunReport {
        var report = RunReport()
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            report.skippedEmptyInput = true
            return report
        }

        // Append the user turn first so it's part of the prompt history.
        let userMessage = CoachMessage(role: "user", text: trimmed)
        conversation.append(userMessage)

        var turnCount = 0
        var toolCallCount = 0
        var pendingFollowUp = false

        repeat {
            pendingFollowUp = false

            // Hard cap — turn count.
            if turnCount >= Self.maxTurnsPerConversation {
                let cap = CoachMessage(
                    role: "assistant",
                    text: "I've reached my turn limit. Want to start a fresh chat?",
                    model: nil
                )
                conversation.append(cap)
                report.capReached = .turns
                break
            }

            // Pick model for this turn.
            let model = Self.pickModel(
                turnIndex: turnCount,
                toolCallsSoFar: toolCallCount,
                userMessage: trimmed,
                contradictionFlagPresent: false // wired in Phase 6c via review queue
            )

            // Build the request.
            let request = CoachChatRequest(
                systemPrompt: systemPrompt,
                history: conversation.messages,
                model: model
            )

            // Network turn.
            let response = try await aiClient.sendChat(request: request)

            // Build assistant message from response content.
            let assistantText = response.content
                .compactMap { block -> String? in
                    if case let .text(text) = block { return text }
                    return nil
                }
                .joined(separator: "\n\n")
            let toolCalls = response.content.compactMap { block -> PendingToolCall? in
                if case let .toolUse(id, name, input) = block {
                    return PendingToolCall(id: id, name: name, inputJSON: input)
                }
                return nil
            }
            let assistantMessage = CoachMessage(
                role: "assistant",
                text: assistantText.isEmpty ? nil : assistantText,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                citedPreferenceIDs: response.citedPreferenceIDs,
                model: model.rawValue
            )
            conversation.append(assistantMessage)
            turnCount += 1
            report.turnsUsed = turnCount

            // If end_turn, we're done.
            if response.stopReason == .endTurn {
                break
            }

            // Tool-use loop. Each tool call → dispatch → append tool_result.
            guard response.stopReason == .toolUse, !toolCalls.isEmpty else {
                // Unexpected stop reason (max_tokens, etc) — surface and bail.
                report.unexpectedStopReason = response.stopReason
                break
            }

            // Hard cap — tool-call count.
            if toolCallCount + toolCalls.count > Self.maxToolCallsPerConversation {
                let cap = CoachMessage(
                    role: "assistant",
                    text: "I've hit the tool-call cap for this chat. End the chat to start fresh.",
                    model: nil
                )
                conversation.append(cap)
                report.capReached = .toolCalls
                break
            }

            var resultBlocks: [ToolResult] = []
            for call in toolCalls {
                toolCallCount += 1
                report.toolCallsUsed = toolCallCount
                do {
                    let dispatch = try await toolDispatcher.dispatch(
                        toolName: call.name,
                        inputJSON: call.inputJSON,
                        context: context
                    )
                    resultBlocks.append(ToolResult(
                        toolUseID: call.id,
                        outputText: dispatch.output.summary,
                        isError: false
                    ))
                    if let entry = dispatch.undoEntry {
                        undoStack.append(entry)
                    }
                    report.toolsSucceeded += 1
                } catch {
                    resultBlocks.append(ToolResult(
                        toolUseID: call.id,
                        outputText: error.localizedDescription,
                        isError: true
                    ))
                    report.toolsFailed += 1
                }
            }

            // Append tool_result block(s) as a user-role message
            // (Anthropic protocol). Then loop for the agent's recovery turn.
            let resultMessage = CoachMessage(
                role: "user",
                toolResults: resultBlocks
            )
            conversation.append(resultMessage)
            pendingFollowUp = true

            // Summarize lazily if we crossed the threshold.
            await summarizeIfNeeded(conversation: conversation)
        } while pendingFollowUp

        // Final summarize check (in case we ended on a non-tool turn but
        // are still over the threshold).
        await summarizeIfNeeded(conversation: conversation)

        try context.save()
        return report
    }

    /// Pops the most recent undo entry and invokes its reverse action.
    /// No-op when the stack is empty.
    @discardableResult
    func undoLast() async -> UndoEntry? {
        guard let entry = undoStack.popLast() else { return nil }
        try? await entry.reverseAction()
        return entry
    }

    /// Clears the undo stack — called by the UI on conversation end.
    func clearUndoStack() {
        undoStack.removeAll()
    }

    // MARK: - Summarization

    /// Replaces messages[0..summarizationCollapseCount] with a single
    /// system_summary pseudo-message. Idempotent — the threshold check
    /// prevents repeated collapses.
    private func summarizeIfNeeded(conversation: CoachConversation) async {
        let messages = conversation.messages
        guard messages.count >= Self.summarizationThreshold else { return }
        // Already-collapsed conversations start with a system_summary turn —
        // skip if the first message is already that role.
        if messages.first?.role == "system_summary" { return }

        // Build the slice we're summarizing.
        let slice = Array(messages.prefix(Self.summarizationCollapseCount))
        let request = ConversationSummarizationRequest(messages: slice)
        do {
            let summaryText = try await summarizerClient.summarize(request: request)
            let summary = CoachMessage(
                role: "system_summary",
                text: summaryText,
                timestamp: slice.first?.timestamp ?? Date(),
                model: "haiku"
            )
            conversation.collapseEarlyMessages(
                upTo: Self.summarizationCollapseCount,
                with: summary
            )
        } catch {
            // Silent failure — keeping the long history is better than
            // crashing the agent loop. Phase 6c surfaces via PostHog.
        }
    }

    // MARK: - Model decision tree

    /// Pure function for the model picker. Tests assert each trigger
    /// independently.
    static func pickModel(
        turnIndex: Int,
        toolCallsSoFar: Int,
        userMessage: String,
        contradictionFlagPresent: Bool
    ) -> CoachModelTier {
        if turnIndex >= 3 { return .sonnet }
        if toolCallsSoFar >= 3 { return .sonnet }
        if contradictionFlagPresent { return .sonnet }
        if userMessageTriggersEscalation(userMessage) { return .sonnet }
        return .haiku
    }

    /// Lowercase whole-word match against `escalationKeywords`. Used by
    /// pickModel and exposed for tests.
    static func userMessageTriggersEscalation(_ message: String) -> Bool {
        let lower = message.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " "))
        let filtered = String(lower.unicodeScalars.filter { allowed.contains($0) })
        let words = Set(filtered.split(separator: " ").map(String.init))
        return !words.isDisjoint(with: escalationKeywords)
    }
}

// MARK: - Public types

extension CoachService {
    enum CapReached: Equatable {
        case turns
        case toolCalls
    }

    struct RunReport: Equatable {
        var turnsUsed: Int = 0
        var toolCallsUsed: Int = 0
        var toolsSucceeded: Int = 0
        var toolsFailed: Int = 0
        var skippedEmptyInput: Bool = false
        var capReached: CapReached? = nil
        var unexpectedStopReason: CoachChatStopReason? = nil
    }

    struct UndoEntry: Sendable {
        let description: String
        let reverseAction: @Sendable () async throws -> Void
    }
}

// MARK: - Model tier

enum CoachModelTier: String, Sendable, Equatable {
    case haiku
    case sonnet
    case opus
}

// MARK: - Request / response DTOs (iOS-side)

/// Iiis side of the /v1/coach/chat round-trip. The real APIClient adapter
/// in Phase 7 wiring maps this to the backend's CoachProxyChatRequest /
/// CoachProxyChatResponse shape from Phase 1.
struct CoachChatRequest: Equatable, Sendable {
    let systemPrompt: String
    let history: [CoachMessage]
    let model: CoachModelTier
}

struct CoachChatResponse: Equatable, Sendable {
    let content: [CoachChatContentBlock]
    let stopReason: CoachChatStopReason
    let citedPreferenceIDs: [UUID]?

    init(
        content: [CoachChatContentBlock],
        stopReason: CoachChatStopReason,
        citedPreferenceIDs: [UUID]? = nil
    ) {
        self.content = content
        self.stopReason = stopReason
        self.citedPreferenceIDs = citedPreferenceIDs
    }
}

enum CoachChatContentBlock: Equatable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: Data)
}

enum CoachChatStopReason: String, Equatable, Sendable {
    case endTurn = "end_turn"
    case toolUse = "tool_use"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
}

// MARK: - Injection seams

/// Backend round-trip. Real adapter lives in Phase 7 wiring.
protocol CoachChatAIClient: Sendable {
    func sendChat(request: CoachChatRequest) async throws -> CoachChatResponse
}

/// Conversation summarizer. Haiku side-call returning a 3-sentence digest.
/// Real adapter lives in Phase 7 wiring.
protocol ConversationSummarizerAIClient: Sendable {
    func summarize(request: ConversationSummarizationRequest) async throws -> String
}

struct ConversationSummarizationRequest: Equatable, Sendable {
    let messages: [CoachMessage]
}

/// Tool dispatcher. Wraps the Phase 3 CoachTools so the service stays
/// async + protocol-injectable for tests.
/// @MainActor because real implementations call into CoachTools which
/// take a SwiftData ModelContext — ModelContext is main-actor-isolated.
@MainActor
protocol CoachToolDispatcher {
    func dispatch(
        toolName: String,
        inputJSON: Data,
        context: ModelContext
    ) async throws -> CoachToolDispatchResult
}

struct CoachToolDispatchResult: Sendable {
    let output: ToolOutput
    let undoEntry: CoachService.UndoEntry?

    init(output: ToolOutput, undoEntry: CoachService.UndoEntry? = nil) {
        self.output = output
        self.undoEntry = undoEntry
    }
}
