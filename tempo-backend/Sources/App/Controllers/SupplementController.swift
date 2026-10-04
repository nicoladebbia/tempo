import Vapor

// MARK: - SupplementController

//
// Wire contract fixed by Tempo/Tempo/Services/Network/APIEndpoints+Supplements.swift
// (feat/supplements-base, commit e8d5dd3):
//
//   GET /v1/supplements/lookup/:upc        → Envelope<SupplementLookupDTO>
//       Barcode → product. NIH DSLD (quoted UPC phrase) + the Open Facts family. 404 when
//       none knows the code; 502 when upstream failed (never cached).
//   GET /v1/supplements/search?q=…          → Envelope<[SupplementSearchHit]> (Tempo catalog + DSLD + Open Food Facts)
//   GET /v1/supplements/label/:id           → Envelope<SupplementLookupDTO> (a search hit, in full:
//       "123"/"dsld:123", "off:<barcode>", "tempo:<uuid>")
//   POST /v1/supplements/read-label         → Envelope<SupplementLookupDTO> (Claude vision reads a label photo)
//   POST /v1/supplements/catalog            → Envelope<SupplementLookupDTO> (add to / confirm in the shared catalog)
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
    let labelReader: SupplementLabelReading

    /// Base64 characters accepted for a label photo (~3.7 MB of image).
    static let maxImageBase64Chars = 5_000_000

    init(
        lookupClient: SupplementLookupClient = SupplementLookupAPIClient(),
        labelReader: SupplementLabelReading = ClaudeSupplementLabelReader()
    ) {
        self.lookupClient = lookupClient
        self.labelReader = labelReader
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get("lookup", ":upc", use: lookup)
        routes.get("search", use: search)
        routes.get("label", ":id", use: label)
        routes.get("picks", ":kind", use: picks)
        // Vision photo: same body ceiling idea as nutrition/ai/proxy/vision (5 MB image
        // as base64 plus JSON overhead), and a tighter per-user rate limit than the
        // group's, since every call is a Sonnet vision request.
        routes.grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
            .on(.POST, "read-label", body: .collect(maxSize: "6mb"), use: readLabel)
        routes.on(.POST, "catalog", body: .collect(maxSize: "64kb"), use: catalog)
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
        } catch let failure where failure is SupplementLookupMiss || (failure as? SupplementLookupError) == .upstreamUnavailable {
            // The outside databases don't have it (or didn't answer): the shared Tempo
            // catalog may, from someone's earlier label photo. Never cached: the
            // catalog changes whenever someone adds or confirms an entry.
            if let entry = try? await SupplementCatalogService.entry(upc: norm.canonical, on: req.db) {
                return Envelope(data: try await SupplementCatalogService.dto(entry, on: req.db), requestID: req.requestID)
            }
            if failure is SupplementLookupMiss {
                throw Abort(.notFound, reason: "No supplement found for this barcode.")
            }
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
        guard let hits = await SupplementSearchService.run(query: q, client: lookupClient, on: req) else {
            throw Abort(.badGateway, reason: "The supplement database didn't answer. Try again in a moment.")
        }
        return Envelope(data: hits, requestID: req.requestID)
    }

    // MARK: - GET /v1/supplements/label/:id  (a search hit → full product)

    /// "123" (legacy = DSLD), "dsld:123", "off:<8-14 digits>", "tempo:<uuid>".
    enum LabelID: Equatable {
        case dsld(String)
        case openFacts(String)
        case tempo(UUID)

        init?(_ raw: String) {
            func digits(_ s: Substring, _ range: ClosedRange<Int>) -> String? {
                range.contains(s.count) && s.allSatisfy({ $0.isASCII && $0.isNumber }) ? String(s) : nil
            }
            if let value = digits(Substring(raw), 1 ... 9) {
                self = .dsld(value)
            } else if raw.hasPrefix("dsld:"), let value = digits(raw.dropFirst(5), 1 ... 9) {
                self = .dsld(value)
            } else if raw.hasPrefix("off:"), let value = digits(raw.dropFirst(4), 8 ... 14) {
                self = .openFacts(value)
            } else if raw.hasPrefix("tempo:"), let uuid = UUID(uuidString: String(raw.dropFirst(6))) {
                self = .tempo(uuid)
            } else {
                return nil
            }
        }
    }

    @Sendable
    func label(_ req: Request) async throws -> Envelope<SupplementLookupDTO> {
        _ = try req.auth.requireUserID()
        guard let raw = req.parameters.get("id"), let id = LabelID(raw) else {
            throw Abort(.badRequest, reason: "Bad label id.")
        }
        let lookupClient = self.lookupClient
        let dto: SupplementLookupDTO
        do {
            switch id {
            case let .dsld(number):
                // Only found labels are cached; a miss or failure is retried next time.
                (dto, _) = try await AICache.shared.withCache(key: .supplementLabel(id: number), on: req) {
                    guard let found = try await lookupClient.label(id: number, on: req) else {
                        throw SupplementLookupMiss()
                    }
                    return found
                }
            case let .openFacts(code):
                (dto, _) = try await AICache.shared.withCache(key: .supplementLabel(id: "off:\(code)"), on: req) {
                    guard let found = try await lookupClient.openFactsLabel(barcode: code, on: req) else {
                        throw SupplementLookupMiss()
                    }
                    return found
                }
            case let .tempo(uuid):
                // Not cached: confirmations and owner edits change it.
                guard let entry = try await SupplementCatalogService.entry(id: uuid, on: req.db) else {
                    throw SupplementLookupMiss()
                }
                dto = try await SupplementCatalogService.dto(entry, on: req.db)
            }
        } catch is SupplementLookupMiss {
            throw Abort(.notFound, reason: "Label not found.")
        } catch {
            throw Abort(.badGateway, reason: "The supplement database didn't answer. Try again in a moment.")
        }
        return Envelope(data: dto, requestID: req.requestID)
    }

    // MARK: - POST /v1/supplements/read-label

    @Sendable
    func readLabel(_ req: Request) async throws -> Envelope<SupplementLookupDTO> {
        _ = try req.auth.requireUserID()
        let input = try req.content.decode(SupplementReadLabelRequest.self)
        let mediaType = input.mediaType.lowercased()
        guard ["image/jpeg", "image/png", "image/webp"].contains(mediaType) else {
            throw Abort(.unsupportedMediaType, reason: "Send the photo as JPEG, PNG or WebP.")
        }
        guard !input.imageBase64.isEmpty, input.imageBase64.count <= Self.maxImageBase64Chars else {
            throw Abort(.payloadTooLarge, reason: "That photo is too big. Try again.")
        }
        guard let bytes = Data(base64Encoded: input.imageBase64), !bytes.isEmpty else {
            throw Abort(.badRequest, reason: "The photo couldn't be read.")
        }
        var upc = ""
        if let raw = input.upc?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            // A bad barcode shouldn't cost the user their scan: just leave it out.
            upc = (try? SupplementUPC.normalize(raw).canonical) ?? ""
        }

        let text: String
        do {
            text = try await labelReader.readLabel(imageBase64: input.imageBase64, mediaType: mediaType, on: req)
        } catch NutritionProxyError.budgetExhausted {
            throw Abort(.tooManyRequests, reason: "AI budget exhausted for this month.")
        }
        let dto = try SupplementLabelParser.parse(text, upc: upc)
        return Envelope(data: dto, requestID: req.requestID)
    }

    // MARK: - POST /v1/supplements/catalog

    @Sendable
    func catalog(_ req: Request) async throws -> Envelope<SupplementLookupDTO> {
        let userID = try req.auth.requireUserID()
        let input = try req.content.decode(SupplementCatalogRequest.self)
        let submission = try SupplementCatalogService.validate(input)
        try await SupplementCatalogService.enforceCap(userID: userID, on: req)
        let dto = try await SupplementCatalogService.submit(submission, userID: userID, on: req.db)
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

/// camelCase on purpose: the global decoder converts the snake_case wire keys.
struct SupplementReadLabelRequest: Content {
    let imageBase64: String
    let mediaType: String
    let upc: String?
}

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
    /// "dsld" | "openfoodfacts" | "openproductsfacts" | "openbeautyfacts" |
    /// "label_photo" (AI read, not yet saved) | "tempo" (shared catalog)
    let source: String
    /// Active ingredients with amounts ("Vitamin D3 25 mcg"), when DSLD has them.
    let ingredients: [String]?
    /// Only set when `source == "tempo"`: distinct users who submitted or
    /// confirmed this shared-catalog entry (>= 1).
    let communityConfirmations: Int?

    init(
        upc: String, brand: String?, name: String, kind: String,
        dosePerServing: String?, servingsPerContainer: Double?,
        proteinGramsPerServing: Double?,
        caloriesPerServing: Double? = nil, carbsGramsPerServing: Double? = nil, fatGramsPerServing: Double? = nil,
        certifications: [String], source: String, ingredients: [String]? = nil,
        communityConfirmations: Int? = nil
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
        self.communityConfirmations = communityConfirmations
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
        case communityConfirmations = "community_confirmations"
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
