import Foundation
import Vapor

// MARK: - SupplementLookupClient

//
// Barcode → product. Verified against the REAL APIs (Sept 2026 research,
// live calls against both):
//
//   - NIH DSLD (api.ods.od.nih.gov/dsld/v9) does NOT support lookup by
//     barcode/UPC. Its `upcSku` field only appears on the full `/label/{id}`
//     record (not on search results), stored with the label's own spacing
//     ("7 48927 06014 0") — its full-text search tokenizes on whitespace, so
//     a raw scanned barcode gets zero hits unless you already know that
//     spacing. DSLD is a name/brand/ingredient search engine, not a barcode
//     index.
//   - Open Food Facts (world.openfoodfacts.org) IS genuinely keyed by
//     barcode (`GET /api/v2/product/<code>.json`) and — despite being a food
//     database — does carry a meaningful number of supplement products
//     (protein powders especially; multivitamins are sparser).
//
// So the real pipeline is: OFF first (the only one that can actually resolve
// a barcode), then a best-effort DSLD ENRICHMENT pass by product name/brand
// (not by barcode) to pull DSLD's more structured ingredient/dose data when
// available. `source` reports "dsld" when that enrichment matched (DSLD data
// wins for dose/servings/certifications), else "openfoodfacts". This is a
// deliberate correction of the "DSLD first" wire-contract comment, which
// assumed DSLD barcode search existed — it doesn't; this is the version that
// actually resolves a scanned barcode.

protocol SupplementLookupClient: Sendable {
    func lookup(upc: String, on req: Request) async throws -> SupplementLookupDTO?
}

enum SupplementLookupError: Error {
    case timeout
}

struct SupplementLookupAPIClient: SupplementLookupClient {
    private let requestTimeoutSeconds: Double = 8

    func lookup(upc: String, on req: Request) async throws -> SupplementLookupDTO? {
        guard let off = try? await withTimeout(requestTimeoutSeconds, { try await Self.fetchOpenFoodFacts(upc: upc, on: req) }) else {
            return nil
        }

        // Best-effort DSLD enrichment by name+brand. Never blocks the
        // response on failure — a slow/erroring DSLD call just means we
        // return the OFF-only data.
        let dsld = try? await withTimeout(requestTimeoutSeconds) {
            try await Self.fetchDSLDEnrichment(name: off.name, brand: off.firstBrand, on: req)
        }

        return Self.merge(upc: upc, off: off, dsld: dsld)
    }

    // MARK: - Open Food Facts

    private static func fetchOpenFoodFacts(upc: String, on req: Request) async throws -> OFFProduct? {
        let uri = URI(string: "https://world.openfoodfacts.org/api/v2/product/\(upc).json")
        var headers = HTTPHeaders()
        headers.add(name: .userAgent, value: "TempoApp/1.0 (support@tempo.app)")
        let response = try await req.client.get(uri, headers: headers)
        guard response.status == .ok else {
            req.logger.warning("Open Food Facts HTTP \(response.status.code) for upc=\(upc)")
            return nil
        }
        let decoder = JSONDecoder()
        let decoded = try response.content.decode(OFFResponse.self, using: decoder)
        guard decoded.status == 1, let product = decoded.product else {
            return nil
        }
        return product
    }

    // MARK: - DSLD enrichment (by name/brand — NOT by barcode, see doc above)

    private static func fetchDSLDEnrichment(name: String, brand: String?, on req: Request) async throws -> DSLDLabel? {
        guard !name.isEmpty else { return nil }
        var components = ["product_name=\(percentEncode(name))"]
        if let brand, !brand.isEmpty {
            components.append("brand=\(percentEncode(brand))")
        }
        let searchURI = URI(string: "https://api.ods.od.nih.gov/dsld/v9/search-filter?\(components.joined(separator: "&"))")
        let searchResponse = try await req.client.get(searchURI)
        guard searchResponse.status == .ok else {
            return nil
        }
        let searchResult = try searchResponse.content.decode(DSLDSearchResponse.self)
        guard let firstHit = searchResult.hits.first else {
            return nil
        }

        let labelURI = URI(string: "https://api.ods.od.nih.gov/dsld/v9/label/\(firstHit.id)")
        let labelResponse = try await req.client.get(labelURI)
        guard labelResponse.status == .ok else {
            return nil
        }
        return try labelResponse.content.decode(DSLDLabel.self)
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    // MARK: - Merge

    /// Internal (not private) so AppTests can exercise the real field-mapping
    /// logic from fixture JSON (decode → merge → assert) without any live
    /// network call, per the "DSLD/OFF response mapping from fixture JSON"
    /// test requirement.
    static func merge(upc: String, off: OFFProduct, dsld: DSLDLabel?) -> SupplementLookupDTO {
        let brand = dsld?.brandName ?? off.firstBrand
        let name = dsld?.fullName ?? off.name
        let kind = SupplementKindGuesser.guess(
            name: name,
            categories: off.categories,
            dsldProductType: dsld?.productType?.langualCodeDescription
        )

        let dosePerServing = dsld?.doseDescription ?? off.servingSize
        let servingsPerContainer = dsld?.servingsPerContainer ?? off.derivedServingsPerContainer
        let proteinGramsPerServing = dsld?.proteinGramsPerServing ?? off.nutriments?.proteinsServing

        var certifications = Set<String>()
        certifications.formUnion(SupplementCertificationScanner.scan(off.ingredientsText))
        certifications.formUnion(SupplementCertificationScanner.scan(off.labelsTags?.joined(separator: " ")))
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
            certifications: Array(certifications).sorted(),
            source: dsld != nil ? "dsld" : "openfoodfacts"
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
        let haystack = [name, categories ?? "", dsldProductType ?? ""].joined(separator: " ").lowercased()
        if haystack.contains("creatine") {
            return .creatine
        }
        if haystack.contains("omega") || haystack.contains("fish oil") {
            return .omega3
        }
        if haystack.contains("multivitamin") || haystack.contains("multi-vitamin") {
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
        if haystack.contains("vitamin") || haystack.contains("mineral") {
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

    enum CodingKeys: String, CodingKey {
        case proteinsServing = "proteins_serving"
    }
}

// MARK: - DSLD wire DTOs

private struct DSLDSearchResponse: Content {
    let hits: [Hit]

    struct Hit: Content {
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "_id"
        }
    }
}

struct DSLDLabel: Content {
    let brandName: String?
    let fullName: String?
    let productType: DSLDProductType?
    let servingsPerContainer: Double?
    let servingSizes: [DSLDServingSize]?
    let ingredientRows: [DSLDIngredientRow]?
    let statements: [DSLDStatement]?

    /// Human-readable dose, e.g. "30.4 Gram(s) (1 scoop)" from the first
    /// serving size entry. DSLD has no single flat "dose" field.
    var doseDescription: String? {
        guard let first = servingSizes?.first else { return nil }
        return first.notes ?? first.display
    }

    /// Sum of any ingredient row DSLD categorizes as protein, converted to
    /// grams. DSLD has no flat "protein_g" field — this is a best-effort
    /// derivation from `ingredientRows`.
    var proteinGramsPerServing: Double? {
        guard let ingredientRows else { return nil }
        let proteinRows = ingredientRows.filter { $0.category?.lowercased().contains("protein") == true }
        guard !proteinRows.isEmpty else { return nil }
        let grams = proteinRows.compactMap { row -> Double? in
            guard let quantity = row.quantity?.first else { return nil }
            return Self.toGrams(quantity.quantity, unit: quantity.unit)
        }
        guard !grams.isEmpty else { return nil }
        return grams.reduce(0, +)
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

    var display: String? {
        guard let minQuantity, let unit else { return nil }
        return "\(minQuantity) \(unit)"
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
}

struct DSLDStatement: Content {
    let type: String?
    let notes: String?
}
