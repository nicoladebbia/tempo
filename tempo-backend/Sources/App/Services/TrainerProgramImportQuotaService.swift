import Fluent
import Foundation
import Redis
import SQLKit
import Vapor

// MARK: - TrainerProgramImportQuotaService

//
// Fix #1 (Pro-only imports) + #2 (rate-limit mid-import), quota half:
// free users get 2 Trainer Program imports per calendar month (UTC);
// Pro/allowlisted users are unlimited. An "import" is one client-generated
// `sessionID` sent on every network call of that import (every transcribe
// batch + the structure call) — the FIRST call of a new session consumes a
// quota slot; later calls with the same session_id are free retries or
// continuations, but ONLY within the same calendar month and only up to a
// per-kind call cap (so one slot cannot buy unlimited Claude calls).
//
// Table: `trainer_program_imports` (CreateTrainerProgramImports +
// AddCallCountsToTrainerProgramImports), unique on (user_id, session_id).

enum TrainerProgramImportQuotaService {
    /// Free-tier sessions allowed per calendar month.
    static let freeMonthlyLimit = 2
    /// Max structure calls one session may make (1 real call + 2 client
    /// retries + slack).
    static let maxStructureCallsPerSession = 4
    /// Max transcribe batches per session (5 images each -> 100 pages).
    static let maxTranscribeCallsPerSession = 20

    enum CallKind: Equatable {
        case transcribe
        case structure
    }

    enum GateResult: Equatable {
        case allowed
        case exceeded(limit: Int, used: Int, resetsAt: Date)
        /// Session id was registered in an earlier month — no reuse.
        case sessionExpired
        /// This session already made its maximum calls of this kind.
        case sessionCallLimit(limit: Int)
    }

    /// Runs the full gate ATOMICALLY: entitlement check, then — inside one
    /// transaction holding a per-user Postgres advisory lock — the session
    /// lookup, month check, per-session call cap, quota count and insert.
    /// The lock serialises concurrent requests of the same user, so parallel
    /// requests with fresh UUIDs can no longer all pass the count check.
    static func gate(
        userID: String,
        sessionID: String,
        kind: CallKind = .transcribe,
        on req: Request
    ) async throws -> GateResult {
        if try await ProEntitlement.isEntitled(userID: userID, on: req) {
            return .allowed
        }

        let yearMonth = currentYearMonth()
        let lockKey = "trainer_program_import:" + userID
        return try await req.db.transaction { db in
            guard let sql = db as? any SQLDatabase else {
                throw Abort(.internalServerError, reason: "Quota gate requires an SQL database.")
            }
            try await sql.raw("SELECT pg_advisory_xact_lock(hashtext(\(bind: lockKey)))").run()

            if let existing = try await TrainerProgramImport.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$sessionID == sessionID)
                .first()
            {
                guard existing.yearMonth == yearMonth else {
                    return .sessionExpired
                }
                switch kind {
                case .structure:
                    guard existing.structureCalls < maxStructureCallsPerSession else {
                        return .sessionCallLimit(limit: maxStructureCallsPerSession)
                    }
                    existing.structureCalls += 1
                case .transcribe:
                    guard existing.transcribeCalls < maxTranscribeCallsPerSession else {
                        return .sessionCallLimit(limit: maxTranscribeCallsPerSession)
                    }
                    existing.transcribeCalls += 1
                }
                try await existing.update(on: db)
                return .allowed
            }

            let used = try await TrainerProgramImport.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$yearMonth == yearMonth)
                .count()
            guard used < freeMonthlyLimit else {
                return .exceeded(limit: freeMonthlyLimit, used: used, resetsAt: nextMonthStartUTC())
            }

            let row = TrainerProgramImport(userID: userID, sessionID: sessionID, yearMonth: yearMonth)
            switch kind {
            case .structure: row.structureCalls = 1
            case .transcribe: row.transcribeCalls = 1
            }
            try await row.create(on: db)
            return .allowed
        }
    }

    /// Read-only snapshot for `GET /v1/training/program-import/quota`. Does
    /// NOT consume a slot.
    static func snapshot(userID: String, on req: Request) async throws -> QuotaSnapshot {
        let isPro = try await ProEntitlement.isEntitled(userID: userID, on: req)
        let yearMonth = currentYearMonth()
        let used = try await TrainerProgramImport.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$yearMonth == yearMonth)
            .count()

        if isPro {
            return QuotaSnapshot(isPro: true, limit: nil, used: used, remaining: nil, resetsAt: nextMonthStartUTC())
        }
        return QuotaSnapshot(
            isPro: false,
            limit: freeMonthlyLimit,
            used: used,
            remaining: max(0, freeMonthlyLimit - used),
            resetsAt: nextMonthStartUTC()
        )
    }

    struct QuotaSnapshot {
        let isPro: Bool
        let limit: Int?
        let used: Int
        let remaining: Int?
        let resetsAt: Date
    }

    // MARK: - Feedback daily quota

    /// "Trainer sent changes" edits per user per UTC day. Redis INCR is
    /// atomic, so parallel requests cannot overshoot the cap.
    static let freeDailyFeedbackLimit = 5
    static let proDailyFeedbackLimit = 30

    /// Returns nil when allowed, or the daily limit that was hit.
    static func consumeFeedback(userID: String, on req: Request) async throws -> Int? {
        let isEntitled = try await ProEntitlement.isEntitled(userID: userID, on: req)
        let limit = isEntitled ? proDailyFeedbackLimit : freeDailyFeedbackLimit
        let day = currentDay()
        let key = RedisKey("trainer_feedback:\(userID):\(day)")
        let count = try await req.redis.increment(key).get()
        if count == 1 {
            _ = try? await req.redis.expire(key, after: .seconds(48 * 3600)).get()
        }
        return count > limit ? limit : nil
    }

    // MARK: - Time helpers

    static func currentDay(date: Date = .init()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .init(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func currentYearMonth(date: Date = .init()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .init(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func nextMonthStartUTC(date: Date = .init()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .init(secondsFromGMT: 0)!
        let comps = calendar.dateComponents([.year, .month], from: date)
        let startOfThisMonth = calendar.date(from: comps) ?? date
        return calendar.date(byAdding: .month, value: 1, to: startOfThisMonth) ?? startOfThisMonth
    }
}
