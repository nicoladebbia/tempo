import Foundation
import Vapor

// MARK: - SupplementLookupClient

//
// Barcode → product, verified against the REAL APIs (Oct 2026, live curl):
//
//   - NIH DSLD (api.ods.od.nih.gov/dsld/v9) has no UPC field in search, BUT a
//     QUOTED phrase search on the label's own spacing does work as a barcode
//     lookup: `search-filter?q="7 48927 02866 9"` returns the labels whose
//     `upcSku` is exactly that phrase. (The unquoted/plain digits form
//     returns nothing, which is why earlier versions concluded DSLD had no
//     barcode search.) Every hit is verified against the full `/label/{id}`
//     record's `upcSku` digits before it is trusted.
//   - Open Food Facts, Open Products Facts and Open Beauty Facts are keyed by
//     barcode (`/api/v2/product/<ean13>.json`).
//   - UPCitemdb's trial endpoint works without a key, but is rate-limited per
//     IP (100/day shared by every user of this server) and its terms restrict
//     it to non-commercial use. Not used.
//
// Pipeline: normalise the UPC, then DSLD-by-UPC and the Open*Facts family run
// concurrently; DSLD wins for dose / servings / ingredients / certifications,
// Open*Facts fills what DSLD lacks (protein for whey, macros). Only when both
// know nothing do we fall back to Open Food Facts + a DSLD name enrichment.
// A source that ERRORS (timeout, 5xx) is not a miss: if nothing was found and
// something errored, the lookup throws so the result is NOT cached and the app
// says "try again" instead of pretending the product doesn't exist.

protocol SupplementLookupClient: Sendable {
    func lookup(upc: String, on req: Request) async throws -> SupplementLookupDTO?
    /// Name search over DSLD. Default: no results (test doubles).
    func search(query: String, on req: Request) async throws -> [SupplementSearchHit]
    /// Full DTO for a DSLD label id picked from `search`.
    func label(id: String, on req: Request) async throws -> SupplementLookupDTO?
}

extension SupplementLookupClient {
    func search(query _: String, on _: Request) async throws -> [SupplementSearchHit] { [] }
    func label(id _: String, on _: Request) async throws -> SupplementLookupDTO? { nil }
}

enum SupplementLookupError: Error {
    case timeout
    /// Upstream databases failed and nothing else answered.
    case upstreamUnavailable
}

/// Outcome of asking one source.
enum SourceResult<T: Sendable>: Sendable {
    case hit(T)
    case miss
    case error
}

struct SupplementSearchHit: Content, Equatable {
    let id: String
    let brand: String?
    let name: String
    let kind: String
    let netContents: String?
    let onMarket: Bool

    enum CodingKeys: String, CodingKey {
        case id, brand, name, kind
        case netContents = "net_contents"
        case onMarket = "on_market"
    }
}

struct SupplementLookupAPIClient: SupplementLookupClient {
    private let requestTimeoutSeconds: Double = 12

    func lookup(upc: String, on req: Request) async throws -> SupplementLookupDTO? {
        let norm = try SupplementUPC.normalize(upc)

        async let dsldResult = Self.guarded(requestTimeoutSeconds) { try await Self.fetchDSLDByUPC(norm, on: req) }
        async let offResult = Self.guarded(requestTimeoutSeconds) { try await Self.fetchOpenFamily(norm, on: req) }
        let (dsld, off) = await (dsldResult, offResult)

        var dsldLabel: DSLDLabel?
        if case let .hit(label) = dsld { dsldLabel = label }
        var offHit: OpenFactsHit?
        if case let .hit(hit) = off { offHit = hit }

        if dsldLabel == nil, offHit == nil {
            if case .error = dsld { throw SupplementLookupError.upstreamUnavailable }
            if case .error = off { throw SupplementLookupError.upstreamUnavailable }
            return nil
        }

        return Self.merge(upc: norm.canonical, off: offHit?.product, dsld: dsldLabel, offSource: offHit?.source ?? "openfoodfacts")
    }

    func search(query: String, on req: Request) async throws -> [SupplementSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let uri = URI(string: "https://api.ods.od.nih.gov/dsld/v9/search-filter?q=\(Self.percentEncode(q))&size=40")
        let response = try await withTimeout(requestTimeoutSeconds) { try await req.client.get(uri) }
        guard response.status == .ok else { throw SupplementLookupError.upstreamUnavailable }
        let decoded = try response.content.decode(DSLDSearchResponse.self)
        return Self.mapSearchHits(decoded)
    }

    func label(id: String, on req: Request) async throws -> SupplementLookupDTO? {
        guard id.allSatisfy(\.isNumber), !id.isEmpty else { return nil }
        let uri = URI(string: "https://api.ods.od.nih.gov/dsld/v9/label/\(id)")
        let response = try await withTimeout(requestTimeoutSeconds) { try await req.client.get(uri) }
        guard response.status == .ok else { return nil }
        let label = try response.content.decode(DSLDLabel.self)
        let upc = label.upcSku?.filter(\.isNumber) ?? ""
        return Self.merge(upc: upc, off: nil, dsld: label, offSource: "openfoodfacts")
    }

    /// Runs `operation` with a timeout and folds throws into `.error`.
    private static func guarded<T: Sendable>(
        _ seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T?
    ) async -> SourceResult<T> {
        do {
            if let value = try await withTimeout(seconds, operation) { return .hit(value) }
            return .miss
        } catch {
            return .error
        }
    }

    // MARK: - DSLD by UPC

    static func mapSearchHits(_ response: DSLDSearchResponse) -> [SupplementSearchHit] {
        var seen = Set<String>()
        var hits: [SupplementSearchHit] = []
        for hit in response.hits {
            let src = hit.source
            guard let name = src?.fullName, !name.isEmpty else { continue }
            let key = "\((src?.brandName ?? "").lowercased())|\(name.lowercased())"
            guard seen.insert(key).inserted else { continue }
            let kind = SupplementKindGuesser.guess(
                name: name, categories: nil, dsldProductType: src?.productType?.langualCodeDescription
            )
            hits.append(SupplementSearchHit(
                id: hit.id, brand: src?.brandName, name: name, kind: kind.rawValue,
                netContents: src?.netContents?.first?.display,
                onMarket: (src?.offMarket ?? 0) == 0
            ))
        }
        // Still-sold labels first, relevance order otherwise preserved.
        return hits.filter(\.onMarket) + hits.filter { !$0.onMarket }
    }

    /// Per-request cap for DSLD calls, well inside the overall lookup budget.
    private static let dsldRequestTimeoutSeconds: Double = 4

    private static func fetchDSLDByUPC(_ norm: NormalizedUPC, on req: Request) async throws -> DSLDLabel? {
        var failures = 0
        var candidates: [(id: String, label: DSLDLabel)] = []
        for phrase in norm.dsldPhrases {
            let uri = URI(string: "https://api.ods.od.nih.gov/dsld/v9/search-filter?q=\(percentEncode(phrase))&size=6")
            let response: ClientResponse
            do {
                response = try await withTimeout(dsldRequestTimeoutSeconds) { try await req.client.get(uri) }
            } catch { failures += 1; continue }
            guard response.status == .ok, let search = try? response.content.decode(DSLDSearchResponse.self) else {
                failures += 1
                continue
            }
            // Fetch the candidate labels side by side, each with its own
            // timeout, so one slow label can't eat the whole lookup budget.
            let matchDigits = norm.matchDigits
            let found = await withTaskGroup(of: (String, DSLDLabel)?.self) { group in
                for hit in search.hits.prefix(6) {
                    group.addTask {
                        let labelURI = URI(string: "https://api.ods.od.nih.gov/dsld/v9/label/\(hit.id)")
                        guard let labelResponse = try? await withTimeout(dsldRequestTimeoutSeconds, { try await req.client.get(labelURI) }),
                              labelResponse.status == .ok,
                              let label = try? labelResponse.content.decode(DSLDLabel.self)
                        else { return nil }
                        // The phrase search is fuzzy; only trust an exact barcode match.
                        let digits = label.upcSku?.filter(\.isNumber) ?? ""
                        return matchDigits.contains(digits) ? (hit.id, label) : nil
                    }
                }
                var matches: [(String, DSLDLabel)] = []
                for await match in group {
                    if let match { matches.append(match) }
                }
                return matches
            }
            candidates.append(contentsOf: found.map { (id: $0.0, label: $0.1) })
            if !candidates.isEmpty { break }
        }
        if let best = pickBestLabel(candidates) { return best }
        if failures == norm.dsldPhrases.count { throw SupplementLookupError.upstreamUnavailable }
        return nil
    }

    /// Prefer a label still on the market, then the newest.
    static func pickBestLabel(_ candidates: [(id: String, label: DSLDLabel)]) -> DSLDLabel? {
        candidates.sorted { a, b in
            let aOn = (a.label.offMarket ?? 0) == 0
            let bOn = (b.label.offMarket ?? 0) == 0
            if aOn != bOn { return aOn }
            return (a.label.entryDate ?? "") > (b.label.entryDate ?? "")
        }.first?.label
    }

    // MARK: - Open Food / Products / Beauty Facts

    struct OpenFactsHit: Sendable {
        let product: OFFProduct
        let source: String
    }

    private static let openFamily: [(host: String, source: String)] = [
        ("world.openfoodfacts.org", "openfoodfacts"),
        ("world.openproductsfacts.org", "openproductsfacts"),
        ("world.openbeautyfacts.org", "openbeautyfacts"),
    ]

    private static func fetchOpenFamily(_ norm: NormalizedUPC, on req: Request) async throws -> OpenFactsHit? {
        // One task per host (candidates tried in order inside it) so a slow
        // host cannot starve the others inside the overall timeout.
        let results: [(hit: OpenFactsHit?, errored: Bool, order: Int)] = await withTaskGroup(
            of: (OpenFactsHit?, Bool, Int).self
        ) { group in
            for (index, entry) in openFamily.enumerated() {
                group.addTask {
                    var errored = false
                    for code in norm.offCandidates.prefix(entry.host == "world.openfoodfacts.org" ? 2 : 1) {
                        do {
                            if let product = try await fetchOpenFacts(host: entry.host, code: code, on: req) {
                                return (OpenFactsHit(product: product, source: entry.source), errored, index)
                            }
                        } catch { errored = true }
                    }
                    return (nil, errored, index)
                }
            }
            var all: [(hit: OpenFactsHit?, errored: Bool, order: Int)] = []
            for await r in group { all.append((r.0, r.1, r.2)) }
            return all
        }
        if let best = results.filter({ $0.hit != nil }).min(by: { $0.order < $1.order })?.hit { return best }
        if results.contains(where: \.errored) { throw SupplementLookupError.upstreamUnavailable }
        return nil
    }

    private static func fetchOpenFacts(host: String, code: String, on req: Request) async throws -> OFFProduct? {
        let uri = URI(string: "https://\(host)/api/v2/product/\(code).json")
        var headers = HTTPHeaders()
        headers.add(name: .userAgent, value: "TempoApp/1.0 (support@tempo.app)")
        let response = try await req.client.get(uri, headers: headers)
        // Open*Facts answers 404 + status 0 for an unknown barcode.
        if response.status == .notFound { return nil }
        guard response.status == .ok else {
            req.logger.warning("\(host) HTTP \(response.status.code) for \(code)")
            throw SupplementLookupError.upstreamUnavailable
        }
        let decoded = try response.content.decode(OFFResponse.self, using: JSONDecoder())
        guard decoded.status == 1, let product = decoded.product else { return nil }
        return product
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    // MARK: - Merge

    /// Internal (not private) so AppTests can exercise the real field-mapping
    /// logic from fixture JSON (decode → merge → assert) without any live
    /// network call. DSLD wins for dose / servings / ingredients / certs; the
    /// Open*Facts product fills what DSLD lacks (whey protein, macros).
    static func merge(upc: String, off: OFFProduct?, dsld: DSLDLabel?, offSource: String = "openfoodfacts") -> SupplementLookupDTO {
        let brand = dsld?.brandName ?? off?.firstBrand
        let name = dsld?.fullName ?? off?.name ?? "Unknown product"
        let kind = SupplementKindGuesser.guess(
            name: name,
            categories: off?.categories,
            dsldProductType: dsld?.productType?.langualCodeDescription
        )

        let dosePerServing = dsld?.doseDescription ?? off?.servingSize
        let servingsPerContainer = dsld?.servingsPerContainer ?? dsld?.derivedServingsPerContainer ?? off?.derivedServingsPerContainer
        let proteinGramsPerServing = dsld?.proteinGramsPerServing ?? off?.nutriments?.proteinsServing

        var certifications = Set<String>()
        certifications.formUnion(SupplementCertificationScanner.scan(off?.ingredientsText))
        certifications.formUnion(SupplementCertificationScanner.scan(off?.labelsTags?.joined(separator: " ")))
        if let statements = dsld?.statements {
            for statement in statements {
                certifications.formUnion(SupplementCertificationScanner.scan(statement.notes))
            }
        }

        return SupplementLookupDTO(
            upc: upc,
            brand: brand,
            name: name,
            kind: kind.rawValue,
            dosePerServing: dosePerServing,
            servingsPerContainer: servingsPerContainer,
            proteinGramsPerServing: proteinGramsPerServing,
            caloriesPerServing: dsld?.caloriesPerServing ?? off?.nutriments?.energyKcalServing,
            carbsGramsPerServing: dsld?.gramsPerServing(named: ["total carbohydrate", "total carbohydrates", "carbohydrate", "carbohydrates"]) ?? off?.nutriments?.carbohydratesServing,
            fatGramsPerServing: dsld?.gramsPerServing(named: ["total fat"]) ?? off?.nutriments?.fatServing,
            certifications: Array(certifications).sorted(),
            source: dsld != nil ? "dsld" : offSource,
            ingredients: dsld?.ingredientSummaries
        )
    }
}

// MARK: - Timeout helper

func withTimeout<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw SupplementLookupError.timeout
        }
        guard let result = try await group.next() else {
            throw SupplementLookupError.timeout
        }
        group.cancelAll()
        return result
    }
}

// MARK: - Kind guessing

enum SupplementKindGuesser {
    static func guess(name: String, categories: String?, dsldProductType: String?) -> SupplementKindGuess {
        // The label's own name beats the database category: DSLD files whey
        // under "Multi-Vitamin and Mineral" more often than you would think.
        let byName = classify(name)
        if byName != .other { return byName }
        let byCategory = classify([categories ?? "", dsldProductType ?? ""].joined(separator: " "))
        return byCategory
    }

    private static func classify(_ text: String) -> SupplementKindGuess {
        let haystack = text.lowercased()
        if haystack.contains("creatine") {
            return .creatine
        }
        if haystack.contains("omega") || haystack.contains("fish oil") || haystack.contains("krill") {
            return .omega3
        }
        if haystack.contains("multivitamin") || haystack.contains("multi-vitamin") || haystack.contains("multi vitamin") {
            return .multivitamin
        }
        if haystack.contains("electrolyte") || haystack.contains("hydration") {
            return .electrolytes
        }
        if haystack.contains("pre-workout") || haystack.contains("preworkout") || haystack.contains("pre workout") {
            return .preworkout
        }
        if haystack.contains("protein") || haystack.contains("whey") || haystack.contains("casein") {
            return .protein
        }
        let minerals = ["magnesium", "zinc", "calcium", "iron", "potassium", "selenium", "biotin", "folate", "b12", "b-12", "vitamin", "mineral"]
        if minerals.contains(where: { haystack.contains($0) }) {
            return .vitamin
        }
        return .other
    }
}

/// Mirrors the iOS `SupplementKind` raw values without depending on the iOS
/// target — the backend only ever needs the raw string.
enum SupplementKindGuess: String {
    case protein, creatine, omega3, multivitamin, vitamin, preworkout, electrolytes, other
}

// MARK: - Certification scanning

enum SupplementCertificationScanner {
    private static let knownCertifications = [
        "NSF Certified for Sport",
        "NSF Contents Certified",
        "Informed Sport",
        "Informed Choice",
        "USP Verified",
    ]

    static func scan(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        let lower = text.lowercased()
        return knownCertifications.filter { lower.contains($0.lowercased()) }
    }
}

// MARK: - Open Food Facts wire DTOs

struct OFFResponse: Content {
    let status: Int
    let product: OFFProduct?
}

struct OFFProduct: Content {
    let productName: String?
    let genericName: String?
    let brands: String?
    let categories: String?
    let ingredientsText: String?
    let servingSize: String?
    let quantity: String?
    let labelsTags: [String]?
    let nutriments: OFFNutriments?

    init(from decoder: Decoder) throws {
        // Open*Facts is user-edited: a field typed wrong must not sink the product.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productName = try? c.decodeIfPresent(String.self, forKey: .productName)
        genericName = try? c.decodeIfPresent(String.self, forKey: .genericName)
        brands = try? c.decodeIfPresent(String.self, forKey: .brands)
        categories = try? c.decodeIfPresent(String.self, forKey: .categories)
        ingredientsText = try? c.decodeIfPresent(String.self, forKey: .ingredientsText)
        servingSize = try? c.decodeIfPresent(String.self, forKey: .servingSize)
        quantity = (try? c.decodeIfPresent(String.self, forKey: .quantity))
            ?? c.flexDouble(.quantity).map { String($0) }
        labelsTags = try? c.decodeIfPresent([String].self, forKey: .labelsTags)
        nutriments = try? c.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
    }

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
        case categories
        case ingredientsText = "ingredients_text"
        case servingSize = "serving_size"
        case quantity
        case labelsTags = "labels_tags"
        case nutriments
    }

    var name: String {
        let candidate = productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty {
            return candidate
        }
        return genericName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown product"
    }

    var firstBrand: String? {
        brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Best-effort: OFF rarely reports servings directly. When `quantity`
    /// ("1.47 lb", "669 g") and `serving_size` ("30.4 g") are both numeric
    /// in the same unit family, servings ≈ quantity / serving size.
    var derivedServingsPerContainer: Double? {
        guard let quantityGrams = Self.parseGrams(quantity), let servingGrams = Self.parseGrams(servingSize), servingGrams > 0 else {
            return nil
        }
        let servings = (quantityGrams / servingGrams).rounded()
        return servings > 0 ? servings : nil
    }

    /// Grams from a label amount. Only a number directly followed by a mass
    /// unit counts ("60 g", "1.2kg", "2 x 30 g" → 30, "500 mg" → 0.5);
    /// "2 gummies" or "1 scoop" give nil. The old check glued every digit
    /// together and accepted any "g" in the text, so "2 gummies" read as 2 g
    /// and "2 x 30 g" as 230 g.
    /// "1,000" → "1000" (comma + exactly three digits after 1–3 leading
    /// digits is a thousands separator); "30,4" and "0,500" stay decimals.
    static func normalizedNumber(_ token: String) -> String {
        let parts = token.split(separator: ",", omittingEmptySubsequences: false)
        if parts.count == 2, parts[1].count == 3, parts[0].count <= 3, parts[0] != "0", !parts[0].contains(".") {
            return String(parts[0]) + String(parts[1])
        }
        return token.replacingOccurrences(of: ",", with: ".")
    }

    static func parseGrams(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let lower = raw.lowercased()
        let pattern = #"(?<![\w.])(\d+(?:[.,]\d+)?)\s*(kg|mg|grams?|gr|g|lbs?|oz)(?![a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numberRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let value = Double(Self.normalizedNumber(String(lower[numberRange])))
        else {
            return nil
        }
        switch lower[unitRange] {
        case "kg": return value * 1000
        case "mg": return value / 1000
        case "lb", "lbs": return value * 453.592
        case "oz": return value * 28.3495
        default: return value
        }
    }
}

struct OFFNutriments: Content {
    let proteinsServing: Double?
    let energyKcalServing: Double?
    let carbohydratesServing: Double?
    let fatServing: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proteinsServing = c.flexDouble(.proteinsServing)
        energyKcalServing = c.flexDouble(.energyKcalServing)
        carbohydratesServing = c.flexDouble(.carbohydratesServing)
        fatServing = c.flexDouble(.fatServing)
    }

    enum CodingKeys: String, CodingKey {
        case proteinsServing = "proteins_serving"
        case energyKcalServing = "energy-kcal_serving"
        case carbohydratesServing = "carbohydrates_serving"
        case fatServing = "fat_serving"
    }
}

// MARK: - DSLD wire DTOs

struct DSLDSearchResponse: Content {
    let hits: [Hit]

    struct Hit: Content {
        let id: String
        let source: Source?

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case source = "_source"
        }
    }

    struct Source: Content {
        let brandName: String?
        let fullName: String?
        let offMarket: Int?
        let productType: DSLDProductType?
        let netContents: [DSLDNetContent]?
    }
}

/// DSLD sends numbers as numbers on some labels and as strings ("74") on
/// others; a strict Double decode made whole labels vanish.
extension KeyedDecodingContainer {
    func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

struct DSLDNetContent: Content {
    let quantity: Double?
    let unit: String?
    let display: String?

    enum CodingKeys: String, CodingKey { case quantity, unit, display }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quantity = c.flexDouble(.quantity)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        display = try? c.decodeIfPresent(String.self, forKey: .display)
    }
}

struct DSLDLabel: Content {
    let brandName: String?
    let fullName: String?
    let upcSku: String?
    let offMarket: Int?
    let entryDate: String?
    let productType: DSLDProductType?
    let servingsPerContainer: Double?
    let netContents: [DSLDNetContent]?
    let servingSizes: [DSLDServingSize]?
    let ingredientRows: [DSLDIngredientRow]?
    let statements: [DSLDStatement]?

    enum CodingKeys: String, CodingKey {
        case brandName, fullName, upcSku, offMarket, entryDate, productType, servingsPerContainer
        case netContents, servingSizes, ingredientRows, statements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brandName = try? c.decodeIfPresent(String.self, forKey: .brandName)
        fullName = try? c.decodeIfPresent(String.self, forKey: .fullName)
        upcSku = try? c.decodeIfPresent(String.self, forKey: .upcSku)
        offMarket = c.flexDouble(.offMarket).map { Int($0) }
        entryDate = try? c.decodeIfPresent(String.self, forKey: .entryDate)
        productType = try? c.decodeIfPresent(DSLDProductType.self, forKey: .productType)
        servingsPerContainer = c.flexDouble(.servingsPerContainer)
        netContents = try? c.decodeIfPresent([DSLDNetContent].self, forKey: .netContents)
        servingSizes = try? c.decodeIfPresent([DSLDServingSize].self, forKey: .servingSizes)
        ingredientRows = try? c.decodeIfPresent([DSLDIngredientRow].self, forKey: .ingredientRows)
        statements = try? c.decodeIfPresent([DSLDStatement].self, forKey: .statements)
    }

    /// "1 Scoop (30.4 g)" / "2 softgels" from the first serving-size entry.
    /// DSLD has no single flat "dose" field, and `notes` is often "".
    var doseDescription: String? {
        guard let first = servingSizes?.first else { return nil }
        let unit = Self.cleanUnit(first.unit)
        var amount: String?
        if let q = first.minQuantity {
            let n = q == q.rounded() ? String(Int(q)) : String(q)
            amount = [n, unit].compactMap { $0 }.joined(separator: " ")
        }
        var note = first.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = note, n.hasPrefix("("), n.hasSuffix(")") { note = String(n.dropFirst().dropLast()) }
        switch (amount, note) {
        case let (amount?, note?) where !note.isEmpty:
            // A full phrase ("1 scoop (30.4 g)") stands alone; a bare "1 Scoop"
            // reads better next to the amount: "30.4 g (1 Scoop)".
            if note.contains("(") || note.count > 14 { return note }
            return "\(amount) (\(note))"
        case let (amount?, _):
            return amount
        case let (nil, note?) where !note.isEmpty:
            return note
        default:
            return nil
        }
    }

    /// Servings in the container when DSLD leaves `servingsPerContainer`
    /// empty: net contents in the serving's own unit ÷ amount per serving
    /// ("90 Softgels" ÷ "2 Softgels" = 45).
    var derivedServingsPerContainer: Double? {
        guard let serving = servingSizes?.first, let per = serving.minQuantity, per > 0,
              let unit = Self.cleanUnit(serving.unit)?.lowercased(),
              let net = netContents?.first(where: { Self.cleanUnit($0.unit)?.lowercased() == unit }),
              let total = net.quantity, total > 0
        else { return nil }
        let servings = (total / per).rounded(.down)
        return servings >= 1 ? servings : nil
    }

    /// "Gram(s)" → "g", "Softgel(s)" → "softgel".
    static func cleanUnit(_ raw: String?) -> String? {
        guard var u = raw?.trimmingCharacters(in: .whitespaces), !u.isEmpty else { return nil }
        u = u.replacingOccurrences(of: "(s)", with: "")
        switch u.lowercased() {
        case "gram": return "g"
        case "milligram": return "mg"
        case "microgram", "mcg": return "mcg"
        case "kg": return "kg"
        default: return u
        }
    }

    /// Protein per serving. DSLD has no flat field: a "Protein" row (by name
    /// or category), else the "24 grams of protein per serving" claim some
    /// labels carry in their statements.
    var proteinGramsPerServing: Double? {
        if let rows = ingredientRows {
            let proteinRows = rows.filter {
                let name = $0.name?.lowercased() ?? ""
                return name == "protein" || name == "total protein" || $0.category?.lowercased() == "protein"
            }
            let grams = proteinRows.compactMap { row -> Double? in
                guard let quantity = row.quantity?.first else { return nil }
                return Self.toGrams(quantity.quantity, unit: quantity.unit)
            }
            if !grams.isEmpty { return grams.reduce(0, +) }
        }
        let text = (statements ?? []).compactMap(\.notes).joined(separator: " ")
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:g|grams?)\s+of\s+(?:high[- ]quality\s+)?protein"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text)
        {
            return Double(text[r])
        }
        return nil
    }

    /// Calories per serving from a DSLD "Calories" ingredient row.
    var caloriesPerServing: Double? {
        guard let row = ingredientRows?.first(where: { $0.name?.lowercased() == "calories" }),
              let quantity = row.quantity?.first?.quantity
        else {
            return nil
        }
        return quantity
    }

    /// Grams of the first ingredient row whose name equals one of `names`
    /// (case-insensitive) — e.g. "Total Fat", "Total Carbohydrates".
    func gramsPerServing(named names: [String]) -> Double? {
        guard let row = ingredientRows?.first(where: { names.contains($0.name?.lowercased() ?? "") }),
              let quantity = row.quantity?.first
        else {
            return nil
        }
        return Self.toGrams(quantity.quantity, unit: quantity.unit)
    }

    private static let macroRowNames: Set<String> = [
        "calories", "total fat", "cholesterol", "sodium", "total carbohydrate", "total carbohydrates",
        "protein", "total protein", "total sugars", "dietary fiber",
    ]

    /// "Vitamin D3 25 mcg" lines for the actives (macro rows excluded), capped.
    var ingredientSummaries: [String]? {
        guard let rows = ingredientRows else { return nil }
        let lines: [String] = rows.compactMap { row in
            guard let name = row.name, !name.isEmpty, !Self.macroRowNames.contains(name.lowercased()) else { return nil }
            guard let q = row.quantity?.first, let value = q.quantity, value > 0 else { return name }
            let n = value == value.rounded() ? String(Int(value)) : String(value)
            let unit = Self.cleanUnit(q.unit) ?? ""
            return "\(name) \(n) \(unit)".trimmingCharacters(in: .whitespaces)
        }
        let capped = Array(lines.prefix(30))
        return capped.isEmpty ? nil : capped
    }

    private static func toGrams(_ value: Double?, unit: String?) -> Double? {
        guard let value else { return nil }
        switch unit?.lowercased() {
        case "mg", "milligram(s)": return value / 1000
        case "g", "gram(s)": return value
        default: return nil
        }
    }
}

struct DSLDProductType: Content {
    let langualCodeDescription: String?
}

struct DSLDServingSize: Content {
    let minQuantity: Double?
    let unit: String?
    let notes: String?

    enum CodingKeys: String, CodingKey { case minQuantity, unit, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minQuantity = c.flexDouble(.minQuantity)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct DSLDIngredientRow: Content {
    let name: String?
    let category: String?
    let quantity: [DSLDQuantity]?
}

struct DSLDQuantity: Content {
    let quantity: Double?
    let unit: String?

    enum CodingKeys: String, CodingKey { case quantity, unit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quantity = c.flexDouble(.quantity)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
    }
}

struct DSLDStatement: Content {
    let type: String?
    let notes: String?
}
