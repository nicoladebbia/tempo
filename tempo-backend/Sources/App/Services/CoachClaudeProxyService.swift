import Foundation
import Vapor

// MARK: - CoachClaudeProxyService
//
// Per Coach v2.1 plan §04-ai-architecture.md.
//
// Stateless single-turn relay between the iOS Coach client and Anthropic.
// Distinct from NutritionClaudeProxyService because the request/response
// shape is different:
//   - Tools (function definitions) in the request body
//   - tool_choice control field
//   - Polymorphic content blocks in both directions (text, tool_use, tool_result)
//   - stop_reason returned to iOS so the client knows whether to loop
//
// The tool-use loop lives on iOS. The backend is a thin auth + budget +
// auditing layer that forwards to Anthropic and returns the raw response
// structure intact.

final class CoachClaudeProxyService: @unchecked Sendable {
    static let shared = CoachClaudeProxyService()

    private init() {}

    // MARK: - Public

    /// Single-turn Coach chat call. Forwards messages + tools + tool_choice
    /// to Anthropic and returns text + tool_use blocks + stop_reason.
    /// Budget-gated against both the global cap and the coach sub-cap.
    func sendCoachChat(
        input: CoachProxyChatRequest,
        on req: Request
    ) async throws -> CoachProxyChatResponse {
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw CoachProxyError.missingAPIKey
        }

        let model = try resolveModel(input.model)
        let maxTokens = max(64, min(input.maxTokens, 4096))

        // Pre-flight budget gate — both the global cap and the coach sub-cap.
        // Input-token estimate uses a rough character-count heuristic across
        // the system prompt, message text blocks, and tool definitions.
        let estimatedInputTokens = estimateInputTokens(input: input)
        let costEstimate = AIBudgetTracker.shared.estimateCostCents(
            model: model,
            estimatedInputTokens: estimatedInputTokens,
            maxOutputTokens: maxTokens
        )
        guard await AIBudgetTracker.shared.canMakeCall(
            estimatedCostCents: costEstimate,
            caller: "coach",
            on: req
        ) else {
            req.logger.warning("[coach_proxy] budget exhausted (global or coach sub-cap)")
            throw CoachProxyError.budgetExhausted
        }

        // Build the Anthropic-shaped request.
        let body = AnthropicCoachRequest(
            model: model,
            maxTokens: maxTokens,
            system: input.system,
            messages: input.messages,
            tools: input.tools,
            toolChoice: input.toolChoice
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(body)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: "x-api-key", value: apiKey)
        headers.add(name: "anthropic-version", value: "2023-06-01")

        let response = try await req.client.post(
            URI(string: "https://api.anthropic.com/v1/messages"),
            headers: headers
        ) { clientReq in
            clientReq.body = .init(data: bodyData)
        }

        guard response.status == .ok else {
            req.logger.error("[coach_proxy] Claude HTTP \(response.status.code)")
            throw CoachProxyError.apiError(Int(response.status.code))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try response.content.decode(AnthropicCoachResponse.self, using: decoder)

        // Post-call spend accounting against the coach sub-budget.
        await AIBudgetTracker.shared.recordSpend(
            model: model,
            inputTokens: raw.usage.inputTokens,
            outputTokens: raw.usage.outputTokens,
            caller: "coach",
            on: req
        )

        let toolUseCount = raw.content.filter {
            if case .toolUse = $0 { return true }
            return false
        }.count
        req.logger.info(
            "[coach_proxy] ok model=\(model) in=\(raw.usage.inputTokens) out=\(raw.usage.outputTokens) stop=\(raw.stopReason ?? "?") tool_use_blocks=\(toolUseCount)"
        )

        return CoachProxyChatResponse(
            content: raw.content,
            stopReason: raw.stopReason,
            usage: .init(
                inputTokens: raw.usage.inputTokens,
                outputTokens: raw.usage.outputTokens
            ),
            model: model
        )
    }

    // MARK: - Model resolution

    /// Map the client-supplied tier label ("haiku" / "sonnet") to a concrete
    /// Anthropic model ID. Defaults to Haiku — Coach's hot path.
    private func resolveModel(_ tier: String?) throws -> String {
        switch tier?.lowercased() {
        case "haiku", nil, "": return AIConfig.haikuModel
        case "sonnet": return AIConfig.sonnetModel
        case "opus":
            // Opus is allowed but expensive; not the typical Coach tier.
            return AIConfig.opusModel
        default:
            throw CoachProxyError.invalidModel(tier ?? "")
        }
    }

    // MARK: - Cost estimation

    /// Rough character-count → token estimate. Same conservatism as the
    /// nutrition proxy: count system + all message text + tool definitions.
    private func estimateInputTokens(input: CoachProxyChatRequest) -> Int {
        var chars = input.system.count
        for message in input.messages {
            chars += message.estimatedCharCount
        }
        // Tool definitions add roughly their JSON-encoded length to the input.
        if let toolsJSON = try? JSONEncoder().encode(input.tools) {
            chars += toolsJSON.count
        }
        return max(500, chars / 4)
    }
}

// MARK: - Public DTOs (callable from controller)

/// Single-turn chat request. iOS sends one of these per loop iteration.
/// The iOS client drives the tool-use loop; the backend is stateless.
struct CoachProxyChatRequest: Content {
    /// Optional model tier: "haiku" (default), "sonnet", "opus".
    let model: String?

    /// max_tokens for this turn. Clamped server-side to [64, 4096].
    let maxTokens: Int

    /// Assembled system prompt (~3.7K tokens at p95 user data per plan §04).
    let system: String

    /// Conversation history including the new user message at the end.
    /// Each message uses polymorphic content blocks.
    let messages: [CoachMessage]

    /// Tool definitions available this turn.
    let tools: [CoachTool]

    /// Tool-choice control. nil → "auto".
    let toolChoice: CoachToolChoice?
}

/// Single-turn chat response. iOS inspects stopReason to decide whether to
/// loop (run tools, send tool_result back) or terminate.
struct CoachProxyChatResponse: Content {
    let content: [CoachContentBlock]
    /// Anthropic's stop_reason: "end_turn", "tool_use", "max_tokens", etc.
    let stopReason: String?
    let usage: Usage
    let model: String

    struct Usage: Content {
        let inputTokens: Int
        let outputTokens: Int
    }
}

// MARK: - Polymorphic message + content block types

/// One conversation turn. The role is "user" (also used for tool_result
/// turns per Anthropic protocol) or "assistant".
struct CoachMessage: Content {
    let role: String
    let content: [CoachContentBlock]

    /// Characters across text blocks only. Used by the budget estimator;
    /// tool inputs/outputs are excluded (they're typically tiny).
    var estimatedCharCount: Int {
        content.reduce(0) { acc, block in
            switch block {
            case let .text(text): acc + text.count
            case let .toolResult(_, output, _): acc + output.count
            case .toolUse: acc
            }
        }
    }
}

/// Polymorphic content block. Anthropic's API uses a tagged union here;
/// we mirror it with an enum + custom Codable.
enum CoachContentBlock: Content {
    case text(String)
    /// Assistant-emitted tool call. iOS dispatches the named local Swift fn.
    case toolUse(id: String, name: String, input: [String: AnyCodable])
    /// User-emitted result of a prior tool call. content is a stringified
    /// representation of the tool's return value (JSON or plain text);
    /// isError flags failures so the agent can self-recover.
    case toolResult(toolUseID: String, content: String, isError: Bool)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
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
            let input = try container.decode([String: AnyCodable].self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
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
        case let .toolUse(id, name, input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .toolResult(id, content, isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(id, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        }
    }
}

/// Tool definition advertised to the model.
struct CoachTool: Content {
    let name: String
    let description: String
    /// JSON Schema describing the tool's input arguments. Free-form to
    /// preserve schema flexibility — Anthropic validates it server-side.
    let inputSchema: AnyCodable

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

/// Tool selection control. iOS usually passes "auto"; "any" forces a tool;
/// `.tool(name:)` forces a specific named tool.
enum CoachToolChoice: Content {
    case auto
    case any
    case tool(name: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "auto": self = .auto
        case "any": self = .any
        case "tool":
            let name = try container.decode(String.self, forKey: .name)
            self = .tool(name: name)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool_choice type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .any:
            try container.encode("any", forKey: .type)
        case let .tool(name):
            try container.encode("tool", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

// MARK: - Errors

enum CoachProxyError: AbortError {
    case missingAPIKey
    case invalidModel(String)
    case apiError(Int)
    case budgetExhausted
    case malformedResponse

    var status: HTTPResponseStatus {
        switch self {
        case .missingAPIKey: return .internalServerError
        case .invalidModel: return .badRequest
        case let .apiError(code):
            // Surface upstream 4xx as 502 to distinguish from client error.
            return code >= 500 ? .badGateway : .badGateway
        case .budgetExhausted: return .serviceUnavailable
        case .malformedResponse: return .badGateway
        }
    }

    var reason: String {
        switch self {
        case .missingAPIKey:
            return "Anthropic API key not configured."
        case let .invalidModel(model):
            return "Unknown coach model tier: \(model)."
        case let .apiError(code):
            return "Upstream AI provider error (\(code))."
        case .budgetExhausted:
            return "Coach is at this month's budget. Try again next month."
        case .malformedResponse:
            return "Coach response was malformed."
        }
    }
}

// MARK: - Wire DTOs (Anthropic shape, private)

private struct AnthropicCoachRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [CoachMessage]
    let tools: [CoachTool]
    let toolChoice: CoachToolChoice?
}

private struct AnthropicCoachResponse: Decodable {
    let content: [CoachContentBlock]
    let stopReason: String?
    let usage: Usage

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
    }
}

// MARK: - AnyCodable
//
// Free-form JSON support for tool input schemas + tool_use arguments. The
// model's tool calls have arbitrary nested structures we can't type-erase
// upfront; AnyCodable lets us round-trip them as opaque JSON values.

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable: unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodable.init))
        case let any as AnyCodable:
            try any.encode(to: encoder)
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "AnyCodable: unsupported value type")
            )
        }
    }
}
