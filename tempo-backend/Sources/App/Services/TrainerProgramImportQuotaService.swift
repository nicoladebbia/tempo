import Fluent
import Foundation
import Vapor

// MARK: - TrainerProgramImportQuotaService

//
// Fix #1 (Pro-only imports) + #2 (rate-limit mid-import), quota half:
// free users get 2 Trainer Program imports per calendar month (UTC);
// Pro/allowlisted users are unlimited. An "import" is one client-generated
// `sessionID` sent on every network call of that import (every transcribe
// batch + the structure call) — the FIRST call of a new session consumes a
// quota slot, every later call with the same session_id is a free
// retry/continuation (so a 429 retry or a multi-batch import never burns
// more than one slot).
//
// Table: `trainer_program_imports` (CreateTrainerProgramImports migration),
// unique on (user_id, session_id).

enum TrainerProgramImportQuotaService {
    /// Free-tier sessions allowed per calendar month.
    static let freeMonthlyLimit = 2

    enum GateResult: Equatable {
        case allowed
        case exceeded(limit: Int, used: Int, resetsAt: Date)
    }

    /// Runs the full gate: entitlement check, session-dedup check, quota
    /// count, and (if this is a new session under the limit) atomically
    /// records the session so it counts against this month's quota.
    static func gate(userID: String, sessionID: String, on req: Request) async throws -> GateResult {
        if try await ProEntitlement.isEntitled(userID: userID, on: req) {
            return .allowed
        }

        // Already-registered session (any month) → free retry/continuation,
        // regardless of the current count.
        if try await TrainerProgramImport.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$sessionID == sessionID)
            .first() != nil
        {
            return .allowed
        }

        let yearMonth = currentYearMonth()
        let used = try await TrainerProgramImport.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$yearMonth == yearMonth)
            .count()

        guard used < freeMonthlyLimit else {
            return .exceeded(limit: freeMonthlyLimit, used: used, resetsAt: nextMonthStartUTC())
        }

        try await recordSession(userID: userID, sessionID: sessionID, yearMonth: yearMonth, on: req)
        return .allowed
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

    // MARK: - Recording (idempotent under races)

    /// Inserts the session row. If a CONCURRENT request for the SAME new
    /// session_id already inserted it (the unique index on
    /// (user_id, session_id) fires), that's treated as success — the
    /// session is registered either way and the slot was only ever meant to
    /// be consumed once. A genuinely different error propagates.
    private static func recordSession(
        userID: String,
        sessionID: String,
        yearMonth: String,
        on req: Request
    ) async throws {
        let row = TrainerProgramImport(userID: userID, sessionID: sessionID, yearMonth: yearMonth)
        do {
            try await row.create(on: req.db)
        } catch {
            if isUniqueConstraintViolation(error) {
                req.logger.info(
                    "[trainer_program_import_quota] concurrent duplicate session insert for user=\(userID) — treating as already-registered"
                )
                return
            }
            throw error
        }
    }

    private static func isUniqueConstraintViolation(_ error: Error) -> Bool {
        if let dbError = error as? any DatabaseError, dbError.isConstraintFailure {
            return true
        }
        // Fallback for drivers/wrappers that don't conform to DatabaseError:
        // Postgres unique_violation is SQLSTATE 23505.
        let description = String(describing: error)
        return description.contains("23505") || description.localizedCaseInsensitiveContains("duplicate key")
    }

    // MARK: - Time helpers

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
