import Foundation
import Vapor

// MARK: - DrillSergeantBatchService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.4 + INTELLIGENCE_REMEDIATION_PLAN.md §7.4.
//
// Generates a 3-day batch of notification copies in one Sonnet call. Runs
// twice a week (Sun 20:00 for Mon-Wed, Wed 20:00 for Thu-Sat). Cached in
// Redis for 3 days per (user, batch_start_date).
//
// The single-shot `/v1/insights/drill-sergeant` route stays for ad-hoc copy
// generation (e.g. iOS-side rendering of a specific tier in real time).
// Notifications scheduled by the existing escalation engine read from this
// cache to avoid live Claude calls on every push.

struct DrillSergeantBatchService {
    static let shared = DrillSergeantBatchService()
    private init() {}

    func generate(
        input: DrillSergeantBatchInput,
        on req: Request,
        bypassCache: Bool = false
    ) async throws -> DrillSergeantBatchResponse {
        let spec = AIFeatureSpec<DrillSergeantBatchResponse>(
            model: AIConfig.sonnetModel,
            maxTokens: 2_000,
            temperature: 0.8,
            timeout: AIConfig.sonnetTimeout,
            estimatedInputTokens: 2_000,
            cacheKey: .notificationBatch(userId: input.userId ?? "", batchStart: input.batchStart)
        )
        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            bypassCache: bypassCache,
            buildPrompts: { (DrillSergeantBatchPrompts.system, DrillSergeantBatchPrompts.buildUserPrompt(from: input)) },
            parse: { raw in try Self.parseJSON(raw) },
            fallback: { Self.fallback(input: input) }
        )
        return value
    }

    private static func parseJSON(_ raw: String) throws -> DrillSergeantBatchResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            s = String(raw[start ... end])
        } else {
            s = raw
        }
        guard let data = s.data(using: .utf8) else { throw InsightError.malformedResponse }
        return try decoder.decode(DrillSergeantBatchResponse.self, from: data)
    }

    static func fallback(input: DrillSergeantBatchInput) -> DrillSergeantBatchResponse {
        // Static templates per channel — same shape as a Claude batch but
        // less varied. Acceptable when budget exhausted or circuit open.
        let channels = ["morning", "afternoon", "evening", "bedtime", "celebration", "weekly_summary"]
        var days: [DrillSergeantBatchDay] = []
        for offset in 0 ..< 3 {
            var entries: [String: String] = [:]
            for channel in channels {
                entries[channel] = "[\(channel)] No excuses today."
            }
            days.append(DrillSergeantBatchDay(dayOffset: offset, copy: entries))
        }
        return DrillSergeantBatchResponse(batchStart: input.batchStart, days: days)
    }
}

struct DrillSergeantBatchInput: Content {
    let userId: String
    let batchStart: String              // "yyyy-MM-dd" of first day in batch
    let userFirstName: String?          // optional, requires consent per §4.4
    let recoveryTrend7day: [Int]
    let upcomingEvents: [String]        // [{"date":"YYYY-MM-DD","label":"Anatomy exam"}]
    let recentStreakDays: Int

    func withUserID(_ id: String) -> DrillSergeantBatchInput {
        DrillSergeantBatchInput(
            userId: id, batchStart: batchStart, userFirstName: userFirstName,
            recoveryTrend7day: recoveryTrend7day,
            upcomingEvents: upcomingEvents, recentStreakDays: recentStreakDays
        )
    }
}

struct DrillSergeantBatchDay: Content {
    let dayOffset: Int                  // 0 = batchStart, 1 = next day, 2 = day after
    let copy: [String: String]          // channel -> copy
}

struct DrillSergeantBatchResponse: Content {
    let batchStart: String
    let days: [DrillSergeantBatchDay]
}

enum DrillSergeantBatchPrompts {
    static let system = """
    You generate batch notification copy for a fitness/accountability app. For each of 3 days, produce one short message per channel (morning, afternoon, evening, bedtime, celebration, weekly_summary). Drill-sergeant tone — direct, specific, no fluff. Reference exact numbers when possible. Output ONLY valid JSON.
    """

    static func buildUserPrompt(from x: DrillSergeantBatchInput) -> String {
        let events = x.upcomingEvents.isEmpty ? "none" : x.upcomingEvents.joined(separator: ", ")
        let recovery = x.recoveryTrend7day.map(String.init).joined(separator: ", ")
        let name = x.userFirstName ?? "Athlete"
        return """
        Athlete: \(name)
        Batch starts: \(x.batchStart) (next 3 days)
        Streak: \(x.recentStreakDays) days
        Recovery last 7 days: \(recovery)
        Upcoming events: \(events)

        Return JSON with copy for 3 days × 6 channels each:
        {
          "batch_start": "\(x.batchStart)",
          "days": [
            {
              "day_offset": 0,
              "copy": {
                "morning": "...",
                "afternoon": "...",
                "evening": "...",
                "bedtime": "...",
                "celebration": "...",
                "weekly_summary": "..."
              }
            }
            // ... 3 days total
          ]
        }

        Each message: 1-2 sentences max. Vary the rhythm across days. No emojis.
        """
    }
}
