import Fluent
import Vapor

// MARK: - BrandCatalogController

// Optional backend-backed brand/size catalog for the iOS
// `ReceiptProductMatcher`. Routes:
//   GET /v1/nutrition/brand-catalog?brand=&q= — simple filtered lookup
//
// `refresher` is constructor-injected (mirrors SupplementController's
// `lookupClient` seam) so a real Open Food Facts-backed implementation can
// be swapped in later without touching this controller's call sites. See
// BrandCatalogRefreshing for the deliberate scope cut (no live calls, no
// scheduled job — plumbing only).

struct BrandCatalogController: RouteCollection {
    let refresher: BrandCatalogRefreshing

    init(refresher: BrandCatalogRefreshing = NullBrandCatalogRefresher()) {
        self.refresher = refresher
    }

    static let maxResults = 50

    func boot(routes: RoutesBuilder) throws {
        routes.get(use: list)
    }

    // MARK: - GET /

    @Sendable
    func list(req: Request) async throws -> Envelope<[BrandCatalogItemDTO]> {
        _ = try req.auth.requireUserID()
        let query = try req.query.decode(BrandCatalogQuery.self)

        var builder = BrandCatalogItem.query(on: req.db)

        if let brand = query.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            // Fluent's `~~` is a plain SQL LIKE (case-sensitive on Postgres),
            // not ILIKE — a documented simplification per "doesn't need to
            // be fancy" in the product ask. Good enough for a typeahead
            // seeded from exact OFF brand slugs.
            builder = builder.filter(\.$brand ~~ brand)
        }
        if let q = query.q?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            builder = builder.group(.or) { group in
                group.filter(\.$name ~~ q)
                group.filter(\.$genericName ~~ q)
            }
        }

        // TODO(BrandCatalogRefreshing): lazy-on-stale-lookup trigger point.
        // If `query.brand` is set and either no rows come back or every
        // matching row's `updatedAt` is older than 7 days, call
        // `refresher.refresh(brand:on:)` here and merge/persist the result
        // before responding. Deliberately NOT done yet — see
        // BrandCatalogRefreshing's scope-cut note.

        let rows = try await builder
            .sort(\.$brand)
            .sort(\.$name)
            .limit(Self.maxResults)
            .all()

        return Envelope(data: rows.map(BrandCatalogItemDTO.init(model:)), requestID: req.requestID)
    }
}

// MARK: - Wire DTOs

struct BrandCatalogQuery: Content {
    let brand: String?
    let q: String?
}

struct BrandCatalogItemDTO: Content {
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

    init(model: BrandCatalogItem) {
        id = model.id?.uuidString ?? ""
        brand = model.brand
        chain = model.chain
        name = model.name
        genericName = model.genericName
        sizeValue = model.sizeValue
        sizeUnit = model.sizeUnit
        packCount = model.packCount
        barcode = model.barcode
        imageURL = model.imageURL
        categories = model.categories
        updatedAt = model.updatedAt
        isStale = model.isStale
    }
}
