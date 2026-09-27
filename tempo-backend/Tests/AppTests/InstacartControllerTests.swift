@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - InstacartController tests

//
// Uses the `configure(app:instacartClient:)` seam to inject FakeInstacartClient
// instead of hitting the real Instacart API. Covers: not-configured error
// when INSTACART_API_KEY is unset, successful request mapping through the
// stub, and validation.

@Suite("InstacartController", .serialized)
struct InstacartControllerTests {
    private func withApp(instacartClient: InstacartClient, _ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, instacartClient: instacartClient)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @discardableResult
    private func makeUser(app: Application) async throws -> (user: User, token: String) {
        let suffix = UUID().uuidString.prefix(12)
        let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "Test User")
        user.tosAcceptedAt = Date()
        try await user.save(on: app.db)
        let req = Request(application: app, on: app.eventLoopGroup.next())
        let token = try await JWTService.issueAccessToken(userID: user.requireID(), deviceID: "test-device", on: req)
        return (user, token)
    }

    private func cartBody(items: [[String: Any]]) -> ByteBuffer {
        let payload: [String: Any] = ["title": "Tempo Grocery List", "items": items]
        return ByteBuffer(data: try! JSONSerialization.data(withJSONObject: payload))
    }

    @Test func returnsNotConfiguredWhenKeyIsMissing() async throws {
        let previous = Environment.get("INSTACART_API_KEY")
        setenv("INSTACART_API_KEY", "", 1)
        defer {
            if let previous {
                setenv("INSTACART_API_KEY", previous, 1)
            } else {
                unsetenv("INSTACART_API_KEY")
            }
        }

        try await withApp(instacartClient: FakeInstacartClient(response: .success("https://example.com/should-not-be-called"))) { app in
            let (_, authToken) = try await makeUser(app: app)
            try await app.test(.POST, "v1/grocery/instacart-cart", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = cartBody(items: [["name": "Black Beans", "quantity": 2, "unit": "cans"]])
            }, afterResponse: { res async throws in
                #expect(res.status == .preconditionFailed)
                let body = try res.content.decode(TestErrorBody.self)
                #expect(body.code == "instacart_not_configured")
            })
        }
    }

    @Test func returnsURLAndMapsItemsWhenConfigured() async throws {
        setenv("INSTACART_API_KEY", "test-key-123", 1)
        defer { unsetenv("INSTACART_API_KEY") }

        let fake = FakeInstacartClient(response: .success("https://www.instacart.com/store/abc123"))
        try await withApp(instacartClient: fake) { app in
            let (_, authToken) = try await makeUser(app: app)
            try await app.test(.POST, "v1/grocery/instacart-cart", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = cartBody(items: [
                    ["name": "Black Beans", "quantity": 2, "unit": "cans"],
                    ["name": "Milk"],
                ])
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<CartWire>.self)
                #expect(json.data.url == "https://www.instacart.com/store/abc123")
            })
        }
        #expect(fake.lastAPIKey == "test-key-123")
        #expect(fake.lastItems?.count == 2)
        #expect(fake.lastItems?.first?.name == "Black Beans")
        #expect(fake.lastItems?.first?.quantity == 2)
        #expect(fake.lastItems?.last?.quantity == nil)
    }

    @Test func upstreamFailureBecomesBadGateway() async throws {
        setenv("INSTACART_API_KEY", "test-key-123", 1)
        defer { unsetenv("INSTACART_API_KEY") }

        try await withApp(instacartClient: FakeInstacartClient(response: .failure(InstacartClientError.upstreamError(500)))) { app in
            let (_, authToken) = try await makeUser(app: app)
            try await app.test(.POST, "v1/grocery/instacart-cart", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = cartBody(items: [["name": "Milk"]])
            }, afterResponse: { res async throws in
                #expect(res.status == .badGateway)
            })
        }
    }

    @Test func emptyItemsIsBadRequest() async throws {
        setenv("INSTACART_API_KEY", "test-key-123", 1)
        defer { unsetenv("INSTACART_API_KEY") }

        try await withApp(instacartClient: FakeInstacartClient(response: .success("https://example.com"))) { app in
            let (_, authToken) = try await makeUser(app: app)
            try await app.test(.POST, "v1/grocery/instacart-cart", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = cartBody(items: [])
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })
        }
    }
}

// MARK: - Wire types

private struct RawEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
}

private struct CartWire: Decodable {
    let url: String
}

/// Mirrors TempoErrorMiddleware's flat wire shape:
/// `{ "error": true, "reason": "...", "code": "<identifier>" }`.
private struct TestErrorBody: Decodable {
    let error: Bool
    let reason: String
    let code: String?
}
