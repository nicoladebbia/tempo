@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - GroceryShareController + PublicGroceryShareController tests

//
// Real Postgres + Redis harness (same pattern as WeeklyPlanControllerTests).
// Covers: owner create/replace, token lookup, per-item LWW merge, expired/
// revoked -> 410, HTML escaping on the public page, and IP rate limiting on
// the public routes.

@Suite("GroceryShareController", .serialized)
struct GroceryShareControllerTests {
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

    private func item(
        id: String = UUID().uuidString,
        name: String = "Black Beans",
        quantity: Double = 2,
        unit: String = "cans",
        category: String = "pantry",
        checked: Bool = false,
        updatedAt: Date = Date()
    ) -> [String: Any] {
        [
            "id": id, "name": name, "quantity": quantity, "unit": unit,
            "category": category, "checked": checked,
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
        ]
    }

    private func upsertBody(token: String? = nil, title: String = "Grocery List", items: [[String: Any]]) -> ByteBuffer {
        var payload: [String: Any] = ["title": title, "items": items]
        if let token {
            payload["token"] = token
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return ByteBuffer(data: data)
    }

    // MARK: - Create / replace

    @Test func createReturnsTokenAndURL() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(name: "Black Beans")])
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<ShareWire>.self)
                #expect(json.ok == true)
                #expect(!json.data.token.isEmpty)
                #expect(json.data.url.contains(json.data.token))
                #expect(json.data.items.count == 1)
                #expect(json.data.items[0].name == "Black Beans")
                #expect(json.data.revoked == false)
            })
        }
    }

    @Test func replaceWithSameTokenUpdatesCatalogFields() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            let itemID = UUID().uuidString
            var token = ""

            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(id: itemID, name: "Milk", quantity: 1)])
            }, afterResponse: { res async throws in
                let json = try res.content.decode(RawEnvelope<ShareWire>.self)
                token = json.data.token
            })

            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(token: token, items: [item(id: itemID, name: "Oat Milk", quantity: 2)])
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<ShareWire>.self)
                #expect(json.data.token == token, "replacing must reuse the same link/token")
                #expect(json.data.items[0].name == "Oat Milk")
                #expect(json.data.items[0].quantity == 2)
            })

            let count = try await SharedGroceryList.query(on: app.db).filter(\.$token == token).count()
            #expect(count == 1, "replace must not create a second row")
        }
    }

    @Test func replaceWithUnknownTokenIsNotFound() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(token: "not-a-real-token", items: [item()])
            }, afterResponse: { res async throws in
                #expect(res.status == .notFound)
            })
        }
    }

    @Test func anotherUsersTokenIsNotFound() async throws {
        try await withApp { app in
            let (_, tokenA) = try await makeUser(app: app)
            let (_, tokenB) = try await makeUser(app: app)
            var shareToken = ""

            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: tokenA)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item()])
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
            })

            try await app.test(.GET, "v1/grocery/shared/\(shareToken)", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: tokenB)
            }, afterResponse: { res async throws in
                #expect(res.status == .notFound)
            })
        }
    }

    // MARK: - Get state (owner)

    @Test func getStateReturnsCurrentItems() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            var shareToken = ""
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(name: "Eggs")])
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
            })

            try await app.test(.GET, "v1/grocery/shared/\(shareToken)", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<ShareWire>.self)
                #expect(json.data.items[0].name == "Eggs")
            })
        }
    }

    // MARK: - Revoke

    @Test func revokeMakesPublicPage410() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            var shareToken = ""
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item()])
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
            })

            try await app.test(.POST, "v1/grocery/shared/\(shareToken)/revoke", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
            })

            try await app.test(.GET, "g/\(shareToken)", afterResponse: { res async throws in
                #expect(res.status == .gone)
                let body = res.body.string
                #expect(body.contains("no longer available"))
            })

            try await app.test(.GET, "g/\(shareToken)/state", afterResponse: { res async throws in
                #expect(res.status == .gone)
            })
        }
    }

    @Test func expiredShareIsGoneOnPublicRoutes() async throws {
        try await withApp { app in
            let (user, _) = try await makeUser(app: app)
            let expired = try SharedGroceryList(
                userID: user.requireID(),
                token: String.randomHex(length: 20),
                title: "Old List",
                itemsJSON: SharedGroceryList.encodeItems([]),
                expiresAt: Date().addingTimeInterval(-3600)
            )
            try await expired.save(on: app.db)

            try await app.test(.GET, "g/\(expired.token)", afterResponse: { res async throws in
                #expect(res.status == .gone)
            })
            try await app.test(.GET, "g/\(expired.token)/state", afterResponse: { res async throws in
                #expect(res.status == .gone)
            })
            try await app.test(.POST, "g/\(expired.token)/items/whatever", afterResponse: { res async throws in
                #expect(res.status == .gone)
            })
        }
    }

    @Test func unknownTokenPublicPageIsGone() async throws {
        try await withApp { app in
            try await app.test(.GET, "g/does-not-exist", afterResponse: { res async throws in
                #expect(res.status == .gone)
            })
        }
    }

    /// An unknown token must be indistinguishable from a revoked/expired one
    /// on EVERY public route, not just the page — otherwise `/state` and
    /// `/items/:id` become an oracle (404 = never existed, 410 = existed
    /// once) that `page()` already hides. Regression test for a review
    /// finding: `requireLiveShare` previously threw `.notFound` for an
    /// unknown token but `.gone` for expired/revoked.
    @Test func unknownTokenIsGoneNotNotFoundOnStateAndToggleRoutes() async throws {
        try await withApp { app in
            try await app.test(.GET, "g/does-not-exist/state", afterResponse: { res async throws in
                #expect(res.status == .gone)
            })
            try await app.test(.POST, "g/does-not-exist/items/whatever", afterResponse: { res async throws in
                #expect(res.status == .gone)
            })
        }
    }

    // MARK: - Public toggle + last-write-wins merge

    @Test func publicToggleSetsCheckedAndServerTimestamp() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            let itemID = UUID().uuidString
            var shareToken = ""
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(id: itemID, checked: false)])
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
            })

            try await app.test(.POST, "g/\(shareToken)/items/\(itemID)", beforeRequest: { req in
                req.headers.contentType = .json
                req.body = ByteBuffer(data: try! JSONSerialization.data(withJSONObject: ["checked": true]))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<ItemWire>.self)
                #expect(json.data.checked == true)
            })

            try await app.test(.GET, "g/\(shareToken)/state", afterResponse: { res async throws in
                let json = try res.content.decode(RawEnvelope<ShareWire>.self)
                #expect(json.data.items[0].checked == true)
            })
        }
    }

    /// The core correctness property: a shopper's tick (server-stamped
    /// "now") must survive a subsequent owner push whose incoming item still
    /// carries the OLD checked value at an OLDER timestamp — i.e. the owner
    /// app hadn't pulled the shopper's tick yet before its own debounced
    /// push fired. See GroceryShareController.createOrReplace's merge logic.
    @Test func staleOwnerPushDoesNotClobberNewerShopperTick() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            let itemID = UUID().uuidString
            let staleTimestamp = Date().addingTimeInterval(-3600)
            var shareToken = ""

            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(id: itemID, checked: false, updatedAt: staleTimestamp)])
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
            })

            // Shopper ticks it — server stamps "now" (newer than staleTimestamp).
            try await app.test(.POST, "g/\(shareToken)/items/\(itemID)", beforeRequest: { req in
                req.headers.contentType = .json
                req.body = ByteBuffer(data: try! JSONSerialization.data(withJSONObject: ["checked": true]))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
            })

            // Owner's app pushes again, still carrying the OLD unchecked value
            // at the OLD (stale) timestamp — simulating a debounced push that
            // fired before the owner pulled the shopper's tick.
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(token: shareToken, items: [item(id: itemID, checked: false, updatedAt: staleTimestamp)])
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<ShareWire>.self)
                #expect(json.data.items[0].checked == true, "the shopper's newer tick must survive a stale owner push")
            })
        }
    }

    @Test func newerOwnerPushOverridesOlderCheckedState() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            let itemID = UUID().uuidString
            var shareToken = ""

            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(id: itemID, checked: true, updatedAt: Date().addingTimeInterval(-10))])
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
            })

            // Owner genuinely unchecks it locally right now — newer timestamp.
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(token: shareToken, items: [item(id: itemID, checked: false, updatedAt: Date())])
            }, afterResponse: { res async throws in
                let json = try res.content.decode(RawEnvelope<ShareWire>.self)
                #expect(json.data.items[0].checked == false, "a genuinely newer owner edit must win")
            })
        }
    }

    // MARK: - HTML escaping

    @Test func publicPageEscapesTitleAndStore() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            var shareToken = ""
            let payload: [String: Any] = [
                "title": "<script>alert(1)</script>",
                "store": "Tom & Jerry's \"Market\"",
                "items": [item(name: "Milk")],
            ]
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = ByteBuffer(data: try! JSONSerialization.data(withJSONObject: payload))
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
            })

            try await app.test(.GET, "g/\(shareToken)", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let html = res.body.string
                #expect(!html.contains("<script>alert(1)</script>"))
                #expect(html.contains("&lt;script&gt;"))
                #expect(html.contains("Tom &amp; Jerry&#39;s &quot;Market&quot;"))
            })
        }
    }

    /// Regression: SecurityHeadersMiddleware sent `default-src 'none'` on every
    /// response, so the page's inline <style>/<script> were blocked — unstyled,
    /// stuck on "Loading…", ticks never synced.
    @Test func publicPageCarriesANonceCSPMatchingItsInlineTags() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            var shareToken = ""
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(name: "Milk")])
            }, afterResponse: { res async throws in
                shareToken = try res.content.decode(RawEnvelope<ShareWire>.self).data.token
                // JSON API responses keep the strict default.
                #expect(res.headers.first(name: "Content-Security-Policy") == "default-src 'none'")
            })

            try await app.test(.GET, "g/\(shareToken)", afterResponse: { res async throws in
                let csp = try #require(res.headers.first(name: "Content-Security-Policy"))
                #expect(csp.contains("script-src 'nonce-"))
                #expect(csp.contains("style-src 'nonce-"))
                #expect(csp.contains("connect-src 'self'"))
                let nonce = try #require(csp.components(separatedBy: "script-src 'nonce-").last?.components(separatedBy: "'").first)
                #expect(!nonce.isEmpty)
                let html = res.body.string
                #expect(html.contains("<script nonce=\"\(nonce)\">"))
                #expect(html.contains("<style nonce=\"\(nonce)\">"))
            })

            // Two responses never share a nonce.
            var first = ""
            try await app.test(.GET, "g/\(shareToken)", afterResponse: { res async in
                first = res.headers.first(name: "Content-Security-Policy") ?? ""
            })
            try await app.test(.GET, "g/\(shareToken)", afterResponse: { res async in
                #expect(res.headers.first(name: "Content-Security-Policy") != first)
            })
        }
    }

    // MARK: - Validation

    @Test func emptyTitleIsBadRequest() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(title: "   ", items: [item()])
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test func duplicateItemIDsAreBadRequest() async throws {
        try await withApp { app in
            let (_, authToken) = try await makeUser(app: app)
            let dupID = UUID().uuidString
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: authToken)
                req.headers.contentType = .json
                req.body = upsertBody(items: [item(id: dupID), item(id: dupID)])
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test func unauthenticatedCreateIsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.contentType = .json
                req.body = upsertBody(items: [item()])
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }

    // MARK: - Rate limiting (public routes)

    @Test func publicRoutesAreIPRateLimited() async throws {
        try await withApp { app in
            // Exercise the real `/g` group's own tiny-limit twin: register a
            // second, identically-behaved route under a fresh path with a
            // 2-req/min cap so the test doesn't need 61 requests to trip it.
            try app.grouped("g-test")
                .grouped(RateLimitMiddleware(limit: 2, window: .minutes(1), scope: .ip))
                .register(collection: PublicGroceryShareController())

            for _ in 0 ..< 2 {
                try await app.test(.GET, "g-test/does-not-exist", afterResponse: { res async throws in
                    #expect(res.status == .gone, "under the limit, requests reach the handler")
                })
            }
            try await app.test(.GET, "g-test/does-not-exist", afterResponse: { res async throws in
                #expect(res.status == .tooManyRequests)
                #expect(res.headers.first(name: "Retry-After") != nil)
            })
        }
    }
}

// MARK: - Minimal decode-side wire types

private struct RawEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
}

private struct ItemWire: Decodable, Equatable {
    let id: String
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let checked: Bool
}

private struct ShareWire: Decodable {
    let token: String
    let url: String
    let title: String
    let store: String?
    let items: [ItemWire]
    let revoked: Bool
}
