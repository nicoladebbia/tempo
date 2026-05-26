import Vapor

// MARK: - NutritionAIController

// Routes:
//   POST /v1/nutrition/ai/explain-adjustment — drill-sergeant explanation of a macro adjustment
//   POST /v1/nutrition/ai/suggest-meal       — pantry-aware meal suggestion using remaining macros
//   POST /v1/nutrition/ai/proxy/text         — generic text proxy (Haiku/Sonnet) for iOS-rendered prompts
//   POST /v1/nutrition/ai/proxy/vision       — generic vision proxy (Haiku) for photo meal logging
//
// Per AI_INTELLIGENCE_ENGINE.md Section 2 + NUTRITION_MODULE_BUILD_PLAN.md N5.1:
//   - All calls Haiku 4.5 (explain/suggest) or caller-selected (proxy/*)
//   - Rate-limited per-user via parent route group
//   - Budget tracked server-side (InsightService.shared owns the budget)
//
// The proxy/* routes exist to migrate iOS-side ClaudeAPIClient callers off the
// embedded Anthropic key. iOS renders its own prompts (because they reference
// SwiftData-bound types) and posts the rendered prompt here. Per
// INTELLIGENCE_REMEDIATION_PLAN.md §3.

struct NutritionAIController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("explain-adjustment", use: explainAdjustment)
        routes.post("suggest-meal", use: suggestMeal)
        // §3.8 Meal Timing per INTELLIGENCE_REMEDIATION_PLAN.md §7.7
        routes.post("meal-timing", use: mealTiming)

        let proxy = routes.grouped("proxy")
        proxy.on(.POST, "text", body: .collect(maxSize: "256kb"), use: proxyText)
        // Vision uploads can be up to ~5MB base64 (3.5MB raw image). Bump the
        // body limit explicitly so the route does not 413 on legitimate photo
        // meal logs.
        proxy.on(.POST, "vision", body: .collect(maxSize: "5mb"), use: proxyVision)

        // Coach chat (v2.1) — stateless single-turn relay with tool-use.
        // Per Coach v2.1 plan §03-services-and-data-flow.md. iOS drives the
        // tool-use loop; this endpoint is one Anthropic round-trip per request.
        // 256kb is plenty for the largest plausible system+history+tools payload.
        let coach = routes.grouped("coach")
        coach.on(.POST, "chat", body: .collect(maxSize: "256kb"), use: coachChat)
    }

    @Sendable
    func explainAdjustment(req: Request) async throws -> Envelope<ExplainAdjustmentResponse> {
        _ = try req.auth.requireUserID()
        let input = try req.content.decode(ExplainAdjustmentRequest.self)
        let text = try await NutritionAIService.shared.explainAdjustment(input: input, on: req)
        return Envelope(data: .init(message: text), requestID: req.requestID)
    }

    @Sendable
    func suggestMeal(req: Request) async throws -> Envelope<SuggestMealResponse> {
        _ = try req.auth.requireUserID()
        let input = try req.content.decode(SuggestMealRequest.self)
        let text = try await NutritionAIService.shared.suggestMeal(input: input, on: req)
        return Envelope(data: .init(message: text), requestID: req.requestID)
    }

    @Sendable
    func mealTiming(req: Request) async throws -> Envelope<MealTimingResponse> {
        let userId = try req.auth.requireUserID()
        let body = try req.content.decode(MealTimingInput.self)
        let bypass = req.query[Bool.self, at: "force_regenerate"] ?? false
        let result = try await MealTimingService.shared.generate(
            input: body.withUserID(userId), on: req, bypassCache: bypass
        )
        return Envelope(data: result, requestID: req.requestID)
    }

    @Sendable
    func proxyText(req: Request) async throws -> Envelope<NutritionProxyTextResponse> {
        _ = try req.auth.requireUserID()
        let input = try req.content.decode(NutritionProxyTextRequest.self)
        let response = try await NutritionClaudeProxyService.shared.sendText(input: input, on: req)
        return Envelope(data: response, requestID: req.requestID)
    }

    @Sendable
    func proxyVision(req: Request) async throws -> Envelope<NutritionProxyTextResponse> {
        _ = try req.auth.requireUserID()
        let input = try req.content.decode(NutritionProxyVisionRequest.self)
        let response = try await NutritionClaudeProxyService.shared.sendVision(input: input, on: req)
        return Envelope(data: response, requestID: req.requestID)
    }


    @Sendable
    func coachChat(req: Request) async throws -> Envelope<CoachProxyChatResponse> {
        _ = try req.auth.requireUserID()
        let input = try req.content.decode(CoachProxyChatRequest.self)
        let response = try await CoachClaudeProxyService.shared.sendCoachChat(input: input, on: req)
        return Envelope(data: response, requestID: req.requestID)
    }
}

// MARK: - DTOs

struct ExplainAdjustmentRequest: Content {
    let mode: String
    let recoveryZone: String?
    let isTrainingDay: Bool
    let baseCalories: Int
    let adjustedCalories: Int
    let baseProtein: Int
    let adjustedProtein: Int
    let modeExplanation: String
}

struct ExplainAdjustmentResponse: Content {
    let message: String
}

struct SuggestMealRequest: Content {
    let pantryCanonicalNames: [String]
    let remainingCalories: Int
    let remainingProtein: Int
    let recoveryZone: String?
    let isTrainingDay: Bool
}

struct SuggestMealResponse: Content {
    let message: String
}
