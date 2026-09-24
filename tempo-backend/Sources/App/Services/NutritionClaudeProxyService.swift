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
        let text = try await callClaudeWithImages(
            model: model,
            system: input.system,
            userMessage: input.userMessage,
            images: [(mediaType: input.imageMediaType, base64: input.imageBase64, hint: nil)],
            maxTokens: input.maxTokens,
            temperature: input.temperature,
            timeout: timeout,
            caller: input.caller,
            on: req
        )
        return NutritionProxyTextResponse(text: text)
    }

    /// Send a pre-rendered prompt with SEVERAL base64-encoded images in ONE
    /// Claude call (multiple image content blocks in a single user message).
    /// Used by the Trainer Program import TRANSCRIBE step so a multi-page
    /// import costs one request per batch of pages instead of one per page.
    /// Per-image `hint` text (e.g. on-device OCR for that specific page), when
    /// present, is inserted as its own text block immediately after that
    /// image so the model can weigh it against the image it describes.
    func sendMultiImage(
        input: NutritionProxyMultiImageRequest,
        on req: Request
    ) async throws -> NutritionProxyTextResponse {
        let model = try resolveModel(input.model)
        let timeout = timeout(for: model)
        let text = try await callClaudeWithImages(
            model: model,
            system: input.system,
            userMessage: input.userMessage,
            images: input.images.enumerated().map { index, image in
                let hint = input.hintTexts.indices.contains(index) ? input.hintTexts[index] : nil
                return (mediaType: image.mediaType, base64: image.base64, hint: hint)
            },
            maxTokens: input.maxTokens,
            temperature: input.temperature,
            timeout: timeout,
            caller: input.caller,
            on: req
        )
        return NutritionProxyTextResponse(text: text)
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

    /// Generalized N-image call. `images` are emitted in order, each
    /// optionally followed by its own hint text block, then `userMessage` is
    /// appended last. A single-image call (sendVision) is just this with a
    /// one-element array and no hint.
    private func callClaudeWithImages(
        model: String,
        system: String,
        userMessage: String,
        images: [(mediaType: String, base64: String, hint: String?)],
        maxTokens: Int,
        temperature: Double,
        timeout: TimeInterval,
        caller: String,
        on req: Request
    ) async throws -> String {
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw NutritionProxyError.missingAPIKey
        }

        var blocks: [ProxyContentBlock] = []
        for image in images {
            blocks.append(.image(source: .init(type: "base64", mediaType: image.mediaType, data: image.base64)))
            if let hint = image.hint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
                blocks.append(.text(
                    "(On-device text hint for the page above — may be imperfect or out of order; weigh it against the image):\n\(hint.prefix(4000))"
                ))
            }
        }
        blocks.append(.text(userMessage))

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
        // Pre-flight budget gate. Per AI_INTELLIGENCE_ENGINE.md §5.4 +
        // INTELLIGENCE_REMEDIATION_PLAN.md §5. Input-token estimate uses
        // a rough heuristic (system + user character count / 4).
        let inputEstimate = max(500, (body.system.count + (body.messages.first?.estimatedCharCount ?? 0)) / 4)
        let costEstimate = AIBudgetTracker.shared.estimateCostCents(
            model: body.model,
            estimatedInputTokens: inputEstimate,
            maxOutputTokens: body.maxTokens
        )
        guard await AIBudgetTracker.shared.canMakeCall(estimatedCostCents: costEstimate, on: req) else {
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
        guard let textBlock = raw.content.first(where: { $0.type == "text" }) else {
            throw NutritionProxyError.malformedResponse
        }

        // Persistent post-call accounting against the monthly budget.
        await AIBudgetTracker.shared.recordSpend(
            model: body.model,
            inputTokens: raw.usage.inputTokens,
            outputTokens: raw.usage.outputTokens,
            on: req
        )

        req.logger.info(
            "[nutrition_proxy \(caller)] ok model=\(body.model) in=\(raw.usage.inputTokens) out=\(raw.usage.outputTokens)"
        )
        return textBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// One image in a multi-image request.
struct NutritionProxyImageInput: Content {
    /// e.g. "image/jpeg", "image/png", "image/webp"
    let mediaType: String
    /// Base64-encoded image bytes (no data: prefix).
    let base64: String
}

/// Several images in ONE Claude call — see `sendMultiImage`. `hintTexts`,
/// when present, must be the same length as `images`; `nil`/absent entries
/// simply mean "no hint for this page".
struct NutritionProxyMultiImageRequest: Content {
    let model: String
    let system: String
    let userMessage: String
    let images: [NutritionProxyImageInput]
    let hintTexts: [String?]
    let maxTokens: Int
    let temperature: Double
    let caller: String
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
                if case let .text(t) = b {
                    return acc + t.count
                }
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

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
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

    struct Block: Decodable {
        let type: String
        let text: String
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
    }
}
