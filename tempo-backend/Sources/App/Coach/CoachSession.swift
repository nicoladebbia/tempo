import Foundation
@preconcurrency import Redis
import Vapor

// MARK: - CoachSession

/// A finished WHOOP workout that is big enough to need a recovery plan (and a weigh-in).
/// The id is TEXT: WHOOP v2 uses UUIDs (v1 used numbers), and this works with both.
/// WHOOP reports energy in kilojoules; `kilocalories` converts with 1 kcal = 4.184 kJ.
struct CoachSession: Content, Equatable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let sportName: String?
    let strain: Double?
    let kilojoules: Double?
    let averageHeartRate: Int?
    let percentRecorded: Double?

    var durationMinutes: Double { max(0, end.timeIntervalSince(start)) / 60 }
    var kilocalories: Double? { kilojoules.map { $0 / 4.184 } }
}

// MARK: - Rules

/// Which workouts get a "weigh yourself" push, and when. The thresholds come from the backtest on
/// A backtest on real WHOOP history: below ~20 min or ~150 kcal a session loses too little to measure with a scale.
enum CoachSessionRules {
    static let minimumMinutes = 20.0
    static let minimumKilocalories = 150.0
    /// Give WHOOP time to finish scoring before we trust the numbers.
    static let settleDelay: TimeInterval = 2 * 60
    /// After this long the moment for a post-session weigh-in has passed (also the 2 h scale window plus margin).
    static let notifyWindowAfterEnd: TimeInterval = 4 * 3600

    /// A SCORED WHOOP v2 record with energy, or nil.
    static func session(from record: WhoopV2WorkoutRecord) -> CoachSession? {
        guard record.scoreState == "SCORED", let score = record.score, score.kilojoule != nil,
              let start = parseWhoopDate(record.start), let end = parseWhoopDate(record.end), end > start
        else { return nil }
        return CoachSession(
            id: record.id, start: start, end: end, sportName: record.sportName, strain: score.strain,
            kilojoules: score.kilojoule, averageHeartRate: score.averageHeartRate, percentRecorded: score.percentRecorded
        )
    }

    static func qualifies(_ session: CoachSession) -> Bool {
        guard let kcal = session.kilocalories else { return false }
        return session.durationMinutes >= minimumMinutes && kcal >= minimumKilocalories
    }

    /// Ended at least `settleDelay` ago and no more than `notifyWindowAfterEnd` ago.
    static func isNotifiable(_ session: CoachSession, now: Date) -> Bool {
        let sinceEnd = now.timeIntervalSince(session.end)
        return sinceEnd >= settleDelay && sinceEnd <= notifyWindowAfterEnd
    }

    /// WHOOP sends "2022-04-24T11:25:44.774Z" (with milliseconds); be tolerant of both forms. Also used to read
    /// timestamps from the app, so the result never depends on the platform's `.iso8601` decoder.
    static func parseWhoopDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    static func whoopTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

extension CoachSession {
    /// The calculator's view of this session, with weather when we have it.
    func trainingSummary(weather: WeatherConditions?) -> TrainingSessionSummary {
        TrainingSessionSummary(
            start: start, end: end, sport: sportName ?? "workout", strain: strain, kilojoules: kilojoules,
            averageHeartRate: averageHeartRate, temperatureC: weather?.temperatureC,
            relativeHumidityPercent: weather?.relativeHumidityPercent, isIndoor: nil
        )
    }
}

// MARK: - Where sessions come from

/// Injectable so tests never call WHOOP. The default asks the WHOOP v2 API through the user's stored token.
protocol CoachWorkoutSource: Sendable {
    func sessions(for userID: String, from: Date, to: Date, on req: Request) async throws -> [CoachSession]
}

/// WHOOP has a request quota shared by the whole app, and three code paths (the push check, the "recent
/// sessions" screen and the recovery call) all want the same recent workout list. So the last 72 hours are fetched at
/// most once per 2 minutes per user and kept in Redis. The key starts with `whoop:<user>:workouts:`, which is exactly
/// what the WHOOP `workout.updated` webhook already clears, so a new workout is never hidden by the cache.
struct WhoopCoachWorkoutSource: CoachWorkoutSource {
    static let windowHours = 72.0
    static let cacheSeconds = 120

    func sessions(for userID: String, from: Date, to: Date, on req: Request) async throws -> [CoachSession] {
        let now = req.now
        let windowStart = now.addingTimeInterval(-Self.windowHours * 3600)
        func overlapping(_ all: [CoachSession]) -> [CoachSession] {
            all.filter { $0.end >= from && $0.start <= to }.sorted { $0.start < $1.start }
        }
        // Older than the cached window: ask WHOOP directly for exactly that range.
        guard from >= windowStart else { return overlapping(try await fetch(userID: userID, from: from, to: max(to, now), on: req)) }

        let key = RedisKey("whoop:\(userID):workouts:coach")
        if let cached = try? await req.application.redis.get(key, as: String.self).get(),
           let data = cached.data(using: .utf8),
           let sessions = try? Self.decoder.decode([CoachSession].self, from: data)
        {
            return overlapping(sessions)
        }
        let fresh = try await fetch(userID: userID, from: windowStart, to: now.addingTimeInterval(3600), on: req)
        if let data = try? Self.encoder.encode(fresh), let text = String(data: data, encoding: .utf8) {
            _ = try? await req.application.redis.setex(key, to: text, expirationInSeconds: Self.cacheSeconds).get()
        }
        return overlapping(fresh)
    }

    private func fetch(userID: String, from: Date, to: Date, on req: Request) async throws -> [CoachSession] {
        let response = try await WhoopAPIService.shared.fetchWorkoutsV2(
            for: userID, start: CoachSessionRules.whoopTimestamp(from), end: CoachSessionRules.whoopTimestamp(to), on: req
        )
        return response.records.compactMap(CoachSessionRules.session(from:))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}

/// The local test server has no real WHOOP: it always has one finished 80-minute match, 10 to 70 minutes old,
/// plus a short walk. Times are pinned to the clock hour so the session does not drift while someone is testing,
/// and the id changes each hour so the "already notified" memory never blocks a new test run.
struct TestModeCoachWorkoutSource: CoachWorkoutSource {
    func sessions(for _: String, from: Date, to: Date, on req: Request) async throws -> [CoachSession] {
        let bucket = (req.now.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        let matchEnd = Date(timeIntervalSince1970: bucket - 600)
        let walkEnd = matchEnd.addingTimeInterval(-4 * 3600)
        let hour = Int64(bucket / 3600)
        let match = CoachSession(id: "test-match-\(hour)", start: matchEnd.addingTimeInterval(-80 * 60), end: matchEnd, sportName: "soccer",
                                 strain: 14.8, kilojoules: 3500, averageHeartRate: 150, percentRecorded: 100)
        let walk = CoachSession(id: "test-walk-\(hour)", start: walkEnd.addingTimeInterval(-15 * 60), end: walkEnd, sportName: "walking",
                                strain: 3.1, kilojoules: 180, averageHeartRate: 90, percentRecorded: 100)
        return [match, walk].filter { $0.end >= from && $0.start <= to }
    }
}

private struct CoachWorkoutSourceKey: StorageKey { typealias Value = any CoachWorkoutSource }

extension Application {
    var coachWorkoutSource: any CoachWorkoutSource {
        get { storage[CoachWorkoutSourceKey.self] ?? (testMode != nil ? TestModeCoachWorkoutSource() : WhoopCoachWorkoutSource()) }
        set { storage[CoachWorkoutSourceKey.self] = newValue }
    }
}
