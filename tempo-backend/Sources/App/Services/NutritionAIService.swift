import Foundation
import Vapor

// MARK: - NutritionAIService

// Thin Haiku-backed service for the two nutrition AI endpoints. Reuses the
// same Claude HTTP call shape as InsightService but with smaller prompts +
// no budget circuit breaker (volume is low — one call per user per ~6 hours).

actor NutritionAIService {
    static let shared = NutritionAIService()

    private init() {}

    // MARK: - Explain

    func explainAdjustment(
        input: ExplainAdjustmentRequest,
        on req: Request
    ) async throws -> String {
        let system = Self.explainSystemPrompt
        let user = """
        User is on a \(input.mode) day.
        Recovery zone: \(input.recoveryZone ?? "unknown").
        Training day: \(input.isTrainingDay ? "yes" : "no").
        Base calorie target: \(input.baseCalories) kcal. Adjusted to: \(input.adjustedCalories) kcal.
        Base protein target: \(input.baseProtein)g. Adjusted to: \(input.adjustedProtein)g.
        Engine's hand-written explanation: \(input.modeExplanation)

        Write a punchy 1–2 sentence drill-sergeant explanation of WHY today's macros shifted. \
        Direct, no fluff, no medical claims. Reference the recovery state if it changed the call.
        """
        return try await callHaiku(system: system, user: user, maxTokens: 200, on: req, caller: "nutrition_explain")
    }

    // MARK: - Suggest

    func suggestMeal(
        input: SuggestMealRequest,
        on req: Request
    ) async throws -> String {
        let system = Self.suggestSystemPrompt
        let pantryList = input.pantryCanonicalNames.prefix(40).joined(separator: ", ")
        let user = """
        Pantry (canonical food names): \(pantryList.isEmpty ? "empty" : pantryList).
        Remaining today: \(input.remainingCalories) kcal, \(input.remainingProtein)g protein.
        Recovery zone: \(input.recoveryZone ?? "unknown").
        Training day: \(input.isTrainingDay ? "yes" : "no").

        Suggest ONE realistic meal the user can make from the pantry to close today's macros. \
        Keep it under 2 sentences. Drill-sergeant tone. No measurements in cups/tbsp — use grams.
        """
        return try await callHaiku(system: system, user: user, maxTokens: 200, on: req, caller: "nutrition_suggest")
    }

    // MARK: - Claude call (text-only Haiku)

    private func callHaiku(
        system: String,
        user: String,
        maxTokens: Int,
        on req: Request,
        caller: String
    ) async throws -> String {
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw NutritionAIError.missingAPIKey
        }

        // Pre-flight budget gate. Per AI_INTELLIGENCE_ENGINE.md §5.4 +
        // INTELLIGENCE_REMEDIATION_PLAN.md §5.
        let estimate = AIBudgetEstimate.haiku(maxTokens: maxTokens, estimatedInputTokens: 1_000)
        guard await AIBudgetTracker.shared.canMakeCall(estimatedCostCents: estimate, on: req) else {
            req.logger.warning("Nutrition AI \(caller): budget exhausted")
            throw NutritionAIError.budgetExhausted
        }

        let body = NutritionClaudeRequest(
            model: AIConfig.haikuModel,
            maxTokens: maxTokens,
            temperature: 0.4,
            system: system,
            messages: [.init(role: "user", content: user)]
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
            req.logger.error("Nutrition AI \(caller) HTTP \(response.status.code)")
            throw NutritionAIError.apiError(Int(response.status.code))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try response.content.decode(NutritionClaudeRawResponse.self, using: decoder)
        guard let textBlock = raw.content.first(where: { $0.type == "text" }) else {
            throw NutritionAIError.malformedResponse
        }

        // Persistent post-call accounting. Per INTELLIGENCE_REMEDIATION_PLAN.md §5.
        await AIBudgetTracker.shared.recordSpend(
            model: AIConfig.haikuModel,
            inputTokens: raw.usage.inputTokens,
            outputTokens: raw.usage.outputTokens,
            on: req
        )

        return textBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompts

    private static let explainSystemPrompt = """
    You are Tempo's drill-sergeant nutrition coach. Explain macro adjustments in 1–2 short sentences with directness. \
    No medical claims, no hedging, no apology. Hit the WHY (recovery zone, training, rest day). Output plain text — no markdown.
    """

    private static let suggestSystemPrompt = """
    You are Tempo's drill-sergeant nutrition coach. Suggest exactly ONE realistic meal in 1–2 short sentences. \
    Use the pantry; pick foods the user owns. Quantify in grams, not cups. \
    Direct tone, no hedging, no apology. No markdown, no lists.
    """
}

// MARK: - Errors

enum NutritionAIError: AbortError {
    case missingAPIKey
    case apiError(Int)
    case malformedResponse
    /// Monthly AI spend cap reached. Per AI_INTELLIGENCE_ENGINE.md §5.4.
    case budgetExhausted

    var status: HTTPResponseStatus {
        switch self {
        case .missingAPIKey: .internalServerError
        case let .apiError(code) where code == 429: .tooManyRequests
        case .apiError: .badGateway
        case .malformedResponse: .badGateway
        case .budgetExhausted: .serviceUnavailable
        }
    }

    var reason: String {
        switch self {
        case .missingAPIKey: "Anthropic API key not configured."
        case let .apiError(code): "Claude API error (HTTP \(code))."
        case .malformedResponse: "Claude returned a malformed response."
        case .budgetExhausted: "AI budget exhausted for this month."
        }
    }
}

// MARK: - Wire DTOs (text-only, kept private)

private struct NutritionClaudeRequest: Codable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [NutritionClaudeMessage]
}

private struct NutritionClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct NutritionClaudeRawResponse: Decodable {
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
