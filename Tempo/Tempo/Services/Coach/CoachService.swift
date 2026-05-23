//
// CoachService.swift
// Tempo
//
// Multi-turn agent loop for the Coach. On each user message:
//
//   1. Assemble the per-turn context (CoachContextAssembler).
//   2. POST to /v1/nutrition/ai/coach/chat with the running transcript +
//      the tool schemas. Default model is Haiku 4.5; escalate to Sonnet
//      4.6 when the message is open-ended ("why am I always tired?")
//      or when Haiku has needed >2 tool turns to converge.
//   3. If response.stop_reason == "tool_use", dispatch each tool_use
//      block against `CoachToolDispatcher`, append tool_result blocks,
//      loop. Otherwise, persist the final assistant text + finish.
//   4. After session.end(), kick off PreferenceExtractor to mine the
//      transcript for new LearnedPreferences (fire-and-forget).
//
// Undo stack: every tool that mutates SwiftData records an Undo closure
// on `CoachService.undoStack`. The chat UI surfaces a single-step undo
// for the user. We deliberately keep undo to one level — a Coach
// conversation rarely needs >1 reversal, and a multi-level stack adds
// complexity without proportional value.
//
// Per `.plans/coach-agent-plan.md` Phase 6 + docs/COACH_AGENT.md.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class CoachService {

    // MARK: - Public surface

    /// Agent loop hard cap. If the model hasn't returned end_turn within
    /// this many tool roundtrips, we bail with a helpful message. Real
    /// conversations converge in 1-3 tool turns.
    static let maxToolTurns = 6

    /// Maximum tokens the model may emit per turn. 1500 is enough for a
    /// paragraph reply + a tool call; larger answers usually mean the
    /// model is rambling.
    static let maxTokensPerTurn = 1_500

    enum Model: String {
        case haiku
        case sonnet
    }

    private let apiClient: APIClient
    private let modelContext: ModelContext
    private let notifications: (any NotificationServiceProtocol)?
    private let logger = Logger(subsystem: "com.tempo.app", category: "CoachService")

    /// One-shot undo stack. Cleared on every new conversation start.
    var undoStack: [Undo] = []

    init(
        apiClient: APIClient,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) {
        self.apiClient = apiClient
        self.modelContext = modelContext
        self.notifications = notifications
    }

    // MARK: - Send

    /// Run one user turn through the agent. Mutates `conversation` in
    /// place (appends user turn → assistant turns → final assistant text).
    /// Returns the final assistant text shown to the user.
    func send(
        userMessage: String,
        conversation: CoachConversation,
        modelHint: Model? = nil
    ) async throws -> SendResult {
        // 1. Append the user turn to the transcript.
        conversation.appendTurn(
            ChatTurn(role: "user", blocks: [.text(userMessage)])
        )

        // 2. Decide model. Escalate to Sonnet for open-ended questions
        //    or when we've already burned >2 tool turns on this conversation
        //    (the model is clearly struggling with Haiku).
        let model = modelHint ?? selectModel(userMessage: userMessage, conversation: conversation)

        // 3. Build system prompt (assembler snapshot + agent instructions).
        let assembler = CoachContextAssembler(context: modelContext)
        let snapshot = assembler.snapshot(userMessage: userMessage)
        let system = Self.systemPrompt(snapshot: snapshot.text)

        // 4. Agent loop.
        var toolTurns = 0
        var finalText: String? = nil
        var citedPreferenceIDs: [UUID] = []
        var pendingQuestion: PendingQuestion? = nil

        while toolTurns < Self.maxToolTurns {
            let request = buildChatRequest(
                model: model,
                system: system,
                conversation: conversation
            )
            let response = try await postChat(request)
            recordUsage(response, into: conversation)

            // Materialize the assistant turn (text + any tool_use blocks).
            let assistantBlocks = response.blocks.compactMap { block -> ChatTurnBlock? in
                switch block.type {
                case "text":
                    return block.text.map { .text($0) }
                case "tool_use":
                    guard let id = block.id, let name = block.name else { return nil }
                    let inputJSON = serializeJSON(block.input)
                    return .toolUse(name: name, id: id, inputJSON: inputJSON)
                default:
                    return nil
                }
            }
            conversation.appendTurn(ChatTurn(role: "assistant", blocks: assistantBlocks))

            // Concatenate any text blocks for the user-facing reply.
            let textParts = assistantBlocks.compactMap { block -> String? in
                if case let .text(s) = block { return s }
                return nil
            }
            if !textParts.isEmpty {
                finalText = textParts.joined(separator: "\n\n")
            }

            // Done?
            if response.stopReason != "tool_use" {
                break
            }

            // Dispatch each tool_use, collect tool_results.
            var resultBlocks: [ChatTurnBlock] = []
            for block in response.blocks where block.type == "tool_use" {
                guard let id = block.id, let name = block.name else { continue }
                do {
                    let output = try CoachToolDispatcher.dispatch(
                        name: name,
                        input: block.input ?? .object([:]),
                        conversation: conversation,
                        modelContext: modelContext,
                        notifications: notifications,
                        undoStack: &undoStack
                    )
                    citedPreferenceIDs.append(contentsOf: output.citedPreferenceIDs)
                    if let q = output.pendingQuestion { pendingQuestion = q }
                    resultBlocks.append(.toolResult(
                        toolUseID: id,
                        isError: false,
                        text: formatToolResult(output)
                    ))
                } catch {
                    logger.error("Coach tool '\(name)' failed: \(error.localizedDescription)")
                    resultBlocks.append(.toolResult(
                        toolUseID: id,
                        isError: true,
                        text: error.localizedDescription
                    ))
                }
            }
            // The next user turn contains the tool_results.
            conversation.appendTurn(ChatTurn(role: "user", blocks: resultBlocks))
            toolTurns += 1

            // If the agent triggered askUser, stop the loop — UI handles
            // the question; no point looping back to the model.
            if pendingQuestion != nil { break }
        }

        if toolTurns >= Self.maxToolTurns, finalText == nil {
            finalText = "I'm having trouble converging on this — let's narrow it down. What's the most important part?"
        }

        try? modelContext.save()

        return SendResult(
            text: finalText ?? "(no response)",
            citedPreferenceIDs: citedPreferenceIDs,
            pendingQuestion: pendingQuestion,
            modelUsed: model,
            toolTurnsTaken: toolTurns
        )
    }

    // MARK: - End conversation

    /// Mark a conversation finished and fire the preference extractor.
    /// Safe to call multiple times — only the first call schedules
    /// extraction.
    func end(
        conversation: CoachConversation,
        extractor: PreferenceExtractor
    ) async {
        guard conversation.endedAt == nil else { return }
        conversation.endedAt = Date()

        if conversation.titleSummary == nil {
            conversation.titleSummary = Self.deriveTitle(from: conversation.turns())
        }

        try? modelContext.save()

        let transcript = conversation.transcriptText()
        do {
            _ = try await extractor.extract(
                transcript: transcript,
                conversationID: conversation.id,
                context: modelContext
            )
        } catch {
            logger.error("PreferenceExtractor on session end failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Undo

    /// Apply the most recent undo entry and pop it. Returns the human
    /// label for confirmation toast.
    @discardableResult
    func undoLast() -> String? {
        guard let entry = undoStack.popLast() else { return nil }
        entry.apply(modelContext)
        try? modelContext.save()
        return entry.label
    }

    var undoLabel: String? { undoStack.last?.label }

    // MARK: - Private — model selection + request build

    private func selectModel(userMessage: String, conversation: CoachConversation) -> Model {
        // Heuristic escalation. Open-ended "why" / "what should I" /
        // "how do I balance" questions or verbose messages prompt Sonnet.
        let lowered = userMessage.lowercased()
        let openEnded = ["why ", "what should", "how do i", "how should i", "explain ", "compare "]
        if openEnded.contains(where: { lowered.contains($0) }) { return .sonnet }
        if userMessage.count > 240 { return .sonnet }

        // Escalate if Haiku has already burned >2 tool turns in this convo.
        let priorToolUses = conversation.turns().flatMap(\.blocks).filter {
            if case .toolUse = $0 { return true }
            return false
        }.count
        if priorToolUses > 2 { return .sonnet }

        return .haiku
    }

    private func buildChatRequest(
        model: Model,
        system: String,
        conversation: CoachConversation
    ) -> NutritionProxyChatRequest {
        let wireMessages = conversation.turns().map { turn in
            NutritionProxyChatRequest.ChatMessage(
                role: turn.role,
                content: turn.blocks.map(toWireBlock)
            )
        }
        return NutritionProxyChatRequest(
            model: model.rawValue,
            system: system,
            messages: wireMessages,
            tools: CoachToolSchema.allTools,
            toolChoice: .auto,
            maxTokens: Self.maxTokensPerTurn,
            temperature: 0.4,
            caller: "coach"
        )
    }

    private func toWireBlock(_ b: ChatTurnBlock) -> NutritionProxyChatRequest.ChatBlock {
        switch b {
        case let .text(s):
            return .init(
                type: "text", text: s,
                id: nil, name: nil, input: nil,
                toolUseId: nil, isError: nil, resultText: nil
            )
        case let .toolUse(name, id, inputJSON):
            let input: NutritionProxyChatRequest.JSONValue?
            if let data = inputJSON.data(using: .utf8) {
                input = try? JSONDecoder().decode(NutritionProxyChatRequest.JSONValue.self, from: data)
            } else {
                input = .object([:])
            }
            return .init(
                type: "tool_use", text: nil,
                id: id, name: name, input: input,
                toolUseId: nil, isError: nil, resultText: nil
            )
        case let .toolResult(toolUseID, isError, text):
            return .init(
                type: "tool_result", text: nil,
                id: nil, name: nil, input: nil,
                toolUseId: toolUseID, isError: isError, resultText: text
            )
        }
    }

    private func postChat(
        _ request: NutritionProxyChatRequest
    ) async throws -> NutritionProxyChatResponse {
        let endpoint = APIEndpoint<NutritionProxyChatResponse>.coachChat()
        return try await apiClient.request(endpoint, body: request)
    }

    private func recordUsage(_ response: NutritionProxyChatResponse, into c: CoachConversation) {
        c.totalTokensIn += response.usage.inputTokens
        c.totalTokensOut += response.usage.outputTokens
    }

    private func serializeJSON(_ v: NutritionProxyChatRequest.JSONValue?) -> String {
        guard let v else { return "{}" }
        let data = (try? JSONEncoder().encode(v)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func formatToolResult(_ output: ToolOutput) -> String {
        var lines = [output.summary]
        if !output.sideEffects.isEmpty {
            lines.append("• " + output.sideEffects.joined(separator: "\n• "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - System prompt

    static func systemPrompt(snapshot: String) -> String {
        """
        You are the Tempo Coach — Nicola's life-operating-system assistant.
        Voice: drill-sergeant honest, never sycophantic. No fluff, no
        validation openers, no time estimates.

        Use tools to actually change Nicola's schedule / preferences /
        meal plan. Don't just describe what you'd do — call the tool.
        Cite the LearnedPreference IDs you relied on in your reply text
        as `[abc12345]` short codes.

        If the user request is genuinely ambiguous, call `askUser` with a
        single sharp question + 2-3 choices. Don't ask a string of clarifying
        questions; pick the most load-bearing one.

        When you mutate state, write the action's reason briefly so the user
        knows why. After all tool calls finish, summarize what you changed
        in one short paragraph.

        Memory snapshot (identity + preferences + recent state):
        \(snapshot)
        """
    }

    static func deriveTitle(from turns: [ChatTurn]) -> String {
        // Take the first user text block, trim to 60 chars.
        for turn in turns where turn.role == "user" {
            for block in turn.blocks {
                if case let .text(s) = block {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return String(trimmed.prefix(60))
                    }
                }
            }
        }
        return "Coach session"
    }

    // MARK: - SendResult

    struct SendResult: Sendable {
        let text: String
        let citedPreferenceIDs: [UUID]
        let pendingQuestion: PendingQuestion?
        let modelUsed: Model
        let toolTurnsTaken: Int
    }

    struct Undo: Sendable {
        let label: String
        let apply: @Sendable @MainActor (ModelContext) -> Void
    }
}

// MARK: - Tool dispatcher

/// Dispatches tool_use blocks emitted by Claude to the matching
/// `CoachTools` method. Each handler decodes the JSON input, calls the
/// tool, and returns the `ToolOutput` for the agent's tool_result block.
@MainActor
enum CoachToolDispatcher {

    static func dispatch(
        name: String,
        input: NutritionProxyChatRequest.JSONValue,
        conversation: CoachConversation,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)?,
        undoStack: inout [CoachService.Undo]
    ) throws -> ToolOutput {
        let dict = inputAsDict(input)
        switch name {
        case "record_preference":
            return try handleRecordPreference(
                dict: dict, conversation: conversation, modelContext: modelContext, undoStack: &undoStack
            )
        case "update_preference":
            return try handleUpdatePreference(dict: dict, modelContext: modelContext)
        case "ask_user":
            return handleAskUser(dict: dict)
        case "shift_bedtime":
            return try handleShiftBedtime(dict: dict)
        case "move_meal":
            return try handleMoveMeal(
                dict: dict, modelContext: modelContext, notifications: notifications,
                undoStack: &undoStack
            )
        case "skip_meal":
            return try handleSkipMeal(
                dict: dict, modelContext: modelContext, notifications: notifications
            )
        default:
            throw CoachToolError.noSuitableAlternative(reason: "Unknown tool '\(name)'.")
        }
    }

    // MARK: - Handlers

    static func handleRecordPreference(
        dict: [String: NutritionProxyChatRequest.JSONValue],
        conversation: CoachConversation,
        modelContext: ModelContext,
        undoStack: inout [CoachService.Undo]
    ) throws -> ToolOutput {
        let text = stringValue(dict["text"]) ?? ""
        let subject = stringValue(dict["subject"]) ?? ""
        let confidence = numberValue(dict["confidence"]) ?? 0.8
        let output = try CoachTools.recordPreference(
            text: text,
            subject: subject,
            confidence: confidence,
            conversationID: conversation.id,
            turnIndex: conversation.turns().count,
            modelContext: modelContext
        )
        if let prefID = output.citedPreferenceIDs.first {
            undoStack.append(.init(label: "Forget '\(text)'") { ctx in
                let desc = FetchDescriptor<LearnedPreference>(
                    predicate: #Predicate { $0.id == prefID }
                )
                if let pref = try? ctx.fetch(desc).first {
                    ctx.delete(pref)
                }
            })
        }
        return output
    }

    static func handleUpdatePreference(
        dict: [String: NutritionProxyChatRequest.JSONValue],
        modelContext: ModelContext
    ) throws -> ToolOutput {
        guard let prefIDStr = stringValue(dict["pref_id"]),
              let prefID = UUID(uuidString: prefIDStr)
        else {
            throw CoachToolError.preferenceNotFound(UUID())
        }
        let actionStr = stringValue(dict["action"]) ?? "deactivate"
        let action: LearnedPreference.Action
        switch actionStr {
        case "supersede": action = .supersede
        case "keep_clarify_scope", "keepClarifyScope": action = .keepClarifyScope
        case "mark_one_off", "markOneOff": action = .markOneOff
        default: action = .deactivate
        }
        let newText = stringValue(dict["new_text"])
        let supersededByID = stringValue(dict["superseded_by_id"]).flatMap(UUID.init(uuidString:))
        return try CoachTools.updatePreference(
            prefID: prefID,
            action: action,
            newText: newText,
            supersededByID: supersededByID,
            modelContext: modelContext
        )
    }

    static func handleAskUser(dict: [String: NutritionProxyChatRequest.JSONValue]) -> ToolOutput {
        let q = stringValue(dict["question"]) ?? ""
        let choices = arrayValue(dict["choices"])?.compactMap(stringValue(_:))
        return CoachTools.askUser(question: q, choices: choices)
    }

    static func handleShiftBedtime(dict: [String: NutritionProxyChatRequest.JSONValue]) throws -> ToolOutput {
        let dateStr = stringValue(dict["date"])
        let date = dateStr.flatMap(parseISODate) ?? Date()
        let newBedtime = stringValue(dict["new_bedtime"]) ?? "23:00"
        return try CoachTools.shiftBedtime(date: date, newBedtimeHHmm: newBedtime)
    }

    static func handleMoveMeal(
        dict: [String: NutritionProxyChatRequest.JSONValue],
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)?,
        undoStack: inout [CoachService.Undo]
    ) throws -> ToolOutput {
        guard let mealIDStr = stringValue(dict["meal_id"]),
              let mealID = UUID(uuidString: mealIDStr)
        else {
            throw CoachToolError.mealNotFound(UUID())
        }
        let newTime = stringValue(dict["new_time"]) ?? "12:00"

        // Snapshot prior time for undo.
        let priorTime: String? = {
            let desc = FetchDescriptor<PlannedMeal>(predicate: #Predicate { $0.id == mealID })
            return (try? modelContext.fetch(desc).first)?.scheduledTime
        }()

        let output = try CoachTools.moveMeal(
            mealID: mealID,
            newTimeHHmm: newTime,
            notifications: notifications,
            modelContext: modelContext
        )

        if let priorTime {
            undoStack.append(.init(label: "Revert meal to \(priorTime)") { ctx in
                let desc = FetchDescriptor<PlannedMeal>(predicate: #Predicate { $0.id == mealID })
                if let meal = try? ctx.fetch(desc).first {
                    meal.scheduledTime = priorTime
                }
            })
        }
        return output
    }

    static func handleSkipMeal(
        dict: [String: NutritionProxyChatRequest.JSONValue],
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)?
    ) throws -> ToolOutput {
        guard let mealIDStr = stringValue(dict["meal_id"]),
              let mealID = UUID(uuidString: mealIDStr)
        else {
            throw CoachToolError.mealNotFound(UUID())
        }
        return try CoachTools.skipMeal(
            mealID: mealID,
            notifications: notifications,
            modelContext: modelContext
        )
    }

    // MARK: - JSON helpers

    static func inputAsDict(_ v: NutritionProxyChatRequest.JSONValue) -> [String: NutritionProxyChatRequest.JSONValue] {
        if case let .object(o) = v { return o }
        return [:]
    }

    static func stringValue(_ v: NutritionProxyChatRequest.JSONValue?) -> String? {
        if case let .string(s) = v { return s }
        return nil
    }

    static func numberValue(_ v: NutritionProxyChatRequest.JSONValue?) -> Double? {
        if case let .number(n) = v { return n }
        return nil
    }

    static func arrayValue(
        _ v: NutritionProxyChatRequest.JSONValue?
    ) -> [NutritionProxyChatRequest.JSONValue]? {
        if case let .array(a) = v { return a }
        return nil
    }

    static func parseISODate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        return f.date(from: s) ?? DateFormatter.coachDateFormatter.date(from: s)
    }
}

private extension DateFormatter {
    static let coachDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Tool schemas (sent to Claude)

/// Tool-use schemas in Anthropic JSON-Schema shape. Order doesn't matter
/// to Claude but we keep it stable for snapshot tests.
enum CoachToolSchema {

    static let allTools: [NutritionProxyChatRequest.ChatTool] = [
        recordPreference,
        updatePreference,
        askUser,
        shiftBedtime,
        moveMeal,
        skipMeal,
    ]

    static let recordPreference = NutritionProxyChatRequest.ChatTool(
        name: "record_preference",
        description: "Persist a new user preference (taste, schedule, constraint). Use when the user states a durable preference like 'I don't eat eggs' or 'bedtime 23:00'.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Short third-person sentence: 'Hates eggs', 'Bedtime 23:00'."),
                ]),
                "subject": .object([
                    "type": .string("string"),
                    "description": .string("Canonical subject dot-string e.g. 'meal_timing.dinner'."),
                ]),
                "confidence": .object([
                    "type": .string("number"),
                    "description": .string("0.0-1.0; .9 for explicit user-stated."),
                ]),
            ]),
            "required": .array([.string("text"), .string("subject"), .string("confidence")]),
        ])
    )

    static let updatePreference = NutritionProxyChatRequest.ChatTool(
        name: "update_preference",
        description: "Modify an existing preference: supersede, deactivate, mark as one-off, or confirm/clarify scope.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "pref_id": .object(["type": .string("string"), "description": .string("UUID of the existing preference.")]),
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("supersede"),
                        .string("keep_clarify_scope"),
                        .string("deactivate"),
                        .string("mark_one_off"),
                    ]),
                ]),
                "new_text": .object(["type": .string("string"), "description": .string("Required if action=keep_clarify_scope and the text changes.")]),
                "superseded_by_id": .object(["type": .string("string"), "description": .string("UUID of replacement pref when action=supersede.")]),
            ]),
            "required": .array([.string("pref_id"), .string("action")]),
        ])
    )

    static let askUser = NutritionProxyChatRequest.ChatTool(
        name: "ask_user",
        description: "Ask the user a single clarifying question. Use when the request is genuinely ambiguous and you can't proceed without input.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "question": .object(["type": .string("string")]),
                "choices": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Optional pre-canned choices (1-4)."),
                ]),
            ]),
            "required": .array([.string("question")]),
        ])
    )

    static let shiftBedtime = NutritionProxyChatRequest.ChatTool(
        name: "shift_bedtime",
        description: "Override bedtime for a specific date (conversation-scoped; v1 doesn't persist).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "date": .object(["type": .string("string"), "description": .string("ISO-8601 or yyyy-MM-dd.")]),
                "new_bedtime": .object(["type": .string("string"), "description": .string("HH:mm 24h.")]),
            ]),
            "required": .array([.string("date"), .string("new_bedtime")]),
        ])
    )

    static let moveMeal = NutritionProxyChatRequest.ChatTool(
        name: "move_meal",
        description: "Reschedule a planned meal to a new time. Downstream meals shift to maintain spacing.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "meal_id": .object(["type": .string("string")]),
                "new_time": .object(["type": .string("string"), "description": .string("HH:mm 24h.")]),
            ]),
            "required": .array([.string("meal_id"), .string("new_time")]),
        ])
    )

    static let skipMeal = NutritionProxyChatRequest.ChatTool(
        name: "skip_meal",
        description: "Mark a planned meal as skipped (user won't eat it).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "meal_id": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("meal_id")]),
        ])
    )
}

// MARK: - APIEndpoint extension

extension APIEndpoint where Response == NutritionProxyChatResponse {
    static func coachChat() -> Self {
        // Coach turns mostly use Haiku (3-8s) but Sonnet escalations can
        // hit 60s. Long timeout matches `nutritionProxyText`.
        APIEndpoint(path: "/v1/nutrition/ai/coach/chat", method: .post, timeoutInterval: 180)
    }
}
