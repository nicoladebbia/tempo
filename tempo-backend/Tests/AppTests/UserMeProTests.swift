@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - GET /v1/user/me → is_pro

//
// The app's Subscription page shows `is_pro` as the user's plan. It has to
// answer the way the Pro gates do (SubscriptionMiddleware): an active
// subscription OR the PRO_ALLOWLIST operator list. It used to look at the
// subscription row only, so an allowlisted account read as Free in the app
// while every gate let it through.
//
// `.serialized`: the allowlist test sets the process-wide PRO_ALLOWLIST variable.

@Suite("User me is_pro", .serialized)
struct UserMeProTests {
    private static let deviceID = "me-pro-device"

    private func withApp(_ body: (Application) async throws -> Void) async throws {
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

    private struct Login {
        let token: String
        let userID: String
    }

    private func login(_ app: Application, pro: Bool) async throws -> Login {
        let name = "me-pro-\(UUID().uuidString.prefix(8).lowercased())"
        var out: Login?
        try await app.test(.POST, "v1/test/login", beforeRequest: { req in
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
            req.body = ByteBuffer(string: #"{"name":"\#(name)","fresh":true,"pro":\#(pro)}"#)
        }, afterResponse: { res async throws in
            let body = try res.content.decode(TestModeController.LoginResponse.self)
            out = Login(token: body.accessToken, userID: body.userId)
        })
        return try #require(out)
    }

    private struct Me {
        let isPro: Bool
        let productId: String?
    }

    private func me(_ app: Application, _ login: Login) async throws -> Me {
        var result: Me?
        try await app.test(.GET, "v1/user/me", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: login.token)
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
        }, afterResponse: { res async throws in
            guard res.status == .ok else {
                throw Abort(res.status)
            }
            let json = try JSONSerialization.jsonObject(with: Data(res.body.readableBytesView)) as? [String: Any]
            let data = try #require(json?["data"] as? [String: Any])
            result = Me(isPro: data["is_pro"] as? Bool ?? false, productId: data["product_id"] as? String)
        })
        return try #require(result)
    }

    @Test func subscriberIsPro() async throws {
        try await withApp { app in
            let user = try await login(app, pro: true)
            let me = try await me(app, user)
            #expect(me.isPro == true)
            #expect(me.productId != nil)
        }
    }

    @Test func freeUserIsNotPro() async throws {
        try await withApp { app in
            let user = try await login(app, pro: false)
            let me = try await me(app, user)
            #expect(me.isPro == false)
            #expect(me.productId == nil)
        }
    }

    @Test func allowlistedUserIsProWithoutASubscription() async throws {
        try await withApp { app in
            let user = try await login(app, pro: false)
            setenv("PRO_ALLOWLIST", user.userID, 1)
            defer { unsetenv("PRO_ALLOWLIST") }

            let me = try await me(app, user)
            #expect(me.isPro == true, "an allowlisted account passes every Pro gate, so the app must read it as Pro")
            #expect(me.productId == nil, "no purchase is behind allowlisted access")
        }
    }
}
