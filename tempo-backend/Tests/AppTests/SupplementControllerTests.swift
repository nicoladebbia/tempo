@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - SupplementController tests

//
// Uses the `configure(app:supplementLookupClient:)` seam to inject
// FakeSupplementLookupClient for the /lookup endpoint. The /picks endpoint
// needs no injection seam: curated (kind, name) combos are served straight
// from SupplementCuratedCatalog (in-process, no network), and unknown combos
// exercise the real AIFeatureRunner fallback path (ANTHROPIC_API_KEY is
// unset for this test, so it fails fast with `missingAPIKey` and returns the
// deterministic fallback — no live network call).

@Suite("SupplementController", .serialized)
struct SupplementControllerTests {
    private func withApp(lookupClient: SupplementLookupClient, _ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, supplementLookupClient: lookupClient)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Decodes with a plain, un-configured JSONDecoder rather than
    /// `res.content.decode` — the app's global ContentConfiguration decoder
    /// sets `.convertFromSnakeCase`, which pre-transforms JSON keys (e.g.
    /// "buy_links" → "buyLinks") before they ever reach our DTOs' explicit
    /// snake_case CodingKeys, causing a spurious keyNotFound. The DTOs match
    /// the wire contract exactly via their own CodingKeys, so a decoder with
    /// no key strategy is what mirrors how the iOS client actually decodes
    /// this JSON.
    private func decodeEnvelope<T: Decodable>(_ res: XCTHTTPResponse, as _: T.Type) throws -> RawEnvelope<T> {
        try JSONDecoder().decode(RawEnvelope<T>.self, from: Data(buffer: res.body))
    }

    /// A fresh, never-before-seen UPC per test run — the lookup endpoint
    /// caches results in the shared Redis instance for ~30 days, so reusing
    /// a fixed UPC across test runs would silently hit a stale cache entry
    /// instead of exercising the fake client.
    private func freshUPC() -> String {
        // NOT String(format: "%012d", ...) — %d promotes its CVarArg to a
        // 32-bit C int, silently truncating (and sometimes negating) a
        // 64-bit Int this large. Plain string construction avoids that trap
        // entirely and is still always exactly 12 digits.
        let body = (0 ..< 11).map { _ in Int.random(in: 0 ... 9) }
        // Lookups validate the GTIN check digit, so a random code must carry a valid one.
        return (body + [SupplementUPC.checkDigit(forBody: body)]).map(String.init).joined()
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

    // MARK: - /v1/supplements/picks/:kind

    @Test func curatedMatchReturnsVerifiedTrue() async throws {
        try await withApp(lookupClient: FakeSupplementLookupClient(response: .notFound)) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/picks/creatine?name=Creatine", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try decodeEnvelope(res, as: SupplementPicksDTO.self)
                #expect(json.data.verified == true)
                #expect(json.data.kind == "creatine")
                #expect(!json.data.picks.isEmpty)
                #expect(json.data.picks.allSatisfy { !$0.certifications.isEmpty })
            })
        }
    }

    @Test func unusualNameFallsBackToAIAndIsMarkedUnverified() async throws {
        let previous = Environment.get("ANTHROPIC_API_KEY")
        unsetenv("ANTHROPIC_API_KEY")
        defer {
            if let previous {
                setenv("ANTHROPIC_API_KEY", previous, 1)
            }
        }

        try await withApp(lookupClient: FakeSupplementLookupClient(response: .notFound)) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/picks/other?name=Turmeric%20Curcumin", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try decodeEnvelope(res, as: SupplementPicksDTO.self)
                #expect(json.data.verified == false)
                #expect(json.data.kind == "other")
            })
        }
    }

    @Test func unknownKindIsBadRequest() async throws {
        try await withApp(lookupClient: FakeSupplementLookupClient(response: .notFound)) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/picks/not-a-kind", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })
        }
    }

    // MARK: - /v1/supplements/lookup/:upc

    @Test func lookupReturnsResultFromClient() async throws {
        let upc = freshUPC()
        let dto = SupplementLookupDTO(
            upc: upc,
            brand: "Optimum Nutrition",
            name: "Gold Standard 100% Whey",
            kind: "protein",
            dosePerServing: "30.4 g",
            servingsPerContainer: 74,
            proteinGramsPerServing: 24,
            certifications: ["Informed Sport"],
            source: "openfoodfacts"
        )
        let fake = FakeSupplementLookupClient(response: .found(dto))
        try await withApp(lookupClient: fake) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/lookup/\(upc)", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try decodeEnvelope(res, as: SupplementLookupDTO.self)
                #expect(json.data.brand == "Optimum Nutrition")
                #expect(json.data.source == "openfoodfacts")
            })
        }
        #expect(fake.lastUPC == upc)
    }

    @Test func lookupReturnsNotFoundWhenClientHasNoMatch() async throws {
        let upc = freshUPC()
        try await withApp(lookupClient: FakeSupplementLookupClient(response: .notFound)) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/lookup/\(upc)", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .notFound)
            })
        }
    }

    @Test func lookupRejectsBadCheckDigit() async throws {
        try await withApp(lookupClient: FakeSupplementLookupClient(response: .notFound)) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/lookup/748927028660", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test func lookupUpstreamFailureIs502NotNotFound() async throws {
        let upc = freshUPC()
        try await withApp(lookupClient: FakeSupplementLookupClient(response: .failure(SupplementLookupError.upstreamUnavailable))) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/lookup/\(upc)", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .badGateway)
            })
        }
    }

    @Test func lookupRejectsMalformedUPC() async throws {
        try await withApp(lookupClient: FakeSupplementLookupClient(response: .notFound)) { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.GET, "v1/supplements/lookup/abc", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
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
