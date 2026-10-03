import Vapor

// MARK: - SupplementController

//
// Wire contract fixed by Tempo/Tempo/Services/Network/APIEndpoints+Supplements.swift
// (feat/supplements-base, commit e8d5dd3):
//
//   GET /v1/supplements/lookup/:upc        → Envelope<SupplementLookupDTO>
//       Barcode → product. NIH DSLD (quoted UPC phrase) + the Open Facts family. 404 when
//       none knows the code; 502 when upstream failed (never cached).
//   GET /v1/supplements/search?q=…          → Envelope<[SupplementSearchHit]> (DSLD name search)
//   GET /v1/supplements/label/:id           → Envelope<SupplementLookupDTO> (a search hit, in full)
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
        routes.get("search", use: search)
        routes.get("label", ":id", use: label)
        routes.get("picks", ":kind", use: picks)
    }

    // MARK: - GET /v1/supplements/lookup/:upc

    @Sendable
    func lookup(_ req: Request) async throws -> Envelope<SupplementLookupDTO> {
        _ = try req.auth.requireUserID()
        guard let rawUPC = req.parameters.get("upc") else {
            throw Abort(.badRequest, reason: "Missing UPC.")
        }
        let norm: NormalizedUPC
        do {
            norm = try SupplementUPC.normalize(rawUPC)
        } catch SupplementUPC.Failure.badCheckDigit {
            throw Abort(.badRequest, reason: "That barcode doesn't look right. Check the digits or scan again.")
        } catch {
            throw Abort(.badRequest, reason: "A barcode has 8, 12 or 13 digits.")
        }

        // Only HITS are cached. A miss (or an upstream failure, which used to
        // be swallowed into a miss) must never stick for 30 days: the
        // databases gain products, and a timeout is not "not found".
        let cacheKey = AICacheKey.supplementLookup(upc: norm.canonical)
        let lookupClient = self.lookupClient
        let result: SupplementLookupDTO
        do {
            (result, _) = try await AICache.shared.withCache(key: cacheKey, on: req) { () -> SupplementLookupDTO in
                guard let dto = try await lookupClient.lookup(upc: norm.canonical, on: req) else {
                    throw SupplementLookupMiss()
                }
                return dto
            }
        } catch is SupplementLookupMiss {
            throw Abort(.notFound, reason: "No supplement found for this barcode.")
        } catch SupplementLookupError.upstreamUnavailable {
            throw Abort(.badGateway, reason: "The supplement databases didn't answer. Try again in a moment.")
        }
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: - GET /v1/supplements/search?q=

    @Sendable
    func search(_ req: Request) async throws -> Envelope<[SupplementSearchHit]> {
        _ = try req.auth.requireUserID()
        let q = String(((try? req.query.get(String.self, at: "q")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard q.count >= 2 else {
            throw Abort(.badRequest, reason: "Type at least 2 letters.")
        }
        do {
            let hits = try await lookupClient.search(query: q, on: req)
            return Envelope(data: hits, requestID: req.requestID)
        } catch {
            throw Abort(.badGateway, reason: "The supplement database didn't answer. Try again in a moment.")
        }
    }

    // MARK: - GET /v1/supplements/label/:id  (a search hit → full product)

    @Sendable
    func label(_ req: Request) async throws -> Envelope<SupplementLookupDTO> {
        _ = try req.auth.requireUserID()
        guard let id = req.parameters.get("id"), id.count <= 9, id.allSatisfy(\.isNumber) else {
            throw Abort(.badRequest, reason: "Bad label id.")
        }
        let dto: SupplementLookupDTO?
        do {
            dto = try await lookupClient.label(id: id, on: req)
        } catch {
            throw Abort(.badGateway, reason: "The supplement database didn't answer. Try again in a moment.")
        }
        guard let dto else { throw Abort(.notFound, reason: "Label not found.") }
        return Envelope(data: dto, requestID: req.requestID)
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

struct SupplementLookupMiss: Error {}

struct SupplementLookupDTO: Content, Equatable {
    let upc: String
    let brand: String?
    let name: String
    /// `SupplementKind.rawValue` best guess.
    let kind: String
    let dosePerServing: String?
    let servingsPerContainer: Double?
    let proteinGramsPerServing: Double?
    /// Optional macros per serving (added Oct 2026). Omitted when the label
    /// data doesn't carry them; older clients ignore the keys.
    let caloriesPerServing: Double?
    let carbsGramsPerServing: Double?
    let fatGramsPerServing: Double?
    let certifications: [String]
    /// "dsld" | "openfoodfacts" | "openproductsfacts" | "openbeautyfacts"
    let source: String
    /// Active ingredients with amounts ("Vitamin D3 25 mcg"), when DSLD has them.
    let ingredients: [String]?

    init(
        upc: String, brand: String?, name: String, kind: String,
        dosePerServing: String?, servingsPerContainer: Double?,
        proteinGramsPerServing: Double?,
        caloriesPerServing: Double? = nil, carbsGramsPerServing: Double? = nil, fatGramsPerServing: Double? = nil,
        certifications: [String], source: String, ingredients: [String]? = nil
    ) {
        self.upc = upc
        self.brand = brand
        self.name = name
        self.kind = kind
        self.dosePerServing = dosePerServing
        self.servingsPerContainer = servingsPerContainer
        self.proteinGramsPerServing = proteinGramsPerServing
        self.caloriesPerServing = caloriesPerServing
        self.carbsGramsPerServing = carbsGramsPerServing
        self.fatGramsPerServing = fatGramsPerServing
        self.certifications = certifications
        self.source = source
        self.ingredients = ingredients
    }

    enum CodingKeys: String, CodingKey {
        case upc, brand, name, kind
        case dosePerServing = "dose_per_serving"
        case servingsPerContainer = "servings_per_container"
        case proteinGramsPerServing = "protein_grams_per_serving"
        case caloriesPerServing = "calories_per_serving"
        case carbsGramsPerServing = "carbs_grams_per_serving"
        case fatGramsPerServing = "fat_grams_per_serving"
        case certifications
        case source
        case ingredients
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
