import Foundation
import Vapor

// MARK: - MealTimingService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.8 + INTELLIGENCE_REMEDIATION_PLAN.md §7.7.
//
// Recommends WHEN to eat each meal today given today's recovery and training
// schedule. Haiku. Cached 2h Redis per (user, date, meal_index) so morning
// requests can serve afternoon meals without re-calling.

struct MealTimingService {
    static let shared = MealTimingService()
    private init() {}

    func generate(
        input: MealTimingInput,
        on req: Request,
        bypassCache: Bool = false
    ) async throws -> MealTimingResponse {
        let spec = AIFeatureSpec<MealTimingResponse>(
            model: AIConfig.haikuModel,
            maxTokens: 300,
            temperature: 0.3,
            timeout: AIConfig.haikuTimeout,
            estimatedInputTokens: 1_000,
            cacheKey: .mealTiming(userId: input.userId ?? "", date: input.date, mealIndex: input.mealIndex)
        )
        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            bypassCache: bypassCache,
            buildPrompts: { (MealTimingPrompts.system, MealTimingPrompts.buildUserPrompt(from: input)) },
            parse: { raw in try Self.parseJSON(raw) },
            fallback: { Self.fallback(input: input) }
        )
        return value
    }

    private static func parseJSON(_ raw: String) throws -> MealTimingResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            s = String(raw[start ... end])
        } else {
            s = raw
        }
        guard let data = s.data(using: .utf8) else { throw InsightError.malformedResponse }
        return try decoder.decode(MealTimingResponse.self, from: data)
    }

    static func fallback(input: MealTimingInput) -> MealTimingResponse {
        let defaultTimes = ["08:00", "12:30", "16:00", "19:30"]
        let suggested = defaultTimes[safe: input.mealIndex] ?? "12:00"
        return MealTimingResponse(
            suggestedTime: suggested,
            note: "Default meal time. AI commentary unavailable."
        )
    }
}

struct MealTimingInput: Content {
    var userId: String? = nil
    let date: String
    let mealIndex: Int                  // 0 = breakfast, 1 = lunch, etc.
    let mealName: String
    let plannedCalories: Int
    let plannedProteinGrams: Int
    let trainingTimeToday: String?      // "16:00" or nil
    let lastMealTime: String?           // previous meal eaten at
    let recoveryZone: String


    func withUserID(_ id: String) -> MealTimingInput {
        var copy = self
        copy.userId = id
        return copy
    }
}

struct MealTimingResponse: Content {
    let suggestedTime: String   // "HH:MM"
    let note: String
}

enum MealTimingPrompts {
    static let system = """
    You recommend optimal meal times for a student-athlete. Consider training time (protein within 90 min post-workout), last meal time (3-4h gap minimum), recovery zone. Output ONLY valid JSON.
    """

    static func buildUserPrompt(from x: MealTimingInput) -> String {
        """
        Meal: \(x.mealName) (\(x.plannedCalories) kcal, \(x.plannedProteinGrams)g protein)
        Training today at: \(x.trainingTimeToday ?? "none")
        Last meal at: \(x.lastMealTime ?? "none yet")
        Recovery: \(x.recoveryZone)

        Return JSON: {"suggested_time": "HH:MM", "note": "1 sentence why"}
        """
    }
}

// MARK: - Safe array index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
