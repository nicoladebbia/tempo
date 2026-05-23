import Foundation
import Vapor

// MARK: - NutritionClaudeProxyService
//
// Generic Claude proxy for nutrition AI features that currently call Anthropic
// directly from iOS via ClaudeAPIClient. This is the iOS-side migration target:
// the iOS service renders its own prompts (because they reference iOS-only
// SwiftData types like DietaryProfile, PlannedFood, MealPlanIntake) and sends
// the rendered prompt + model selection here. The proxy holds the API key,
// makes the upstream call, and returns Claude's raw text completion.
//
// Per AI_INTELLIGENCE_ENGINE.md Section 2 + ADR-018: Claude must be called
// from the Vapor backend only. This service is the chokepoint that finally
// honours that ADR for the nutrition module.
//
// Per INTELLIGENCE_REMEDIATION_PLAN.md §3.1: replaces ClaudeAPIClient.swift
// for MealPlanGeneratorService, MealRedistributionService, NaturalLanguage-
// LoggingService, NutritionCoachService, and PhotoAnalysisService.

actor NutritionClaudeProxyService {
    static let shared = NutritionClaudeProxyService()

    private init() {}

    // MARK: - Public

    /// Send a pre-rendered prompt to Claude and return the raw text completion.
    /// Caller is responsible for prompt rendering, JSON parsing, and validation.
    func sendText(
        input: NutritionProxyTextRequest,
        on req: Request
    ) async throws -> NutritionProxyTextResponse {
        let model = try resolveModel(input.model)
        let timeout = timeout(for: model)
        let text = try await callClaude(
            model: model,
            system: input.system,
            userMessage: input.userMessage,
            maxTokens: input.maxTokens,
            temperature: input.temperature,
            timeout: timeout,
            caller: input.caller,
            on: req
        )
        return NutritionProxyTextResponse(text: text)
    }

    /// Send a pre-rendered prompt with a base64-encoded image to Claude.
    /// Used by PhotoAnalysisService (Haiku Vision). Caller supplies media type
    /// (image/jpeg, image/png, image/webp).
    func sendVision(
        input: NutritionProxyVisionRequest,
        on req: Request
    ) async throws -> NutritionProxyTextResponse {
        let model = try resolveModel(input.model)
        let timeout = timeout(for: model)
        let text = try await callClaudeWithImage(
            model: model,
            system: input.system,
            userMessage: input.userMessage,
            imageMediaType: input.imageMediaType,
            imageBase64: input.imageBase64,
            maxTokens: input.maxTokens,
            temperature: input.temperature,
            timeout: timeout,
            caller: input.caller,
            on: req
        )
        return NutritionProxyTextResponse(text: text)
    }


    /// Multi-turn chat with tool use. Used by the iOS Coach agent loop —
    /// the server forwards the supplied tool schemas to Claude and returns
    /// the raw response (text + tool_use blocks + stop_reason) for the
    /// client to dispatch and loop.
    func sendChat(
        input: NutritionProxyChatRequest,
        on req: Request
    ) async throws -> NutritionProxyChatResponse {
        let model = try resolveModel(input.model)
        let timeout = timeout(for: model)

        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw NutritionProxyError.missingAPIKey
        }

        let messages: [ProxyMessage] = input.messages.map { msg in
            let blocks: [ProxyContentBlock] = msg.content.compactMap { b in
                switch b.type {
                case "text":
                    return b.text.map { .text($0) }
                case "tool_use":
                    guard let id = b.id, let name = b.name, let input = b.input else { return nil }
                    return .toolUse(id: id, name: name, input: input)
                case "tool_result":
                    guard let toolUseId = b.toolUseId else { return nil }
                    return .toolResult(toolUseId: toolUseId, isError: b.isError, resultText: b.resultText)
                default:
                    return nil
                }
            }
            return ProxyMessage(role: msg.role, content: .blocks(blocks))
        }

        let body = ProxyClaudeRequest(
            model: model,
            maxTokens: input.maxTokens,
            temperature: input.temperature,
            system: input.system,
            messages: messages,
            tools: input.tools,
            toolChoice: input.toolChoice
        )

        let raw = try await executeRaw(
            body: body,
            apiKey: apiKey,
            timeout: timeout,
            caller: input.caller,
            on: req
        )

        let blocks: [NutritionProxyChatResponse.Block] = raw.content.map { b in
            .init(type: b.type, text: b.text, id: b.id, name: b.name, input: b.input)
        }
        return NutritionProxyChatResponse(
            stopReason: raw.stopReason ?? "end_turn",
            blocks: blocks,
            usage: .init(inputTokens: raw.usage.inputTokens, outputTokens: raw.usage.outputTokens)
        )
    }

    // MARK: - Model resolution

    private func resolveModel(_ raw: String) throws -> String {
        switch raw.lowercased() {
        case "haiku": AIConfig.haikuModel
        case "sonnet": AIConfig.sonnetModel
        case "opus":
            // Opus is reserved for pattern detection per AI spec §1.
            // Nutrition features must not burn Opus tokens.
            throw NutritionProxyError.modelNotAllowed("Opus is not available for nutrition AI routes.")
        default:
            throw NutritionProxyError.unknownModel(raw)
        }
    }

    private func timeout(for model: String) -> TimeInterval {
        switch model {
        case AIConfig.haikuModel: AIConfig.haikuTimeout
        case AIConfig.sonnetModel: AIConfig.sonnetTimeout
        case AIConfig.opusModel: AIConfig.opusTimeout
        default: AIConfig.haikuTimeout
        }
    }

    // MARK: - Claude calls

    private func callClaude(
        model: String,
        system: String,
        userMessage: String,
        maxTokens: Int,
        temperature: Double,
        timeout: TimeInterval,
        caller: String,
        on req: Request
    ) async throws -> String {
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw NutritionProxyError.missingAPIKey
        }

        let body = ProxyClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            system: system,
            messages: [.init(role: "user", content: .text(userMessage))]
        )

        return try await execute(
            body: body,
            apiKey: apiKey,
            timeout: timeout,
            caller: caller,
            on: req
        )
    }

    private func callClaudeWithImage(
        model: String,
        system: String,
        userMessage: String,
        imageMediaType: String,
        imageBase64: String,
        maxTokens: Int,
        temperature: Double,
        timeout: TimeInterval,
        caller: String,
        on req: Request
    ) async throws -> String {
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw NutritionProxyError.missingAPIKey
        }

        let blocks: [ProxyContentBlock] = [
            .image(source: .init(type: "base64", mediaType: imageMediaType, data: imageBase64)),
            .text(userMessage),
        ]

        let body = ProxyClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            system: system,
            messages: [.init(role: "user", content: .blocks(blocks))]
        )

        return try await execute(
            body: body,
            apiKey: apiKey,
            timeout: timeout,
            caller: caller,
            on: req
        )
    }

    private func execute(
        body: ProxyClaudeRequest,
        apiKey: String,
        timeout: TimeInterval,
        caller: String,
        on req: Request
    ) async throws -> String {
        let raw = try await executeRaw(
            body: body,
            apiKey: apiKey,
            timeout: timeout,
            caller: caller,
            on: req
        )
        guard let textBlock = raw.content.first(where: { $0.type == "text" }),
              let text = textBlock.text else {
            throw NutritionProxyError.malformedResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lower-level call used by the multi-turn chat endpoint. Returns the
    /// raw Anthropic response (text + tool_use blocks + stop_reason + usage)
    /// so the caller can drive a tool-use agent loop.
    private func executeRaw(
        body: ProxyClaudeRequest,
        apiKey: String,
        timeout: TimeInterval,
        caller: String,
        on req: Request
    ) async throws -> ProxyClaudeRawResponse {
        // Pre-flight budget gate. Per AI_INTELLIGENCE_ENGINE.md §5.4 +
        // INTELLIGENCE_REMEDIATION_PLAN.md §5. Input-token estimate uses
        // a rough heuristic (system + user character count / 4).
        let messageChars = body.messages.reduce(0) { $0 + $1.estimatedCharCount }
        let inputEstimate = max(500, (body.system.count + messageChars) / 4)
        let costEstimate = AIBudgetTracker.shared.estimateCostCents(
            model: body.model,
            estimatedInputTokens: inputEstimate,
            maxOutputTokens: body.maxTokens
        )
        // Per-feature sub-budget gate (currently only "coach"). Falls back to
        // the global monthly cap when no sub-budget is registered.
        guard await AIBudgetTracker.shared.canMakeCall(
            estimatedCostCents: costEstimate,
            caller: caller,
            on: req
        ) else {
            req.logger.warning("[nutrition_proxy \(caller)] budget exhausted")
            throw NutritionProxyError.budgetExhausted
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(body)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: "x-api-key", value: apiKey)
        headers.add(name: "anthropic-version", value: "2023-06-01")

        // Vapor's client does not expose a per-request timeout knob the way
        // URLSession does; rely on the upstream HTTP/2 stream timeout for now
        // and surface 408 via the response status. Tracked for follow-up.
        _ = timeout

        let response = try await req.client.post(
            URI(string: "https://api.anthropic.com/v1/messages"),
            headers: headers
        ) { clientReq in
            clientReq.body = .init(data: bodyData)
        }

        guard response.status == .ok else {
            req.logger.error("[nutrition_proxy \(caller)] Claude HTTP \(response.status.code)")
            throw NutritionProxyError.apiError(Int(response.status.code))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try response.content.decode(ProxyClaudeRawResponse.self, using: decoder)

        // Persistent post-call accounting against the monthly budget (global
        // + per-caller sub-budget).
        await AIBudgetTracker.shared.recordSpend(
            model: body.model,
            inputTokens: raw.usage.inputTokens,
            outputTokens: raw.usage.outputTokens,
            caller: caller,
            on: req
        )

        req.logger.info(
            "[nutrition_proxy \(caller)] ok model=\(body.model) in=\(raw.usage.inputTokens) out=\(raw.usage.outputTokens) stop=\(raw.stopReason ?? "?")"
        )
        return raw
    }
}

// MARK: - Public DTOs (callable from controller)

struct NutritionProxyTextRequest: Content {
    /// One of: "haiku", "sonnet". Opus is rejected.
    let model: String
    let system: String
    let userMessage: String
    let maxTokens: Int
    let temperature: Double
    /// Short tag for logging — e.g. "meal_plan", "redistribute", "nl_log", "coach", "recipe".
    let caller: String
}

struct NutritionProxyVisionRequest: Content {
    let model: String
    let system: String
    let userMessage: String
    /// e.g. "image/jpeg", "image/png", "image/webp"
    let imageMediaType: String
    /// Base64-encoded image bytes (no data: prefix).
    let imageBase64: String
    let maxTokens: Int
    let temperature: Double
    let caller: String
}

struct NutritionProxyTextResponse: Content {
    let text: String
}

// MARK: - Coach chat (tool-use, multi-turn)

/// Request body for the multi-turn coach chat endpoint. Mirrors a subset of
/// Anthropic's `/v1/messages` shape so the iOS agent loop can drive tool use
/// without the backend having to understand domain tools. Tool dispatch
/// happens on-device — the server only forwards `tools` to Claude and parses
/// `tool_use` blocks out of the response.
///
/// `messages` must already include any prior `tool_result` blocks the iOS
/// agent ran. The system prompt + memory snapshot is passed in `system`.
struct NutritionProxyChatRequest: Content {
    /// One of: "haiku", "sonnet". Opus rejected per AIConfig allow-list.
    let model: String
    let system: String
    let messages: [ChatMessage]
    /// Tool schemas the server forwards to Claude verbatim. JSON-Schema
    /// per Anthropic's tool-use spec.
    let tools: [ChatTool]?
    /// Optional `tool_choice`: `auto` (default), `any`, or `{type:"tool",name:"X"}`.
    let toolChoice: ChatToolChoice?
    let maxTokens: Int
    let temperature: Double
    /// Short tag for logging + sub-budget bookkeeping. Coach uses "coach".
    let caller: String

    struct ChatMessage: Content {
        /// "user" or "assistant".
        let role: String
        /// Blocks: text, tool_use (echo back from assistant turn), tool_result.
        let content: [ChatBlock]
    }

    struct ChatBlock: Content {
        /// "text" | "tool_use" | "tool_result"
        let type: String
        // text
        let text: String?
        // tool_use (assistant echo)
        let id: String?
        let name: String?
        let input: JSONValue?
        // tool_result (user echo)
        let toolUseId: String?
        let isError: Bool?
        /// Tool result body, encoded as either a plain string or a JSON value.
        /// Anthropic accepts both; we forward as-is. Decoded from
        /// `content` on the wire — that's what iOS sends, matching the
        /// Anthropic tool_result block shape.
        let resultText: String?

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
            case toolUseId = "tool_use_id"
            case isError = "is_error"
            case resultText = "content"
        }
    }

    struct ChatTool: Content {
        let name: String
        let description: String
        /// JSON Schema for the tool's input. Forwarded verbatim to Claude.
        let inputSchema: JSONValue
    }

    enum ChatToolChoice: Content {
        case auto
        case any
        case tool(name: String)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                switch s {
                case "auto": self = .auto
                case "any": self = .any
                default: throw DecodingError.dataCorruptedError(
                    in: c, debugDescription: "Unknown tool_choice string: \(s)"
                )
                }
                return
            }
            struct Obj: Decodable { let type: String; let name: String? }
            let obj = try c.decode(Obj.self)
            switch obj.type {
            case "auto": self = .auto
            case "any": self = .any
            case "tool":
                guard let n = obj.name else {
                    throw DecodingError.dataCorruptedError(
                        in: c, debugDescription: "tool choice missing name"
                    )
                }
                self = .tool(name: n)
            default:
                throw DecodingError.dataCorruptedError(
                    in: c, debugDescription: "Unknown tool_choice type: \(obj.type)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .auto: try c.encode(["type": "auto"])
            case .any: try c.encode(["type": "any"])
            case let .tool(name): try c.encode(["type": "tool", "name": name])
            }
        }
    }
}

struct NutritionProxyChatResponse: Content {
    /// Anthropic stop_reason: "end_turn", "tool_use", "max_tokens", "stop_sequence".
    let stopReason: String
    /// Decoded content blocks from Claude's response. Text blocks have `text`;
    /// tool_use blocks have `id`/`name`/`input`.
    let blocks: [Block]
    let usage: Usage

    struct Block: Content {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: JSONValue?
    }

    struct Usage: Content {
        let inputTokens: Int
        let outputTokens: Int
    }
}

/// Permissive JSON box used by the chat DTOs — Claude's tool input/output
/// schemas are arbitrary JSON and we don't want to force a domain shape
/// at the proxy boundary.
enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }
}

// MARK: - Errors

enum NutritionProxyError: AbortError {
    case missingAPIKey
    case unknownModel(String)
    case modelNotAllowed(String)
    case apiError(Int)
    case malformedResponse
    /// Monthly AI budget cap reached. Per AI_INTELLIGENCE_ENGINE.md §5.4.
    case budgetExhausted

    var status: HTTPResponseStatus {
        switch self {
        case .missingAPIKey: .internalServerError
        case .unknownModel, .modelNotAllowed: .badRequest
        case let .apiError(code) where code == 429: .tooManyRequests
        case .apiError: .badGateway
        case .malformedResponse: .badGateway
        case .budgetExhausted: .serviceUnavailable
        }
    }

    var reason: String {
        switch self {
        case .missingAPIKey: "Anthropic API key not configured on server."
        case let .unknownModel(raw): "Unknown model identifier: \(raw). Use 'haiku' or 'sonnet'."
        case let .modelNotAllowed(msg): msg
        case let .apiError(code): "Claude API error (HTTP \(code))."
        case .malformedResponse: "Claude returned a malformed response."
        case .budgetExhausted: "AI budget exhausted for this month."
        }
    }
}

// MARK: - Wire DTOs (private)

private struct ProxyClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [ProxyMessage]
    /// Tool schemas forwarded verbatim to Claude. `nil` for text/vision; set
    /// for the chat endpoint. Omitted from JSON when nil so Anthropic does
    /// not see an explicit `null`.
    var tools: [NutritionProxyChatRequest.ChatTool]? = nil
    /// `auto` | `any` | `{type:"tool",name:"X"}`. Same nil-omit rule as `tools`.
    var toolChoice: NutritionProxyChatRequest.ChatToolChoice? = nil

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens
        case temperature
        case system
        case messages
        case tools
        case toolChoice
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(system, forKey: .system)
        try c.encode(messages, forKey: .messages)
        if let tools, !tools.isEmpty { try c.encode(tools, forKey: .tools) }
        if let toolChoice { try c.encode(toolChoice, forKey: .toolChoice) }
    }
}

private struct ProxyMessage: Encodable {
    let role: String
    let content: ProxyMessageContent

    /// Coarse character count used by the budget tracker to estimate the
    /// input-token bill before the call. Image bytes are NOT counted —
    /// Anthropic prices vision input differently and our estimate is
    /// intentionally conservative.
    var estimatedCharCount: Int {
        switch content {
        case let .text(s): s.count
        case let .blocks(blocks):
            blocks.reduce(0) { acc, b in
                if case let .text(t) = b { return acc + t.count }
                return acc
            }
        }
    }
}

/// Anthropic accepts `content` as either a string OR an array of blocks.
/// For text-only requests we keep it as a plain string (matches NutritionAIService).
/// For vision requests we send the array form.
private enum ProxyMessageContent: Encodable {
    case text(String)
    case blocks([ProxyContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(s): try container.encode(s)
        case let .blocks(b): try container.encode(b)
        }
    }
}

private enum ProxyContentBlock: Encodable {
    case text(String)
    case image(source: ProxyImageSource)
    /// Assistant echo of a prior tool_use block — required by Anthropic when
    /// continuing a multi-turn tool conversation.
    case toolUse(id: String, name: String, input: JSONValue)
    /// User echo of a tool result corresponding to a prior tool_use.
    case toolResult(toolUseId: String, isError: Bool?, resultText: String?)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case isError = "is_error"
        case content
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case let .image(source):
            try c.encode("image", forKey: .type)
            try c.encode(source, forKey: .source)
        case let .toolUse(id, name, input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case let .toolResult(toolUseId, isError, resultText):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseId, forKey: .toolUseId)
            if let isError { try c.encode(isError, forKey: .isError) }
            if let resultText { try c.encode(resultText, forKey: .content) }
        }
    }
}

private struct ProxyImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct ProxyClaudeRawResponse: Decodable {
    let content: [Block]
    let usage: Usage
    /// Anthropic stop_reason. Optional because legacy text/vision callers
    /// don't read it; chat callers do.
    let stopReason: String?

    struct Block: Decodable {
        let type: String
        // text block
        let text: String?
        // tool_use block
        let id: String?
        let name: String?
        let input: JSONValue?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
    }
}
