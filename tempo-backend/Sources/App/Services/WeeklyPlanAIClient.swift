import Vapor

// MARK: - WeeklyPlanAIClient

//
// Thin seam around NutritionClaudeProxyService for WeeklyPlanJob's one
// Claude call. NutritionClaudeProxyService is an actor singleton with no
// protocol of its own, so tests can't inject a fake through it directly —
// this protocol exists purely so WeeklyPlanJobTests can stub the AI call
// without hitting the network or the real budget tracker.

protocol WeeklyPlanAIClient: Sendable {
    /// Sends the stored system + prompt to Claude Sonnet and returns the raw
    /// text completion (still possibly fenced / with leading commentary —
    /// WeeklyPlanPipeline.extractJSON handles that).
    func generate(system: String, prompt: String, on req: Request) async throws -> String
}

struct LiveWeeklyPlanAIClient: WeeklyPlanAIClient {
    func generate(system: String, prompt: String, on req: Request) async throws -> String {
        let input = NutritionProxyTextRequest(
            model: "sonnet",
            system: system,
            userMessage: prompt,
            maxTokens: 32768,
            temperature: 0.3,
            caller: "weekly_plan_job"
        )
        let response = try await NutritionClaudeProxyService.shared.sendText(input: input, on: req)
        return response.text
    }
}
