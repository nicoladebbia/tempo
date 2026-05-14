import Crypto
import Foundation
import Vapor

// MARK: - DashboardInsightsService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.10 + INTELLIGENCE_REMEDIATION_PLAN.md §7.5.
//
// Short natural-language insights surfaced on the dashboard. Haiku, cached by
// data hash so the cache key changes ONLY when the underlying input changes.
// Effective TTL: "until data changes". The Redis-backed AICacheKey gives a
// memory ceiling.

struct DashboardInsightsService {
    static let shared = DashboardInsightsService()
    private init() {}

    func extractContext(from req: Request, userId: String) throws -> DashboardInsightsInput {
        try req.content.decode(DashboardInsightsInput.self).withUserID(userId)
    }

    func generate(
        input: DashboardInsightsInput,
        on req: Request,
        bypassCache: Bool = false
    ) async throws -> DashboardInsightsResponse {
        // Hash inputs so the cache key changes when any input does.
        let hash = Self.dataHash(of: input)
        let spec = AIFeatureSpec<DashboardInsightsResponse>(
            model: AIConfig.haikuModel,
            maxTokens: 400,
            temperature: 0.5,
            timeout: AIConfig.haikuTimeout,
            estimatedInputTokens: 1_500,
            cacheKey: .dashboardInsights(userId: input.userId ?? "", dataHash: hash)
        )
        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            bypassCache: bypassCache,
            buildPrompts: {
                (DashboardInsightsPrompts.system, DashboardInsightsPrompts.buildUserPrompt(from: input))
            },
            parse: { raw in try Self.parseJSON(raw) },
            fallback: { Self.fallback(input: input) }
        )
        return value
    }

    private static func dataHash(of input: DashboardInsightsInput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(input)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func parseJSON(_ raw: String) throws -> DashboardInsightsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            s = String(raw[start ... end])
        } else {
            s = raw
        }
        guard let data = s.data(using: .utf8) else { throw InsightError.malformedResponse }
        return try decoder.decode(DashboardInsightsResponse.self, from: data)
    }

    static func fallback(input: DashboardInsightsInput) -> DashboardInsightsResponse {
        DashboardInsightsResponse(insights: [
            DashboardInsight(
                icon: "chart.bar",
                title: "Tracking on plan",
                body: "Today's metrics are within your 7-day average."
            )
        ])
    }
}

struct DashboardInsightsInput: Content {
    var userId: String? = nil
    let todayRecovery: Int
    let recovery7DayAvg: Int
    let todayProtein: Int
    let proteinTarget: Int
    let todayStudyMinutes: Int
    let studyTarget: Int
    let streakDays: Int


    func withUserID(_ id: String) -> DashboardInsightsInput {
        var copy = self
        copy.userId = id
        return copy
    }
}

struct DashboardInsight: Content {
    let icon: String
    let title: String
    let body: String
}

struct DashboardInsightsResponse: Content {
    let insights: [DashboardInsight]
}

enum DashboardInsightsPrompts {
    static let system = """
    You generate dashboard insight cards for a student-athlete fitness app. Each insight is one icon + one short title + one short body. Reference exact numbers from the data. Output ONLY valid JSON.
    """

    static func buildUserPrompt(from x: DashboardInsightsInput) -> String {
        """
        Recovery today: \(x.todayRecovery)% (7-day avg: \(x.recovery7DayAvg)%)
        Protein today: \(x.todayProtein)g / \(x.proteinTarget)g
        Study today: \(x.todayStudyMinutes) min / \(x.studyTarget) min
        Streak: \(x.streakDays) days

        Return JSON:
        {"insights":[{"icon":"sf-symbol-name","title":"Short","body":"One sentence with specifics"}]}

        Generate 2-3 insights. Use SF Symbol names for icon. Reference the user's actual numbers.
        """
    }
}
