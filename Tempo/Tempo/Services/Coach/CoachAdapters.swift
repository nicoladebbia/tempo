//
// CoachAdapters.swift
// Tempo
//
// Coach v2.1 Phase 7a — concrete adapters wiring the Phase 6b protocols
// (CoachChatAIClient, ConversationSummarizerAIClient, CoachToolDispatcher)
// against real iOS plumbing: APIClient for network, CoachTools for
// tool dispatch, NutritionProxyTextRequest for the cheap Haiku summary
// side-call.
//
// All three adapters are tested independently — the network adapters
// use a fake `APIRequester` protocol so unit tests don't hit the wire;
// the dispatcher adapter is testable end-to-end against a SwiftData
// in-memory container plus the real CoachTools.
//
// Per .plans/coach-v2.1/03-services-and-data-flow.md "What calls what"
// and §04-ai-architecture.md (tool-use protocol + summarization).
//

import Foundation
import SwiftData

// MARK: - APIRequester

/// Minimal seam over APIClient so adapters are testable without standing
/// up a live network stack. The real implementation forwards to
/// `APIClient.request(_:body:)`; tests inject a deterministic stub.
protocol APIRequester: Sendable {
    func request<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        _ endpoint: APIEndpoint<Response>,
        body: Body
    ) async throws -> Response
}

extension APIClient: APIRequester {
    func request<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        _ endpoint: APIEndpoint<Response>,
        body: Body
    ) async throws -> Response {
        try await request(endpoint, body: body, queryItems: nil)
    }
}

// MARK: - CoachChatAIClientAdapter

/// Maps the iOS-side CoachChatRequest (Phase 6b shape) into the backend
/// CoachChatProxyRequest wire shape, posts via APIRequester, and maps
/// the response back. Tool definitions come from `CoachToolCatalog`
/// (a small lookup of name → description + JSON Schema).
struct CoachChatAIClientAdapter: CoachChatAIClient {
    let requester: APIRequester
    let toolCatalog: [CoachChatProxyTool]
    let maxTokensHaiku: Int
    let maxTokensSonnet: Int
    let maxTokensOpus: Int

    init(
        requester: APIRequester,
        toolCatalog: [CoachChatProxyTool] = CoachToolCatalog.defaultCatalog,
        maxTokensHaiku: Int = 800,
        maxTokensSonnet: Int = 1024,
        maxTokensOpus: Int = 1024
    ) {
        self.requester = requester
        self.toolCatalog = toolCatalog
        self.maxTokensHaiku = maxTokensHaiku
        self.maxTokensSonnet = maxTokensSonnet
        self.maxTokensOpus = maxTokensOpus
    }

    func sendChat(request: CoachChatRequest) async throws -> CoachChatResponse {
        let wireMessages = request.history.compactMap { msg -> CoachChatProxyMessage? in
            // Map CoachMessage → proxy message with polymorphic content blocks.
            // Skip system_summary turns — they're injected via systemPrompt only,
            // not in messages[].
            switch msg.role {
            case "system_summary":
                return nil
            case "assistant":
                var blocks: [CoachChatProxyContentBlock] = []
                if let text = msg.text, !text.isEmpty {
                    blocks.append(.text(text))
                }
                if let calls = msg.toolCalls {
                    for call in calls {
                        blocks.append(.toolUse(
                            id: call.id,
                            name: call.name,
                            inputJSON: call.inputJSON
                        ))
                    }
                }
                guard !blocks.isEmpty else { return nil }
                return CoachChatProxyMessage(role: "assistant", content: blocks)
            case "user":
                var blocks: [CoachChatProxyContentBlock] = []
                if let text = msg.text, !text.isEmpty {
                    blocks.append(.text(text))
                }
                if let results = msg.toolResults {
                    for result in results {
                        blocks.append(.toolResult(
                            toolUseID: result.toolUseID,
                            content: result.outputText,
                            isError: result.isError
                        ))
                    }
                }
                guard !blocks.isEmpty else { return nil }
                return CoachChatProxyMessage(role: "user", content: blocks)
            default:
                return nil
            }
        }

        let maxTokens: Int
        switch request.model {
        case .haiku: maxTokens = maxTokensHaiku
        case .sonnet: maxTokens = maxTokensSonnet
        case .opus: maxTokens = maxTokensOpus
        }

        let body = CoachChatProxyRequest(
            model: request.model.rawValue,
            maxTokens: maxTokens,
            system: request.systemPrompt,
            messages: wireMessages,
            tools: toolCatalog,
            toolChoice: nil
        )
        let response = try await requester.request(APIEndpoint<CoachChatProxyResponse>.coachChat(), body: body)

        // Map back.
        let content: [CoachChatContentBlock] = response.content.compactMap { block in
            switch block {
            case let .text(text):
                return .text(text)
            case let .toolUse(id, name, inputJSON):
                return .toolUse(id: id, name: name, input: inputJSON)
            case .toolResult:
                // toolResult blocks are user-message content; not expected
                // in a server response, but drop defensively if present.
                return nil
            }
        }
        let stopReason: CoachChatStopReason
        switch response.stopReason {
        case "end_turn": stopReason = .endTurn
        case "tool_use": stopReason = .toolUse
        case "max_tokens": stopReason = .maxTokens
        case "stop_sequence": stopReason = .stopSequence
        default: stopReason = .endTurn
        }
        return CoachChatResponse(content: content, stopReason: stopReason)
    }
}

// MARK: - ConversationSummarizerAIClientAdapter

/// Calls the existing /v1/nutrition/ai/proxy/text route (Haiku) to get
/// a 3-sentence digest of the early conversation. Tagged with
/// caller="coach_summary" so backend logs separate it from coach-chat
/// spend.
struct ConversationSummarizerAIClientAdapter: ConversationSummarizerAIClient {
    let requester: APIRequester
    let maxTokens: Int

    init(requester: APIRequester, maxTokens: Int = 200) {
        self.requester = requester
        self.maxTokens = maxTokens
    }

    func summarize(request: ConversationSummarizationRequest) async throws -> String {
        let rendered = request.messages
            .map { msg -> String in
                let role = msg.role.uppercased()
                let text = msg.text ?? "(tool action)"
                return "\(role): \(text)"
            }
            .joined(separator: "\n")
        let userMessage = """
        Summarize this user-coach conversation in 3 sentences for context
        retention. Preserve any decisions made, actions taken, and
        preferences mentioned. Output prose only, no preamble.

        \(rendered)
        """
        let body = NutritionProxyTextRequest(
            model: "haiku",
            system: "You are a conversation summarizer. Output exactly 3 sentences.",
            userMessage: userMessage,
            maxTokens: maxTokens,
            temperature: 0.0,
            caller: "coach_summary"
        )
        let response = try await requester.request(
            APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
            body: body
        )
        return response.text
    }
}

// MARK: - CoachToolDispatcherAdapter

/// Wraps the Phase 3 CoachTools statics so the agent loop (Phase 6b)
/// can call them by name + opaque JSON args. Deserializes per-tool
/// argument bytes, dispatches, captures an undo entry that restores
/// pre-state for the mutating tools.
@MainActor
struct CoachToolDispatcherAdapter: CoachToolDispatcher {
    let notifications: CoachMealNotificationScheduler
    /// Conversation reference used to write PendingOutcome rows so the
    /// grader can link outcomes back to their decision.
    let conversationID: UUID
    let turnIndex: Int

    init(
        conversationID: UUID,
        turnIndex: Int,
        notifications: CoachMealNotificationScheduler = NoopCoachMealNotificationScheduler()
    ) {
        self.conversationID = conversationID
        self.turnIndex = turnIndex
        self.notifications = notifications
    }

    func dispatch(
        toolName: String,
        inputJSON: Data,
        context: ModelContext
    ) async throws -> CoachToolDispatchResult {
        let decoder = JSONDecoder()
        let output: ToolOutput
        var undoEntry: CoachService.UndoEntry?

        switch toolName {
        case "moveMeal":
            let args = try decoder.decode(MoveMealArgs.self, from: inputJSON)
            let mealID = try Self.parseUUID(args.mealID)
            // Capture pre-state for undo.
            let pre = try CoachToolHelpers.plannedMeal(id: mealID, in: context)
            let oldScheduled = pre.scheduledTime
            let oldStatus = pre.status

            output = try CoachTools.moveMeal(
                mealID: mealID,
                newTimeHHmm: args.newTimeHHmm,
                notifications: notifications,
                context: context
            )
            // Undo restores scheduled time + status. Notifications
            // re-restored by the same scheduler hook.
            let scheduler = notifications
            undoEntry = CoachService.UndoEntry(
                description: "Undo move \(pre.mealName)",
                reverseAction: { @MainActor in
                    let row = try? CoachToolHelpers.plannedMeal(id: mealID, in: context)
                    row?.scheduledTime = oldScheduled
                    row?.status = oldStatus
                    try? context.save()
                    scheduler.cancelMealNotification(mealID: mealID)
                }
            )
            queuePendingOutcomeIfNeeded(
                toolName: toolName,
                inputJSON: inputJSON,
                context: context
            )

        case "swapDayType":
            let args = try decoder.decode(SwapDayTypeArgs.self, from: inputJSON)
            let dayType = try Self.parseDayType(args.newType)
            let date = try Self.parseDate(args.date)
            output = try CoachTools.swapDayType(
                date: date,
                newType: dayType,
                scaleMacros: args.scaleMacros,
                caloriesMultiplier: args.caloriesMultiplier ?? 1.0,
                context: context
            )
            // Per-day macro scale isn't trivially reversible without a
            // pre-state snapshot of every meal; deferring undo for v2.1
            // (the chat UI presents a hint that swapDayType isn't undoable
            // and recommends manual revert).
            queuePendingOutcomeIfNeeded(
                toolName: toolName,
                inputJSON: inputJSON,
                context: context
            )

        case "skipMeal":
            let args = try decoder.decode(SkipMealArgs.self, from: inputJSON)
            let mealID = try Self.parseUUID(args.mealID)
            let pre = try CoachToolHelpers.plannedMeal(id: mealID, in: context)
            let oldStatus = pre.status
            output = try CoachTools.skipMeal(
                mealID: mealID,
                notifications: notifications,
                context: context
            )
            undoEntry = CoachService.UndoEntry(
                description: "Undo skip \(pre.mealName)",
                reverseAction: { @MainActor in
                    let row = try? CoachToolHelpers.plannedMeal(id: mealID, in: context)
                    row?.status = oldStatus
                    try? context.save()
                }
            )
            queuePendingOutcomeIfNeeded(
                toolName: toolName,
                inputJSON: inputJSON,
                context: context
            )

        case "swapToQuickerMeal":
            let args = try decoder.decode(SwapToQuickerMealArgs.self, from: inputJSON)
            let mealID = try Self.parseUUID(args.mealID)
            output = try CoachTools.swapToQuickerMeal(
                mealID: mealID,
                maxPrepMin: args.maxPrepMin,
                context: context
            )
            // No persistence side-effect → no undo needed, no pending outcome.

        case "shiftBedtime":
            let args = try decoder.decode(ShiftBedtimeArgs.self, from: inputJSON)
            let date = try Self.parseDate(args.date)
            output = try CoachTools.shiftBedtime(
                date: date,
                newBedtimeHHmm: args.newBedtimeHHmm
            )
            queuePendingOutcomeIfNeeded(
                toolName: toolName,
                inputJSON: inputJSON,
                context: context
            )

        case "askUser":
            let args = try decoder.decode(AskUserArgs.self, from: inputJSON)
            output = CoachTools.askUser(
                question: args.question,
                choices: args.choices ?? []
            )

        case "recordPreference":
            let args = try decoder.decode(RecordPreferenceArgs.self, from: inputJSON)
            output = try CoachTools.recordPreference(
                text: args.text,
                subject: args.subject,
                source: args.source,
                polarity: args.polarity,
                scope: args.scope,
                confidence: args.confidence,
                conversationID: conversationID,
                turnIndex: turnIndex,
                context: context
            )

        case "updatePreference":
            let args = try decoder.decode(UpdatePreferenceArgs.self, from: inputJSON)
            let prefID = try Self.parseUUID(args.prefID)
            let supersededID = args.supersededByID.flatMap { try? Self.parseUUID($0) }
            output = try CoachTools.updatePreference(
                prefID: prefID,
                action: args.action,
                newText: args.newText,
                newScope: args.newScope,
                supersededByID: supersededID,
                context: context
            )

        default:
            throw DispatchError.unknownTool(toolName)
        }

        return CoachToolDispatchResult(output: output, undoEntry: undoEntry)
    }

    // MARK: - Helpers

    private func queuePendingOutcomeIfNeeded(
        toolName: String,
        inputJSON: Data,
        context: ModelContext
    ) {
        guard let window = PendingOutcome.window(for: toolName) else { return }
        let row = PendingOutcome(
            decisionConvID: conversationID,
            decisionTurnIndex: turnIndex,
            actionToolName: toolName,
            actionPayload: inputJSON,
            evaluationWindow: window
        )
        context.insert(row)
        // Save deferred — CoachService.sendMessage saves on completion.
    }

    static func parseUUID(_ raw: String) throws -> UUID {
        guard let uuid = UUID(uuidString: raw) else {
            throw DispatchError.malformedUUID(raw)
        }
        return uuid
    }

    static func parseDate(_ raw: String) throws -> Date {
        // Bare YYYY-MM-DD strings ("2026-05-27") are interpreted in the
        // user's local calendar, not UTC. The previous ISO8601 path put
        // them at UTC midnight which, after Calendar.current.startOfDay,
        // rolled back to the prior day in positive offsets — the
        // grader's day-range queries then missed the matching rows.
        if raw.count == 10, raw.contains("-") {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        let isoFull = ISO8601DateFormatter()
        if let date = isoFull.date(from: raw) { return date }
        throw DispatchError.malformedDate(raw)
    }

    static func parseDayType(_ raw: String) throws -> DayType {
        guard let type = DayType(rawValue: raw) else {
            throw DispatchError.malformedDayType(raw)
        }
        return type
    }
}

// MARK: - Per-tool arg DTOs

struct MoveMealArgs: Decodable, Sendable {
    let mealID: String
    let newTimeHHmm: String
}

struct SwapDayTypeArgs: Decodable, Sendable {
    let date: String
    let newType: String
    let scaleMacros: Bool
    let caloriesMultiplier: Double?
}

struct SkipMealArgs: Decodable, Sendable {
    let mealID: String
}

struct SwapToQuickerMealArgs: Decodable, Sendable {
    let mealID: String
    let maxPrepMin: Int
}

struct ShiftBedtimeArgs: Decodable, Sendable {
    let date: String
    let newBedtimeHHmm: String
}

struct AskUserArgs: Decodable, Sendable {
    let question: String
    let choices: [String]?
}

struct RecordPreferenceArgs: Decodable, Sendable {
    let text: String
    let subject: String
    let source: LearnedPreference.Source
    let polarity: LearnedPreference.Polarity
    let scope: LearnedPreference.Scope
    let confidence: Double?
}

struct UpdatePreferenceArgs: Decodable, Sendable {
    let prefID: String
    let action: CoachTools.UpdateAction
    let newText: String?
    let newScope: LearnedPreference.Scope?
    let supersededByID: String?
}

// MARK: - Errors

enum DispatchError: Error, Equatable {
    case unknownTool(String)
    case malformedUUID(String)
    case malformedDate(String)
    case malformedDayType(String)
}

// MARK: - CoachToolCatalog

/// Static tool definitions advertised to Claude per turn. The schemas
/// match the per-tool arg DTOs above so the model knows exactly what
/// JSON to emit.
enum CoachToolCatalog {
    /// Default catalog used by CoachChatAIClientAdapter. Phase 8 may
    /// extend with the suggestExpiryAwareMeal pantry tool.
    static let defaultCatalog: [CoachChatProxyTool] = [
        .init(
            name: "moveMeal",
            description: "Shift a planned meal to a new time. Reschedules notifications.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "mealID": .object(["type": .string("string"), "description": .string("PlannedMeal UUID")]),
                    "newTimeHHmm": .object(["type": .string("string"), "pattern": .string("^[0-2][0-9]:[0-5][0-9]$")]),
                ]),
                "required": .array([.string("mealID"), .string("newTimeHHmm")]),
            ])
        ),
        .init(
            name: "swapDayType",
            description: "Change a calendar day's training type. scaleMacros true scales every planned meal by caloriesMultiplier.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD")]),
                    "newType": .object(["type": .string("string"), "enum": .array([.string("strength"), .string("cardio"), .string("soccer"), .string("double"), .string("rest")])]),
                    "scaleMacros": .object(["type": .string("boolean")]),
                    "caloriesMultiplier": .object(["type": .string("number")]),
                ]),
                "required": .array([.string("date"), .string("newType"), .string("scaleMacros")]),
            ])
        ),
        .init(
            name: "skipMeal",
            description: "Mark a planned meal as skipped and cancel its notification.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "mealID": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("mealID")]),
            ])
        ),
        .init(
            name: "swapToQuickerMeal",
            description: "Suggest up to 3 quicker recipes whose totalMinutes ≤ maxPrepMin and macros are close to the original meal. Does NOT auto-replace.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "mealID": .object(["type": .string("string")]),
                    "maxPrepMin": .object(["type": .string("integer"), "minimum": .int(1)]),
                ]),
                "required": .array([.string("mealID"), .string("maxPrepMin")]),
            ])
        ),
        .init(
            name: "shiftBedtime",
            description: "Acknowledge a bedtime shift for a date. v1: no DB persistence yet — just confirms the intent.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD")]),
                    "newBedtimeHHmm": .object(["type": .string("string"), "pattern": .string("^[0-2][0-9]:[0-5][0-9]$")]),
                ]),
                "required": .array([.string("date"), .string("newBedtimeHHmm")]),
            ])
        ),
        .init(
            name: "askUser",
            description: "Ask the user a question. Choices are optional; when present, the UI renders them as tappable chips.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "question": .object(["type": .string("string")]),
                    "choices": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                ]),
                "required": .array([.string("question")]),
            ])
        ),
        .init(
            name: "recordPreference",
            description: "Insert a new LearnedPreference row. Use when the user reveals a recurring pattern.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                    "subject": .object(["type": .string("string"), "description": .string("dot.path.taxonomy")]),
                    "source": .object(["type": .string("string"), "enum": .array([.string("explicit"), .string("observed"), .string("inferred"), .string("userVerified")])]),
                    "polarity": .object(["type": .string("string"), "enum": .array([.string("positive"), .string("negative"), .string("avoidAtAllCosts")])]),
                    "scope": .object(["type": .string("string"), "enum": .array([.string("always"), .string("weekday"), .string("weekend"), .string("dayTypeHard"), .string("dayTypeRest"), .string("eventTravel"), .string("eventMatch"), .string("seasonalSummer")])]),
                    "confidence": .object(["type": .string("number")]),
                ]),
                "required": .array([.string("text"), .string("subject"), .string("source"), .string("polarity"), .string("scope")]),
            ])
        ),
        .init(
            name: "updatePreference",
            description: "Mutate an existing LearnedPreference. Action: supersede / keepClarifyScope / deactivate / markOneOff.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "prefID": .object(["type": .string("string")]),
                    "action": .object(["type": .string("string"), "enum": .array([.string("supersede"), .string("keepClarifyScope"), .string("deactivate"), .string("markOneOff")])]),
                    "newText": .object(["type": .string("string")]),
                    "newScope": .object(["type": .string("string")]),
                    "supersededByID": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("prefID"), .string("action")]),
            ])
        ),
    ]
}
