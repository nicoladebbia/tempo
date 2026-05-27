//
// CoachChatProxyDTOs.swift
// Tempo
//
// Coach v2.1 Phase 7a — iOS-side DTOs + APIEndpoint factory for the
// backend coach-chat route (POST /v1/nutrition/ai/coach/chat).
//
// These mirror Phase 1's CoachProxyChatRequest / CoachProxyChatResponse
// shape on the backend. Adapters (CoachChatAIClientAdapter,
// ConversationSummarizerAIClientAdapter) wrap the iOS-side
// CoachChatRequest / ConversationSummarizationRequest into these wire
// DTOs, post via APIClient, and map the response back into the
// iOS-side CoachChatResponse / String summary used by Phase 6b.
//
// Per .plans/coach-v2.1/04-ai-architecture.md "Tool-use protocol" and
// Phase 1 commit `b77fd0cb` (backend tool-use route).
//

import Foundation

// MARK: - Wire DTOs

/// Mirrors backend `CoachProxyChatRequest`. Snake-case keys match the
/// backend's `convertFromSnakeCase` decoder.
struct CoachChatProxyRequest: Codable, Sendable {
    /// "haiku" (default) | "sonnet" | "opus"
    let model: String?
    /// Clamped server-side to [64, 4096].
    let maxTokens: Int
    /// Assembled system-prompt body from CoachContextAssembler.
    let system: String
    /// Conversation history including the new user message at the end.
    let messages: [CoachChatProxyMessage]
    /// Tool definitions advertised for this turn.
    let tools: [CoachChatProxyTool]
    /// nil → "auto" (Anthropic default).
    let toolChoice: CoachChatProxyToolChoice?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case toolChoice = "tool_choice"
    }
}

/// One conversation turn. role is "user" (also used for tool_result
/// turns per Anthropic protocol) or "assistant".
struct CoachChatProxyMessage: Codable, Sendable {
    let role: String
    let content: [CoachChatProxyContentBlock]
}

/// Polymorphic content block. Matches the backend's tagged-union
/// schema (Phase 1 commit `b77fd0cb`).
enum CoachChatProxyContentBlock: Codable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, inputJSON: Data)
    case toolResult(toolUseID: String, content: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            // Re-encode `input` as raw JSON bytes — the dispatcher
            // deserializes per tool. Avoids type-erasing here.
            let inputAny = try container.decode(AnyJSON.self, forKey: .input)
            let json = try JSONEncoder().encode(inputAny)
            self = .toolUse(id: id, name: name, inputJSON: json)
        case "tool_result":
            let id = try container.decode(String.self, forKey: .toolUseID)
            let content = try container.decode(String.self, forKey: .content)
            let isError = (try? container.decode(Bool.self, forKey: .isError)) ?? false
            self = .toolResult(toolUseID: id, content: content, isError: isError)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .toolUse(id, name, inputJSON):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            // Decode the opaque bytes back into a Codable any-tree so the
            // backend sees a real JSON object, not a string.
            if let any = try? JSONDecoder().decode(AnyJSON.self, from: inputJSON) {
                try container.encode(any, forKey: .input)
            } else {
                try container.encode(AnyJSON.object([:]), forKey: .input)
            }
        case let .toolResult(id, content, isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(id, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError { try container.encode(true, forKey: .isError) }
        }
    }
}

/// Tool advertisement. Mirrors backend `CoachTool`.
struct CoachChatProxyTool: Codable, Sendable {
    let name: String
    let description: String
    /// JSON Schema describing the tool input. We pass a pre-built dict
    /// since the schemas are static per tool.
    let inputSchema: AnyJSON

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

/// Tool-choice control. nil omits the field and defaults to auto.
enum CoachChatProxyToolChoice: Codable, Sendable {
    case auto
    case any
    case tool(name: String)

    private enum CodingKeys: String, CodingKey {
        case type, name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "auto": self = .auto
        case "any": self = .any
        case "tool": self = .tool(name: try c.decode(String.self, forKey: .name))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown tool_choice type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto: try c.encode("auto", forKey: .type)
        case .any: try c.encode("any", forKey: .type)
        case let .tool(name):
            try c.encode("tool", forKey: .type)
            try c.encode(name, forKey: .name)
        }
    }
}

/// Mirrors backend `CoachProxyChatResponse`.
struct CoachChatProxyResponse: Codable, Sendable {
    let content: [CoachChatProxyContentBlock]
    let stopReason: String?
    let usage: Usage
    let model: String

    struct Usage: Codable, Sendable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case usage
        case model
    }
}

// MARK: - APIEndpoint extension

extension APIEndpoint where Response == CoachChatProxyResponse {
    /// POST /v1/nutrition/ai/coach/chat — Phase 1 backend tool-use route.
    static func coachChat() -> Self {
        APIEndpoint(path: "/v1/nutrition/ai/coach/chat", method: .post)
    }
}

// MARK: - AnyJSON

/// Free-form JSON value used for tool input schemas + tool_use args.
/// Mirrors the backend's AnyCodable shape but with a discriminated
/// union for clean Codable conformance.
enum AnyJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([AnyJSON].self) { self = .array(a); return }
        if let o = try? container.decode([String: AnyJSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "AnyJSON: unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(b): try container.encode(b)
        case let .int(i): try container.encode(i)
        case let .double(d): try container.encode(d)
        case let .string(s): try container.encode(s)
        case let .array(a): try container.encode(a)
        case let .object(o): try container.encode(o)
        }
    }
}
