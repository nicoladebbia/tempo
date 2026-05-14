import Foundation
import Vapor

// MARK: - StudyScheduleService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.7 + INTELLIGENCE_REMEDIATION_PLAN.md §7.8.
//
// Builds a per-exam study schedule. Sonnet. Cached in Postgres until the
// exam date changes or topic progress is updated (invalidation handled by
// the exam edit endpoint when §8/§9 land).

struct StudyScheduleService {
    static let shared = StudyScheduleService()
    private init() {}

    func generate(
        input: StudyScheduleInput,
        on req: Request,
        bypassCache: Bool = false
    ) async throws -> StudyScheduleResponse {
        let spec = AIFeatureSpec<StudyScheduleResponse>(
            model: AIConfig.sonnetModel,
            maxTokens: 1_500,
            temperature: 0.3,
            timeout: AIConfig.sonnetTimeout,
            estimatedInputTokens: 2_500,
            cacheKey: .studySchedule(userId: input.userId ?? "", examId: input.examId)
        )
        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            bypassCache: bypassCache,
            buildPrompts: { (StudySchedulePrompts.system, StudySchedulePrompts.buildUserPrompt(from: input)) },
            parse: { raw in try Self.parseJSON(raw) },
            fallback: { Self.fallback(input: input) }
        )
        return value
    }

    private static func parseJSON(_ raw: String) throws -> StudyScheduleResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            s = String(raw[start ... end])
        } else {
            s = raw
        }
        guard let data = s.data(using: .utf8) else { throw InsightError.malformedResponse }
        return try decoder.decode(StudyScheduleResponse.self, from: data)
    }

    static func fallback(input: StudyScheduleInput) -> StudyScheduleResponse {
        // Even-split topics over remaining days.
        let days = max(1, input.daysUntilExam)
        let per = max(1, input.topics.count / days)
        var sessions: [StudySession] = []
        for (i, topic) in input.topics.enumerated() {
            let day = min(days, (i / per) + 1)
            sessions.append(StudySession(dayOffset: day, topic: topic, minutes: 60))
        }
        return StudyScheduleResponse(
            examId: input.examId,
            sessions: sessions,
            rationale: "Rule-based even split."
        )
    }
}

struct StudyScheduleInput: Content {
    var userId: String? = nil
    let examId: String
    let examName: String
    let daysUntilExam: Int
    let topics: [String]
    let topicProgress: [String: Int]   // topic -> % complete
    let dailyAvailabilityMinutes: Int


    func withUserID(_ id: String) -> StudyScheduleInput {
        var copy = self
        copy.userId = id
        return copy
    }
}

struct StudySession: Content {
    let dayOffset: Int       // 1 = tomorrow
    let topic: String
    let minutes: Int
}

struct StudyScheduleResponse: Content {
    let examId: String
    let sessions: [StudySession]
    let rationale: String
}

enum StudySchedulePrompts {
    static let system = """
    You build study schedules for university students. Distribute topics across the days remaining before the exam, weighted by current progress. Hardest/least-progressed topics get earlier and more time. Output ONLY valid JSON.
    """

    static func buildUserPrompt(from x: StudyScheduleInput) -> String {
        let topicLines = x.topics.map { t in
            let pct = x.topicProgress[t] ?? 0
            return "- \(t) (\(pct)% complete)"
        }.joined(separator: "\n")
        return """
        Exam: \(x.examName)
        Days until exam: \(x.daysUntilExam)
        Daily availability: \(x.dailyAvailabilityMinutes) minutes
        Topics:
        \(topicLines)

        Return JSON:
        {
          "exam_id": "\(x.examId)",
          "sessions": [
            {"day_offset": 1, "topic": "string", "minutes": number}
          ],
          "rationale": "1-2 sentence summary"
        }

        Spread sessions across all remaining days. Don't exceed daily availability per day.
        """
    }
}
