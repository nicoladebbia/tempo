import Foundation
import Vapor

// MARK: - TrainingProgramService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.5 + INTELLIGENCE_REMEDIATION_PLAN.md §7.6.
//
// Generates a 7-day training program tailored to recovery trend, football
// schedule, and recent session history. Sonnet (deep reasoning, ~10s p95).
// Spec calls for this to run as a background job with a push notification on
// completion; for v1 we run synchronously and return when ready. Caller is
// expected to show a "generating your week..." UI for up to ~30s.

struct TrainingProgramService {
    static let shared = TrainingProgramService()
    private init() {}

    func generate(
        input: TrainingProgramInput,
        on req: Request,
        bypassCache: Bool = false
    ) async throws -> TrainingProgramResponse {
        let spec = AIFeatureSpec<TrainingProgramResponse>(
            model: AIConfig.sonnetModel,
            maxTokens: 2_500,
            temperature: 0.3,
            timeout: AIConfig.sonnetTimeout,
            estimatedInputTokens: 3_000,
            cacheKey: .trainingProgram(userId: input.userId ?? "", weekStart: input.weekStart)
        )
        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            bypassCache: bypassCache,
            buildPrompts: { (TrainingProgramPrompts.system, TrainingProgramPrompts.buildUserPrompt(from: input)) },
            parse: { raw in try Self.parseJSON(raw) },
            fallback: { Self.fallback(input: input) }
        )
        return value
    }

    private static func parseJSON(_ raw: String) throws -> TrainingProgramResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            s = String(raw[start ... end])
        } else {
            s = raw
        }
        guard let data = s.data(using: .utf8) else { throw InsightError.malformedResponse }
        return try decoder.decode(TrainingProgramResponse.self, from: data)
    }

    static func fallback(input: TrainingProgramInput) -> TrainingProgramResponse {
        // Rule-based 5-day PPL skeleton respecting football days.
        let split: [(String, String)] = [
            ("monday", "push"), ("tuesday", "pull"), ("wednesday", "legs"),
            ("thursday", "push"), ("friday", "pull"),
            ("saturday", input.footballDays.contains("saturday") ? "football" : "rest"),
            ("sunday", input.footballDays.contains("sunday") ? "football" : "rest")
        ]
        let days = split.map { TrainingProgramDay(day: $0.0, workoutType: $0.1, volumeAdjustment: 1.0) }
        return TrainingProgramResponse(
            weekStart: input.weekStart,
            days: days,
            rationale: "Rule-based fallback: standard PPL split honouring football days."
        )
    }
}

struct TrainingProgramInput: Content {
    var userId: String? = nil
    let weekStart: String
    let footballDays: [String]            // ["saturday"]
    let recentRecovery7Day: [Int]         // last 7 daily recovery scores
    let recentSessions: [String]          // last 4 session summaries
    let goal: String                      // "hypertrophy" | "strength" | "fat_loss"


    func withUserID(_ id: String) -> TrainingProgramInput {
        var copy = self
        copy.userId = id
        return copy
    }
}

struct TrainingProgramDay: Content {
    let day: String           // "monday"
    let workoutType: String   // "push" | "pull" | "legs" | "football" | "rest"
    let volumeAdjustment: Double
}

struct TrainingProgramResponse: Content {
    let weekStart: String
    let days: [TrainingProgramDay]
    let rationale: String
}

enum TrainingProgramPrompts {
    static let system = """
    You program 7-day training weeks for a student-athlete who plays football. Respect football days (no heavy legs the day before, no high-volume push the day before). Match volume to the 7-day recovery trend. Output ONLY valid JSON.
    """

    static func buildUserPrompt(from x: TrainingProgramInput) -> String {
        let recovery = x.recentRecovery7Day.map(String.init).joined(separator: ", ")
        let sessions = x.recentSessions.joined(separator: " | ")
        let football = x.footballDays.isEmpty ? "none" : x.footballDays.joined(separator: ", ")
        return """
        Week starts: \(x.weekStart)
        Goal: \(x.goal)
        Football days this week: \(football)
        Recovery last 7 days: \(recovery)
        Recent sessions: \(sessions)

        Return JSON:
        {
          "week_start": "\(x.weekStart)",
          "days": [
            {"day": "monday", "workout_type": "push|pull|legs|football|rest", "volume_adjustment": 0.0-1.2}
            // ... 7 days
          ],
          "rationale": "1-2 sentence summary"
        }

        Include all 7 days in order monday→sunday. Match weekly tonnage to recovery trend.
        """
    }
}
