@testable import App
import Fluent
import Foundation
import Testing
import Vapor

// MARK: - TrainerProgramImportQuotaService tests

//
// Exercises the quota gate against a REAL Postgres + Redis (same
// docker-compose services every other integration point uses; connects via
// the same DB_HOST/DB_PORT/... env-var defaults `configure(_:)` falls back
// to when DATABASE_URL/REDIS_URL aren't set). Each test creates its own
// fresh User row so counts never collide across runs.
//
// `.serialized`: these tests mutate the process-wide PRO_ALLOWLIST env var
// and each spins up its own `Application` + `autoMigrate()` against the same
// physical database — running them one at a time avoids both an env-var
// race and a migration race between concurrently-booting `Application`s.

@Suite("TrainerProgramImportQuotaService", .serialized)
struct TrainerProgramImportQuotaServiceTests {
    // MARK: - Harness

    private func withApp(_ body: (Application, Request) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            // Redis/queues pools are wired up during the app lifecycle boot
            // (not by configure() alone) — without this, `req.redis` fatal
            // errors with "No redis found for id default".
            try await app.asyncBoot()
            let req = Request(application: app, on: app.eventLoopGroup.next())
            try await body(app, req)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func makeFreeUser(on db: any Database) async throws -> User {
        let user = User(appleUserID: "apple_\(UUID().uuidString)", username: "user_\(UUID().uuidString.prefix(12))")
        try await user.create(on: db)
        return user
    }

    private func makeProUser(on db: any Database) async throws -> User {
        let user = try await makeFreeUser(on: db)
        let sub = UserSubscription(
            userID: user.id!,
            productId: "tempo_pro_annual",
            originalTransactionId: "txn_\(UUID().uuidString)",
            purchaseDate: Date().addingTimeInterval(-86400),
            expirationDate: Date().addingTimeInterval(86400 * 30)
        )
        try await sub.create(on: db)
        return user
    }

    // MARK: - Same session not double-counted

    @Test func sameSessionIsFreeOnRepeatedCalls() async throws {
        try await withApp { _, req in
            let user = try await makeFreeUser(on: req.db)
            let sessionID = UUID().uuidString

            let first = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: sessionID, on: req)
            let second = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: sessionID, on: req)
            let third = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: sessionID, on: req)

            #expect(first == .allowed)
            #expect(second == .allowed)
            #expect(third == .allowed)

            let snapshot = try await TrainerProgramImportQuotaService.snapshot(userID: user.id!, on: req)
            #expect(snapshot.used == 1, "3 calls with the SAME session_id must consume exactly 1 quota slot")
        }
    }

    // MARK: - Free monthly limit enforced across distinct sessions

    @Test func freeUserIsBlockedAfterTwoDistinctSessions() async throws {
        try await withApp { _, req in
            let user = try await makeFreeUser(on: req.db)

            let first = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: UUID().uuidString, on: req)
            let second = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: UUID().uuidString, on: req)
            #expect(first == .allowed)
            #expect(second == .allowed)

            let thirdSessionID = UUID().uuidString
            let third = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: thirdSessionID, on: req)
            guard case let .exceeded(limit, used, resetsAt) = third else {
                Issue.record("expected .exceeded, got \(third)")
                return
            }
            #expect(limit == 2)
            #expect(used == 2)
            #expect(resetsAt > Date())

            // A retry of the SAME (already-blocked) new session_id must still
            // report exceeded, not silently register it.
            let retry = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: thirdSessionID, on: req)
            #expect(retry == third)

            let snapshot = try await TrainerProgramImportQuotaService.snapshot(userID: user.id!, on: req)
            #expect(snapshot.isPro == false)
            #expect(snapshot.limit == 2)
            #expect(snapshot.used == 2)
            #expect(snapshot.remaining == 0)
        }
    }

    // MARK: - Month rollover

    @Test func onlyCurrentCalendarMonthCountsTowardTheLimit() async throws {
        try await withApp { _, req in
            let user = try await makeFreeUser(on: req.db)

            // Two sessions "used" in a previous month — must not count against
            // this month's quota.
            try await TrainerProgramImport(userID: user.id!, sessionID: UUID().uuidString, yearMonth: "2020-01").create(on: req.db)
            try await TrainerProgramImport(userID: user.id!, sessionID: UUID().uuidString, yearMonth: "2020-02").create(on: req.db)

            let snapshotBeforeThisMonth = try await TrainerProgramImportQuotaService.snapshot(userID: user.id!, on: req)
            #expect(snapshotBeforeThisMonth.used == 0, "old-month rows must not count toward the current month's used total")

            // Now this month's own two slots should still both be available.
            let first = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: UUID().uuidString, on: req)
            let second = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: UUID().uuidString, on: req)
            #expect(first == .allowed)
            #expect(second == .allowed)

            let third = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: UUID().uuidString, on: req)
            guard case .exceeded = third else {
                Issue.record("expected .exceeded once this month's own 2 slots are used, got \(third)")
                return
            }
        }
    }

    // MARK: - Pro unlimited

    @Test func proUserIsNeverBlocked() async throws {
        try await withApp { _, req in
            let user = try await makeProUser(on: req.db)

            for _ in 0 ..< 5 {
                let result = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: UUID().uuidString, on: req)
                #expect(result == .allowed)
            }

            let snapshot = try await TrainerProgramImportQuotaService.snapshot(userID: user.id!, on: req)
            #expect(snapshot.isPro == true)
            #expect(snapshot.limit == nil)
            #expect(snapshot.remaining == nil)
        }
    }

    // MARK: - Allowlist bypass

    @Test func allowlistedFreeUserIsUnlimited() async throws {
        try await withApp { _, req in
            let user = try await makeFreeUser(on: req.db)
            setenv("PRO_ALLOWLIST", user.id!, 1)
            defer { unsetenv("PRO_ALLOWLIST") }

            for _ in 0 ..< 4 {
                let result = try await TrainerProgramImportQuotaService.gate(userID: user.id!, sessionID: UUID().uuidString, on: req)
                #expect(result == .allowed)
            }

            let snapshot = try await TrainerProgramImportQuotaService.snapshot(userID: user.id!, on: req)
            #expect(snapshot.isPro == true, "an allowlisted user should read back as Pro/unlimited from the quota snapshot")
        }
    }
}
