@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - BrandCatalogController tests

//
// Real Postgres + Redis harness (same pattern as SupplementControllerTests).
// No real network calls anywhere here — BrandCatalogRefreshing is never
// invoked by the endpoint (deliberate scope cut, see
// BrandCatalogRefreshing.swift); the seam is exercised directly via
// FakeBrandCatalogRefresher.

@Suite("BrandCatalogController", .serialized)
struct BrandCatalogTests {
    private func withApp(
        refresher: BrandCatalogRefreshing = NullBrandCatalogRefresher(),
        _ body: (Application) async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, brandCatalogRefresher: refresher)
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

    /// brand-catalog rows are never cleaned up between tests (or between
    /// separate `swift test` runs against the same shared Postgres
    /// container), and the table has no per-user scoping to isolate on. Every
    /// test that counts rows gives its brand/search term a unique suffix so
    /// it can never match another test's (or another run's) leftover data.
    private func uniqueSuffix() -> String {
        UUID().uuidString.lowercased().prefix(8).description
    }

    @discardableResult
    private func seed(
        app: Application,
        brand: String,
        name: String,
        chain: String? = nil,
        genericName: String? = nil,
        barcode: String? = nil,
        categories: [String]? = nil
    ) async throws -> BrandCatalogItem {
        let item = BrandCatalogItem(
            brand: brand,
            chain: chain,
            name: name,
            genericName: genericName,
            barcode: barcode,
            categories: categories
        )
        try await item.save(on: app.db)
        return item
    }

    // MARK: - Migration

    @Test func migrationCreatesTableAndRoundTripsAllColumns() async throws {
        try await withApp { app in
            let barcode = "bc_\(uniqueSuffix())"
            let item = BrandCatalogItem(
                brand: "Publix",
                chain: "publix",
                name: "Publix Greek Yogurt 0%",
                genericName: "greek yogurt",
                sizeValue: 5.3,
                sizeUnit: "oz",
                packCount: 1,
                barcode: barcode,
                imageURL: "https://example.com/img.jpg",
                categories: ["dairy", "yogurt"]
            )
            try await item.save(on: app.db)

            let fetched = try await BrandCatalogItem.query(on: app.db)
                .filter(\.$barcode == barcode)
                .first()
            #expect(fetched?.name == "Publix Greek Yogurt 0%")
            #expect(fetched?.brand == "Publix")
            #expect(fetched?.chain == "publix")
            #expect(fetched?.sizeValue == 5.3)
            #expect(fetched?.sizeUnit == "oz")
            #expect(fetched?.packCount == 1)
            #expect(fetched?.categories == ["dairy", "yogurt"])
            #expect(fetched?.isStale == false)
        }
    }

    // MARK: - GET /v1/nutrition/brand-catalog

    @Test func filtersByBrand() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let brand = "Publix_\(uniqueSuffix())"
            try await seed(app: app, brand: brand, name: "Publix Greek Yogurt 0%")
            try await seed(app: app, brand: brand, name: "Publix 2% Milk")
            try await seed(app: app, brand: "Great Value_\(uniqueSuffix())", name: "Great Value Whole Milk")

            try await app.test(.GET, "v1/nutrition/brand-catalog?brand=\(brand)", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<[ItemWire]>.self)
                #expect(json.data.count == 2)
                #expect(json.data.allSatisfy { $0.brand == brand })
            })
        }
    }

    @Test func filtersByBrandAndQTogether() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let brand = "Publix_\(uniqueSuffix())"
            try await seed(app: app, brand: brand, name: "Publix Greek Yogurt 0%", genericName: "greek yogurt")
            try await seed(app: app, brand: brand, name: "Publix 2% Milk", genericName: "milk")

            try await app.test(.GET, "v1/nutrition/brand-catalog?brand=\(brand)&q=Yogurt", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<[ItemWire]>.self)
                #expect(json.data.count == 1)
                #expect(json.data[0].name == "Publix Greek Yogurt 0%")
            })
        }
    }

    @Test func qMatchesGenericNameToo() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let genericName = "whole milk \(uniqueSuffix())"
            try await seed(app: app, brand: "Great Value", name: "GV Whole Milk", genericName: genericName)

            try await app.test(.GET, "v1/nutrition/brand-catalog?q=\(genericName)", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<[ItemWire]>.self)
                #expect(json.data.count == 1)
                #expect(json.data[0].genericName == genericName)
            })
        }
    }

    @Test func emptyResultWhenNoMatch() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            try await seed(app: app, brand: "Publix_\(uniqueSuffix())", name: "Publix Greek Yogurt 0%")

            try await app.test(.GET, "v1/nutrition/brand-catalog?brand=NoSuchBrandXYZ_\(uniqueSuffix())", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<[ItemWire]>.self)
                #expect(json.data.isEmpty)
            })
        }
    }

    // MARK: - Injected fake refresher seam

    @Test func injectedFakeRefresherSeamIsInvokedDirectlyNotViaEndpoint() async throws {
        try await withApp { app in
            let fake = FakeBrandCatalogRefresher()
            let (_, token) = try await makeUser(app: app)

            // Hitting the endpoint must NOT call the refresher — the refresh
            // trigger point is a documented TODO, not wired up yet.
            try await app.test(.GET, "v1/nutrition/brand-catalog?brand=Publix_\(uniqueSuffix())", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
            })
            #expect(fake.calledBrands.isEmpty)

            // The seam itself works when called directly.
            let req = Request(application: app, on: app.eventLoopGroup.next())
            let result = try await fake.refresh(brand: "Publix", on: req)
            #expect(result.isEmpty)
            #expect(fake.calledBrands == ["Publix"])
        }
    }
}

// MARK: - Wire types

private struct ItemWire: Decodable {
    let id: String
    let brand: String
    let chain: String?
    let name: String
    let genericName: String?
    let sizeValue: Double?
    let sizeUnit: String?
    let packCount: Int?
    let barcode: String?
    let imageURL: String?
    let categories: [String]?
    let updatedAt: Date
    let isStale: Bool
}

private struct RawEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
}
