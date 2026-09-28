import Vapor

// MARK: - SupplementController

//
// Wire contract fixed by Tempo/Tempo/Services/Network/APIEndpoints+Supplements.swift
// (feat/supplements-base, commit e8d5dd3):
//
//   GET /v1/supplements/lookup/:upc        → Envelope<SupplementLookupDTO>
//       Barcode → product. NIH DSLD first, Open Food Facts fallback. 404 when
//       neither database knows the code.
//   GET /v1/supplements/picks/:kind?name=… → Envelope<SupplementPicksDTO>
//       2–3 vetted, third-party-tested products for a supplement type. A
//       curated, researched catalog (SupplementCuratedCatalog.swift) covers
//       the common cases (`verified: true`); anything else falls back to a
//       Claude Haiku suggestion (`verified: false`), cached ~30 days.
//
// Never invents a certification: the curated catalog only lists products
// whose certification was checked against the certifier's own site/listing
// (see SupplementCuratedCatalog.swift doc comment for sourcing notes).

struct SupplementController: RouteCollection {
    let lookupClient: SupplementLookupClient

    init(lookupClient: SupplementLookupClient = SupplementLookupAPIClient()) {
        self.lookupClient = lookupClient
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get("lookup", ":upc", use: lookup)
        routes.get("picks", ":kind", use: picks)
    }

    // MARK: - GET /v1/supplements/lookup/:upc

    @Sendable
    func lookup(_ req: Request) async throws -> Envelope<SupplementLookupDTO> {
        _ = try req.auth.requireUserID()
        guard let rawUPC = req.parameters.get("upc") else {
            throw Abort(.badRequest, reason: "Missing UPC.")
        }
        let upc = rawUPC.filter(\.isNumber)
        guard upc.count >= 6, upc.count <= 14 else {
            throw Abort(.badRequest, reason: "UPC must be 6–14 digits.")
        }

        let cacheKey = AICacheKey.supplementLookup(upc: upc)
        let (result, _) = try await AICache.shared.withCache(
            key: cacheKey,
            on: req
        ) { () -> SupplementLookupDTO? in
            try await lookupClient.lookup(upc: upc, on: req)
        }

        guard let result else {
            throw Abort(.notFound, reason: "No supplement found for this barcode.")
        }
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: - GET /v1/supplements/picks/:kind

    @Sendable
    func picks(_ req: Request) async throws -> Envelope<SupplementPicksDTO> {
        _ = try req.auth.requireUserID()
        guard let kindRaw = req.parameters.get("kind"), SupplementKindWire(rawValue: kindRaw) != nil else {
            throw Abort(.badRequest, reason: "Unknown supplement kind.")
        }
        let rawName = (try? req.query.get(String.self, at: "name")) ?? ""
        // Goes into an AI prompt: letters, digits, spaces and basic label
        // punctuation only — no quotes, newlines or tags to break out with.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -+.,&%/()'"))
        let cleaned = String(String.UnicodeScalarView(rawName.unicodeScalars.filter { allowed.contains($0) }))
        let name = String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))

        if let slug = SupplementCatalogSlug.match(kind: kindRaw, name: name),
           let entry = SupplementCuratedCatalog.entries[slug]
        {
            let dto = SupplementPicksDTO(
                kind: kindRaw,
                picks: entry.picks.map { $0.toWire() },
                verified: true,
                lookFor: entry.lookFor
            )
            return Envelope(data: dto, requestID: req.requestID)
        }

        // Not in the curated catalog — Claude Haiku fallback, honestly marked
        // unverified. Cached ~30 days per (kind, name) so repeat lookups for
        // the same unusual supplement don't keep re-billing Claude.
        let dto = try await SupplementAIPicksService.picks(kind: kindRaw, name: name, on: req)
        return Envelope(data: dto, requestID: req.requestID)
    }
}

/// Just for route validation — mirrors the iOS `SupplementKind` raw values.
/// Kept private to this controller; the source of truth for the enum itself
/// lives in the iOS app (Tempo/Models/Nutrition/Supplement.swift).
private enum SupplementKindWire: String {
    case protein, creatine, omega3, multivitamin, vitamin, preworkout, electrolytes, other
}

// MARK: - DTOs

struct SupplementLookupDTO: Content, Equatable {
    let upc: String
    let brand: String?
    let name: String
    /// `SupplementKind.rawValue` best guess.
    let kind: String
    let dosePerServing: String?
    let servingsPerContainer: Double?
    let proteinGramsPerServing: Double?
    let certifications: [String]
    /// "dsld" | "openfoodfacts"
    let source: String

    enum CodingKeys: String, CodingKey {
        case upc, brand, name, kind
        case dosePerServing = "dose_per_serving"
        case servingsPerContainer = "servings_per_container"
        case proteinGramsPerServing = "protein_grams_per_serving"
        case certifications
        case source
    }
}

struct SupplementPicksDTO: Content, Equatable {
    let kind: String
    let picks: [Pick]
    let verified: Bool
    let lookFor: String?

    struct Pick: Content, Equatable {
        let brand: String
        let product: String
        let form: String?
        let certifications: [String]
        let why: String
        let approxPricePerServingUSD: Double?
        let priceAsOf: String?
        let buyLinks: [BuyLink]

        enum CodingKeys: String, CodingKey {
            case brand, product, form, certifications, why
            case approxPricePerServingUSD = "approx_price_per_serving_usd"
            case priceAsOf = "price_as_of"
            case buyLinks = "buy_links"
        }
    }

    struct BuyLink: Content, Equatable {
        let label: String
        let url: String
    }

    enum CodingKeys: String, CodingKey {
        case kind, picks, verified
        case lookFor = "look_for"
    }
}
