@testable import App
import Fluent
import Foundation
import Testing
import Vapor

// MARK: - Refresh-token rotation reuse detection
//
// verifyRefreshToken used to filter `revokedAt == nil`, so a replayed (already
// rotated) token looked unknown and the "revoke all sessions" branch in
// AuthController.refreshToken was dead code. Calls the controller directly (not
// over HTTP) so the per-IP auth rate limiter can't make this flaky.

@Suite("Refresh token replay", .serialized)
struct RefreshTokenReplayTests {
    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func refreshRequest(_ app: Application, token: String, device: String = "dev-1") throws -> Request {
        let req = Request(application: app, method: .POST, url: "/v1/auth/refresh", on: app.eventLoopGroup.next())
        req.headers.replaceOrAdd(name: "X-Device-Id", value: device)
        try req.content.encode(["refreshToken": token], as: .json)
        return req
    }

    private func activeSessions(_ app: Application, userID: String) async throws -> Int {
        try await RefreshToken.query(on: app.db)
            .filter(\.$user.$id == userID)
            .filter(\.$revokedAt == nil)
            .count()
    }

    private func backdateRevocation(_ app: Application, userID: String) async throws {
        let revoked = try await RefreshToken.query(on: app.db)
            .filter(\.$user.$id == userID)
            .filter(\.$revokedAt != nil)
            .all()
        for token in revoked {
            token.revokedAt = Date().addingTimeInterval(-(AuthController.replayGraceSeconds + 5))
            try await token.save(on: app.db)
        }
    }

    private func makeUser(_ app: Application) async throws -> String {
        let suffix = UUID().uuidString.prefix(12)
        let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "T")
        try await user.save(on: app.db)
        return try user.requireID()
    }

    @Test func replayedTokenRevokesEverySession() async throws {
        try await withApp { app in
            let uid = try await makeUser(app)
            let issueReq = Request(application: app, on: app.eventLoopGroup.next())
            let first = try await JWTService.issueTokenPair(userID: uid, deviceID: "dev-1", on: issueReq)
            _ = try await JWTService.issueTokenPair(userID: uid, deviceID: "dev-2", on: issueReq) // another device

            // Legit rotation.
            let rotated = try await AuthController().refreshToken(refreshRequest(app, token: first.refreshToken))
            #expect(try await activeSessions(app, userID: uid) == 2) // dev-2 + the rotated dev-1 token

            // Replay right after rotation (lost response): plain 401, nothing else dies.
            do {
                _ = try await AuthController().refreshToken(refreshRequest(app, token: first.refreshToken))
                Issue.record("expected 401")
            } catch let abort as Abort {
                #expect(abort.status == .unauthorized)
                #expect(!abort.reason.contains("Replay"))
            }
            #expect(try await activeSessions(app, userID: uid) == 2)

            // Past the grace window it's a leak.
            try await backdateRevocation(app, userID: uid)

            // Attacker replays the old token: 401 AND every session dies.
            await #expect(throws: Abort.self) {
                _ = try await AuthController().refreshToken(refreshRequest(app, token: first.refreshToken))
            }
            #expect(try await activeSessions(app, userID: uid) == 0)

            // The rotated token is dead too.
            await #expect(throws: Abort.self) {
                _ = try await AuthController().refreshToken(refreshRequest(app, token: rotated.refreshToken))
            }
        }
    }

    @Test func unknownTokenIsPlain401AndTouchesNothing() async throws {
        try await withApp { app in
            let uid = try await makeUser(app)
            let issueReq = Request(application: app, on: app.eventLoopGroup.next())
            _ = try await JWTService.issueTokenPair(userID: uid, deviceID: "dev-1", on: issueReq)

            do {
                _ = try await AuthController().refreshToken(refreshRequest(app, token: "not-a-real-token"))
                Issue.record("expected 401")
            } catch let abort as Abort {
                #expect(abort.status == .unauthorized)
                #expect(!abort.reason.contains("Replay"))
            }
            #expect(try await activeSessions(app, userID: uid) == 1)
        }
    }
}
