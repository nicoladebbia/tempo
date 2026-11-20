@testable import App
import Fluent
import Foundation
import Testing
import Vapor

/// PUT /v1/integrations/whoop/token: the phone owns the WHOOP login and shares only its access token.
/// The server must never refresh such a link (WHOOP refresh tokens are single-use: that would log the phone out).
@Suite("WHOOP phone-shared token", .serialized)
struct WhoopTokenShareTests {
    private func withApp(_ body: (Application) async throws -> Void) async throws {
        setenv("WHOOP_TOKEN_ENCRYPTION_KEY", "test-only-whoop-token-key-0123456789abcdef", 1)
        defer { unsetenv("WHOOP_TOKEN_ENCRYPTION_KEY") }
        let app = try await Application.make(.testing)
        TestMode.force(true, on: app)
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

    private static let deviceID = "whoop-share-device"
    private struct Login { let token: String; let userID: String }

    private func login(_ app: Application, _ name: String) async throws -> Login {
        var out: Login?
        try await app.test(.POST, "v1/test/login", beforeRequest: { req in
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
            req.body = ByteBuffer(string: #"{"name":"\#(name)","fresh":true,"pro":true}"#)
        }, afterResponse: { res async throws in
            let b = try res.content.decode(TestModeController.LoginResponse.self)
            out = Login(token: b.accessToken, userID: b.userId)
        })
        return try #require(out)
    }

    private func share(_ app: Application, _ login: Login, token: String, expiresAt: Date) async throws -> (HTTPStatus, String) {
        var status = HTTPStatus.ok
        var text = ""
        let iso = ISO8601DateFormatter().string(from: expiresAt)
        try await app.test(.PUT, "v1/integrations/whoop/token", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: login.token)
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
            req.headers.contentType = .json
            req.body = ByteBuffer(string: #"{"access_token":"\#(token)","expires_at":"\#(iso)"}"#)
        }, afterResponse: { res async throws in
            status = res.status
            text = res.body.string
        })
        return (status, text)
    }

    private func rows(_ app: Application, _ userID: String) async throws -> [WhoopIntegration] {
        try await WhoopIntegration.query(on: app.db).filter(\.$user.$id == userID).all()
    }

    @Test func sharingCreatesOnePhoneManagedLinkAndUpdatesItInPlace() async throws {
        try await withApp { app in
            let me = try await login(app, "whoop-share")
            let (s1, b1) = try await share(app, me, token: "phone-access-1", expiresAt: Date().addingTimeInterval(3600))
            #expect(s1 == .ok)
            #expect(b1.contains(#""managed_by":"phone""#))

            let (s2, _) = try await share(app, me, token: "phone-access-2", expiresAt: Date().addingTimeInterval(3500))
            #expect(s2 == .ok)
            let all = try await rows(app, me.userID)
            #expect(all.count == 1, "one link per user")
            let link = try #require(all.first)
            #expect(link.isPhoneManaged)
            #expect(try link.accessToken() == "phone-access-2")
            #expect(try link.refreshToken().isEmpty, "the server never holds the phone's refresh token")
        }
    }

    @Test func aServerOwnedLinkIsLeftAlone() async throws {
        try await withApp { app in
            let me = try await login(app, "whoop-server")
            let own = try WhoopIntegration(
                userID: me.userID,
                encryptedAccessToken: EncryptionService.encrypt("server-access"),
                encryptedRefreshToken: EncryptionService.encrypt("server-refresh"),
                tokenExpiresAt: Date().addingTimeInterval(3600)
            )
            try await own.save(on: app.db)

            let (status, body) = try await share(app, me, token: "phone-access", expiresAt: Date().addingTimeInterval(3600))
            #expect(status == .ok)
            #expect(body.contains(#""managed_by":"server""#))
            let link = try #require(try await rows(app, me.userID).first)
            #expect(try link.accessToken() == "server-access")
            #expect(try link.refreshToken() == "server-refresh")
        }
    }

    @Test func rejectsEmptyOrExpiredTokens() async throws {
        try await withApp { app in
            let me = try await login(app, "whoop-bad")
            #expect(try await share(app, me, token: "  ", expiresAt: Date().addingTimeInterval(3600)).0 == .badRequest)
            #expect(try await share(app, me, token: "x", expiresAt: Date().addingTimeInterval(-60)).0 == .unprocessableEntity)
            #expect(try await rows(app, me.userID).isEmpty)
        }
    }

    @Test func anExpiredPhoneLinkIsNeverRefreshedByTheServer() async throws {
        try await withApp { app in
            let me = try await login(app, "whoop-expired")
            _ = try await share(app, me, token: "phone-access", expiresAt: Date().addingTimeInterval(120))
            let link = try #require(try await rows(app, me.userID).first)
            link.tokenExpiresAt = Date().addingTimeInterval(-60)
            try await link.save(on: app.db)
            #expect(link.isExpiredPhoneLink)

            let req = Request(application: app, on: app.eventLoopGroup.next())
            do {
                _ = try await WhoopAPIService.shared.validAccessToken(for: me.userID, on: req)
                Issue.record("expected the expired phone link to fail without a refresh")
            } catch let abort as Abort {
                #expect(abort.identifier == "3008")
            }
            let after = try #require(try await rows(app, me.userID).first)
            #expect(after.lastSyncStatus != "token_revoked", "an expired phone link is not a revoked one")

            // The workout sweep skips it instead of failing every 10 minutes.
            #expect(try await CoachWorkoutWatchJob().sweep(app: app, now: Date(), userID: me.userID) == 0)
        }
    }
}
