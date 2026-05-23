//
// NutritionProxyDTOs.swift
// Tempo
//
// iOS-side DTOs + endpoint definitions for the generic nutrition Claude proxy
// on the backend (POST /v1/nutrition/ai/proxy/text and .../proxy/vision).
//
// The proxy moves all nutrition AI Claude calls server-side so the Anthropic
// API key never ships in the app binary. Per ADR-018 + INTELLIGENCE_REMEDIATION_PLAN.md §3.
//

import Foundation

// MARK: - Text proxy request / response

/// Mirrors backend `NutritionProxyTextRequest` (snake_case wire format).
struct NutritionProxyTextRequest: Codable, Sendable {
    /// One of: "haiku", "sonnet". Backend rejects anything else (Opus is
    /// reserved for pattern detection per AI spec §1).
    let model: String
    let system: String
    let userMessage: String
    let maxTokens: Int
    let temperature: Double
    /// Short tag for backend logs — e.g. "meal_plan", "meal_recipe", "coach".
    let caller: String

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case userMessage = "user_message"
        case maxTokens = "max_tokens"
        case temperature
        case caller
    }
}

/// Mirrors backend `NutritionProxyVisionRequest`. Used by PhotoAnalysisService.
struct NutritionProxyVisionRequest: Codable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case userMessage = "user_message"
        case imageMediaType = "image_media_type"
        case imageBase64 = "image_base64"
        case maxTokens = "max_tokens"
        case temperature
        case caller
    }
}

/// Mirrors backend `NutritionProxyTextResponse`. The backend strips the
/// surrounding Envelope before this is decoded (see APIClient).
struct NutritionProxyTextResponse: Codable, Sendable {
    let text: String
}

// MARK: - Coach chat (multi-turn, tool-use)

/// Mirrors backend `NutritionProxyChatRequest`. Drives the CoachService
/// agent loop — each iteration POSTs the running transcript + tool
/// schemas, parses tool_use blocks out of the response, dispatches the
/// tools on device, appends tool_results, and loops.
struct NutritionProxyChatRequest: Codable, Sendable {
    let model: String
    let system: String
    let messages: [ChatMessage]
    let tools: [ChatTool]?
    let toolChoice: ChatToolChoice?
    let maxTokens: Int
    let temperature: Double
    let caller: String

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case toolChoice = "tool_choice"
        case maxTokens = "max_tokens"
        case temperature, caller
    }

    struct ChatMessage: Codable, Sendable {
        let role: String
        let content: [ChatBlock]
    }

    struct ChatBlock: Codable, Sendable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: JSONValue?
        let toolUseId: String?
        let isError: Bool?
        let resultText: String?

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
            case toolUseId = "tool_use_id"
            case isError = "is_error"
            case resultText = "content"
        }
    }

    struct ChatTool: Codable, Sendable {
        let name: String
        let description: String
        let inputSchema: JSONValue

        enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "input_schema"
        }
    }

    enum ChatToolChoice: Codable, Sendable {
        case auto
        case any
        case tool(name: String)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            struct Obj: Codable { let type: String; let name: String? }
            let obj = try c.decode(Obj.self)
            switch obj.type {
            case "auto": self = .auto
            case "any": self = .any
            case "tool":
                guard let n = obj.name else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "tool missing name") }
                self = .tool(name: n)
            default: throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown \(obj.type)")
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

    /// Permissive JSON box for tool input/output schemas.
    enum JSONValue: Codable, Sendable, Equatable {
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
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported")
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
}

/// Mirrors backend `NutritionProxyChatResponse`.
struct NutritionProxyChatResponse: Codable, Sendable {
    let stopReason: String
    let blocks: [Block]
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
        case blocks, usage
    }

    struct Block: Codable, Sendable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: NutritionProxyChatRequest.JSONValue?
    }

    struct Usage: Codable, Sendable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

// MARK: - APIEndpoint extensions

extension APIEndpoint where Response == NutritionProxyTextResponse {
    static func nutritionProxyText() -> Self {
        // Sonnet weekly-meal-plan generation routinely takes 90–120s with
        // maxTokens=32_768. Default 60s timeout produced silent timeout failures
        // after a successful 401-refresh+retry. Give the proxy a longer leash.
        APIEndpoint(path: "/v1/nutrition/ai/proxy/text", method: .post, timeoutInterval: 180)
    }

    static func nutritionProxyVision() -> Self {
        // Vision proxy (Haiku) carries an image payload and an AI roundtrip;
        // 60s default is borderline. Same long-leash rationale as proxyText.
        APIEndpoint(path: "/v1/nutrition/ai/proxy/vision", method: .post, timeoutInterval: 120)
    }
}
