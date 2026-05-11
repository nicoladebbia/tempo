import Vapor

// MARK: - NutritionAIController

// Routes:
//   POST /v1/nutrition/ai/explain-adjustment — drill-sergeant explanation of a macro adjustment
//   POST /v1/nutrition/ai/suggest-meal       — pantry-aware meal suggestion using remaining macros
//
// Per AI_INTELLIGENCE_ENGINE.md Section 2 + NUTRITION_MODULE_BUILD_PLAN.md N5.1:
//   - All calls Haiku 4.5
//   - Rate-limited per-user via parent route group
//   - Budget tracked server-side (InsightService.shared owns the budget)

struct NutritionAIController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("explain-adjustment", use: explainAdjustment)
        routes.post("suggest-meal", use: suggestMeal)
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
