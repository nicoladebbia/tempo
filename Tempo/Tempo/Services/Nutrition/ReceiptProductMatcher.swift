//
// ReceiptProductMatcher.swift
// Tempo
//
// Layer 5 of the receipt pipeline — sits ABOVE ReceiptItemResolver, not
// instead of it. The resolver turns raw OCR ("PUB GRK YOG 0%") into a
// readable name + canonical food name deterministically, with no network
// call. This file tries to go one step further: find the EXACT Open Food
// Facts product behind that readable name (barcode, photo, Nutri-Score),
// and — separately — infer the package SIZE when the receipt printed none
// (receipts usually show a price, not "32 oz").
//
// Both halves are best-effort and conservative: `findExactMatch` returns
// nil rather than force a wrong barcode onto a food-level item, and
// `ReceiptSizeInference.infer` returns an empty array rather than invent a
// size with no evidence. Callers keep working at "food-level" confidence
// when either comes back empty — that's the expected, common case.
//

import Foundation

// MARK: - ReceiptProductCandidate

struct ReceiptProductCandidate: Sendable {
    /// The matched Open Food Facts product — barcode, name, brand, image,
    /// Nutri-Score/NOVA all come along for free via the existing type.
    let product: FoodProduct
    /// 0...1 confidence that this is the right product.
    let matchScore: Double
    /// Where the package size on `product` (if any) should be considered to
    /// have come from, for the caller's UI/telemetry.
    let sizeSource: String
}

// MARK: - ReceiptProductMatcher

enum ReceiptProductMatcher {
    /// Session-scoped negative-and-positive cache, keyed by (store chain,
    /// raw receipt text). Confirmed exact matches already persist long-term
    /// via the crowd/local alias layers (ReceiptItemResolver.learn); this
    /// cache only avoids re-querying OFF for the SAME receipt line within
    /// one review session.
    private static let cache = ReceiptProductMatchCache()

    /// Finds the single best Open Food Facts product for a resolved receipt
    /// line, or nil when nothing is confident enough (caller stays at
    /// "food-level" — never a forced wrong exact match).
    ///
    /// Known limitation: `FoodProductProviding.search(_:limit:)` has no
    /// country parameter, so a US store chain (`storeChain` — "publix",
    /// "walmart", "target", "costco", "trader_joes", "whole_foods", "aldi",
    /// …) can't be enforced server-side here without editing
    /// OpenFoodFactsClient (owned by a different workstream). Deliberately
    /// NOT compensated for with a local post-filter on category/text: OFF's
    /// coverage of US products is thin enough that a wrong-country guess
    /// would throw away more correct matches than it would catch bad ones.
    /// `storeChain` is accepted for API symmetry with the caller's data and
    /// for the cache key, not used to filter results.
    static func findExactMatch(
        readableName: String,
        matchedBrand: String?,
        rawText: String,
        sizeValue: Double?,
        sizeUnit: String?,
        paidPrice: Double,
        storeChain: String?,
        provider: any FoodProductProviding,
        threshold: Double = 0.6
    ) async throws -> ReceiptProductCandidate? {
        let cacheKey = "\(storeChain?.lowercased() ?? "")|\(rawText.lowercased())"
        if let cached = await cache.cached(cacheKey) {
            return cached
        }

        let queries = searchQueries(readableName: readableName, matchedBrand: matchedBrand)
        guard !queries.isEmpty else {
            await cache.store(cacheKey, value: nil)
            return nil
        }

        var seenIDs = Set<String>()
        var pool: [FoodProduct] = []
        for query in queries {
            let hits = try await provider.search(query, limit: 8)
            for hit in hits where seenIDs.insert(hit.id).inserted {
                pool.append(hit)
            }
        }

        let ranked = pool
            .map { product in
                (product: product, score: compositeScore(
                    product: product,
                    readableName: readableName,
                    matchedBrand: matchedBrand,
                    sizeValue: sizeValue,
                    sizeUnit: sizeUnit
                ))
            }
            .sorted { $0.score > $1.score }

        guard let best = ranked.first, best.score >= threshold else {
            await cache.store(cacheKey, value: nil)
            return nil
        }

        let sizeSource = if sizeValue != nil, sizeUnit != nil {
            "printed_on_receipt"
        } else if best.product.quantityLabel != nil {
            "off_quantity_label"
        } else {
            "unknown"
        }
        let candidate = ReceiptProductCandidate(product: best.product, matchScore: best.score, sizeSource: sizeSource)
        await cache.store(cacheKey, value: candidate)
        return candidate
    }

    // MARK: - Query building

    /// Primary query: brand + name as the resolver already formats
    /// `readableName` ("Publix" + "Greek Yogurt 0%"). Fallback query: name
    /// alone, in case OFF's index doesn't carry the store's own brand
    /// wording. The resolver PREPENDS `matchedBrand` into `readableName`
    /// (see ReceiptItemResolver.expandDictionary), so it's stripped back
    /// out first to avoid "Publix Publix Greek Yogurt" in the query.
    static func searchQueries(readableName: String, matchedBrand: String?) -> [String] {
        let trimmedName = readableName.trimmingCharacters(in: .whitespaces)
        guard let matchedBrand, !matchedBrand.trimmingCharacters(in: .whitespaces).isEmpty else {
            return trimmedName.isEmpty ? [] : [trimmedName]
        }

        let strippedName = stripLeadingBrand(trimmedName, brand: matchedBrand)
        let withBrand = [matchedBrand, strippedName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var queries: [String] = []
        var seen = Set<String>()
        func add(_ query: String) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else {
                return
            }
            queries.append(trimmed)
        }
        add(withBrand)
        add(strippedName)
        return queries
    }

    /// Strips a leading brand (matched as whole, case-insensitive tokens)
    /// off the front of a name. Returns the name unchanged if it doesn't
    /// actually start with the brand.
    static func stripLeadingBrand(_ name: String, brand: String) -> String {
        let brandTokens = brand.split(separator: " ").map { $0.lowercased() }
        let nameTokens = name.split(separator: " ")
        guard !brandTokens.isEmpty, nameTokens.count >= brandTokens.count else {
            return name
        }
        let prefix = nameTokens.prefix(brandTokens.count).map { $0.lowercased() }
        guard prefix == brandTokens else {
            return name
        }
        return nameTokens.dropFirst(brandTokens.count).joined(separator: " ")
    }

    // MARK: - Ranking

    /// (a) name token overlap 0.5, (b) brand match 0.25, (c) size match 0.25.
    static func compositeScore(
        product: FoodProduct,
        readableName: String,
        matchedBrand: String?,
        sizeValue: Double?,
        sizeUnit: String?
    ) -> Double {
        let nameScore = jaccard(tokenize(readableName), tokenize(product.displayName))
        let brand = brandScore(matchedBrand: matchedBrand, candidateBrand: product.brand)
        let size = sizeScore(candidateLabel: product.quantityLabel, sizeValue: sizeValue, sizeUnit: sizeUnit)
        return 0.5 * nameScore + 0.25 * brand + 0.25 * size
    }

    static func tokenize(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else {
            return 0
        }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    /// nil `matchedBrand` (receipt line had no detected brand) is neutral —
    /// we simply don't know, so it shouldn't drag a good name match down.
    /// A `matchedBrand` present but the candidate has no brand at all is
    /// scored low: we asked a specific question and got no evidence either way.
    static func brandScore(matchedBrand: String?, candidateBrand: String?) -> Double {
        guard let matchedBrand, !matchedBrand.trimmingCharacters(in: .whitespaces).isEmpty else {
            return 0.5
        }
        guard let candidateBrand, !candidateBrand.trimmingCharacters(in: .whitespaces).isEmpty else {
            return 0.0
        }
        let a = matchedBrand.lowercased()
        let b = candidateBrand.lowercased()
        return (a == b || a.contains(b) || b.contains(a)) ? 1.0 : 0.0
    }

    /// Unknown on either side (no printed size, or OFF has no quantity
    /// label) is neutral — don't penalize what we can't compare. A close
    /// size match scores high, a clear mismatch scores low.
    static func sizeScore(candidateLabel: String?, sizeValue: Double?, sizeUnit: String?) -> Double {
        guard let sizeValue, let sizeUnit,
              let requestedGrams = ReceiptSizeMath.gramsEquivalent(value: sizeValue, unit: sizeUnit), requestedGrams > 0
        else {
            return 0.5
        }
        guard let candidateLabel, let candidateGrams = ReceiptSizeMath.gramsEquivalent(fromLabel: candidateLabel) else {
            return 0.5
        }
        let diff = abs(candidateGrams - requestedGrams) / requestedGrams
        switch diff {
        case ..<0.05: return 1.0
        case ..<0.15: return 0.8
        case ..<0.30: return 0.4
        default: return 0.0
        }
    }
}

// MARK: - ReceiptProductMatchCache

/// Simple session-scoped cache (no persistence — confirmed exact matches
/// are persisted long-term elsewhere, via the crowd/local alias layers).
/// Caches negative results too, so a repeated miss for the same line
/// doesn't re-query OFF every time within a review session.
private actor ReceiptProductMatchCache {
    private var storage: [String: ReceiptProductCandidate?] = [:]

    /// Outer optional: whether this key has been queried before. Inner
    /// optional: the result of that query (nil = confirmed miss).
    func cached(_ key: String) -> ReceiptProductCandidate?? {
        storage[key]
    }

    func store(_ key: String, value: ReceiptProductCandidate?) {
        storage[key] = value
    }

    func reset() {
        storage.removeAll()
    }
}

extension ReceiptProductMatcher {
    /// Test-only: clears the session cache so one test's fake provider
    /// results can't leak into the next test via a shared cache key.
    static func resetCacheForTesting() async {
        await cache.reset()
    }
}

// MARK: - ReceiptSizeCandidate

struct ReceiptSizeCandidate: Sendable {
    let sizeValue: Double
    let sizeUnit: String
    let packCount: Int?
    /// 0...1.
    let confidence: Double
    /// User-facing label, e.g. "32 oz".
    let label: String
}

// MARK: - ReceiptSizeInference

/// Infers a receipt line's package size when the receipt printed none —
/// this whole feature was explicitly scoped as cuttable, in this exact
/// priority order:
///   (a) family + size match from the bundled BrandCatalogSeed — a cheap
///       deterministic win when the receipt DID print a size.
///   (b) price-based inference — no size printed, so rank the family's
///       known sizes by how close their expected price (seeded
///       cents-per-gram × size) lands to what was actually paid.
///   (c) NOT implemented here on purpose: the review-screen size picker UI,
///       a backend refresh job, and crowd-learning of sizes are owned by
///       other workstreams. This type only produces candidates.
enum ReceiptSizeInference {
    static func infer(
        canonicalFoodName: String,
        paidPrice: Double,
        familyCandidates: [BrandCatalogSeedEntry],
        storeChain: String?,
        printedSizeValue: Double? = nil,
        printedSizeUnit: String? = nil
    ) -> [ReceiptSizeCandidate] {
        guard !familyCandidates.isEmpty else {
            return []
        }

        // (a) The receipt DID print a size: find the catalog entry that
        // matches it and return it at full confidence — no need to guess
        // from price when the answer is already on the receipt.
        if let printedSizeValue, let printedSizeUnit,
           let printedGrams = ReceiptSizeMath.gramsEquivalent(value: printedSizeValue, unit: printedSizeUnit), printedGrams > 0
        {
            if let match = familyCandidates.first(where: { entry in
                guard let entryGrams = ReceiptSizeMath.gramsEquivalent(value: entry.sizeValue, unit: entry.sizeUnit) else {
                    return false
                }
                return abs(entryGrams - printedGrams) / printedGrams < 0.05
            }) {
                return [candidate(for: match, confidence: 1.0)]
            }
        }

        // (b) No printed size (or it didn't match anything in the family):
        // rank the family's known sizes by expected price.
        guard let dollarsPerGram = typicalPricePerGram(canonicalFoodName: canonicalFoodName) else {
            return []
        }

        let scored: [(entry: BrandCatalogSeedEntry, expected: Double, confidence: Double)] = familyCandidates.compactMap { entry in
            guard let unitGrams = ReceiptSizeMath.gramsEquivalent(value: entry.sizeValue, unit: entry.sizeUnit) else {
                return nil
            }
            let totalGrams = unitGrams * Double(entry.packCount ?? 1)
            let expected = totalGrams * dollarsPerGram
            guard expected > 0 else {
                return nil
            }
            let confidence = max(0, 1 - min(1, abs(expected - paidPrice) / expected))
            return (entry, expected, confidence)
        }
        .sorted { $0.confidence > $1.confidence }

        guard let best = scored.first else {
            return []
        }

        var results = [candidate(for: best.entry, confidence: best.confidence)]

        // "When two sizes are close in price, keep both as candidates"
        // rather than picking one arbitrarily.
        if scored.count > 1 {
            let runnerUp = scored[1]
            let relativeDiff = abs(best.expected - runnerUp.expected) / best.expected
            if relativeDiff <= 0.15 {
                results.append(candidate(for: runnerUp.entry, confidence: runnerUp.confidence))
            }
        }
        return results
    }

    private static func candidate(for entry: BrandCatalogSeedEntry, confidence: Double) -> ReceiptSizeCandidate {
        ReceiptSizeCandidate(
            sizeValue: entry.sizeValue,
            sizeUnit: entry.sizeUnit,
            packCount: entry.packCount,
            confidence: confidence,
            label: sizeLabel(value: entry.sizeValue, unit: entry.sizeUnit, packCount: entry.packCount)
        )
    }

    private static func sizeLabel(value: Double, unit: String, packCount: Int?) -> String {
        let formattedValue = value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
        let base = "\(formattedValue) \(unit)"
        guard let packCount, packCount > 1 else {
            return base
        }
        return "\(packCount)-pack of \(base)"
    }

    /// Rough, honestly-approximate 2026 US price-per-gram by broad category
    /// — NOT store-specific, NOT current-pricing-accurate. Only used to
    /// RANK candidate sizes against each other by which expected price is
    /// closest to what was paid, not to produce an absolute price estimate.
    private static let categoryPricePerGram: [(keywords: [String], dollarsPerGram: Double)] = [
        (["yogurt", "milk", "cheese", "butter", "cream", "dairy"], 0.007),
        (["banana", "apple", "orange", "lettuce", "tomato", "onion", "potato", "berries", "produce", "fruit", "vegetable"], 0.004),
        (["chicken", "beef", "pork", "turkey", "salmon", "shrimp", "meat", "fish"], 0.018),
        (["rice", "pasta", "flour", "sugar", "oats", "bean", "nut", "almond", "cereal", "bread", "peanut butter"], 0.011),
        (["oil", "olive oil"], 0.015),
        (["soda", "juice", "water", "coffee", "tea", "cola", "beverage"], 0.002),
    ]

    private static func typicalPricePerGram(canonicalFoodName: String) -> Double? {
        let name = canonicalFoodName.lowercased()
        return categoryPricePerGram.first { entry in entry.keywords.contains { name.contains($0) } }?.dollarsPerGram
    }
}

// MARK: - ReceiptSizeMath

/// Shared size-string parsing for both `ReceiptProductMatcher` (comparing
/// OFF's `quantityLabel` against a printed receipt size) and
/// `ReceiptSizeInference` (comparing catalog-seed sizes against each
/// other). Normalizes everything to a "grams-equivalent" basis, treating
/// 1 mL ≈ 1 g for liquids — the same rough approximation
/// `PantryUnit.gramsApprox` already uses elsewhere in the app.
enum ReceiptSizeMath {
    static func gramsEquivalent(value: Double, unit: String) -> Double? {
        let normalized = unit
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
        switch normalized {
        case "g",
             "gram",
             "grams": return value
        case "kg",
             "kilogram",
             "kilograms": return value * 1000
        case "mg",
             "milligram",
             "milligrams": return value / 1000
        case "oz",
             "ounce",
             "ounces",
             "floz",
             "fl oz",
             "fluid ounce",
             "fluid ounces": return value * 28.3495
        case "lb",
             "lbs",
             "pound",
             "pounds": return value * 453.592
        case "ml",
             "milliliter",
             "milliliters",
             "millilitre",
             "millilitres": return value
        case "cl",
             "centiliter",
             "centiliters": return value * 10
        case "l",
             "liter",
             "liters",
             "litre",
             "litres": return value * 1000
        case "gal",
             "gallon",
             "gallons": return value * 3785.41
        default: return nil
        }
    }

    /// Parses a free-text size label ("500 g", "1 L", "32 fl oz",
    /// "6 x 33 cl") into a grams-equivalent value. Best-effort — an
    /// unparseable label returns nil rather than a wrong guess.
    static func gramsEquivalent(fromLabel rawLabel: String) -> Double? {
        let text = rawLabel.lowercased().replacingOccurrences(of: ",", with: ".")
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        // Multipack: "6 x 33 cl", "4x125g".
        if let match = firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(fl\.?\s?oz|[a-z]+)"#),
           let count = Double(match.groups[0]),
           let amount = Double(match.groups[1]),
           let perUnit = gramsEquivalent(value: amount, unit: match.groups[2])
        {
            return count * perUnit
        }

        if let match = firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(fl\.?\s?oz|[a-z]+)"#),
           let value = Double(match.groups[0])
        {
            return gramsEquivalent(value: value, unit: match.groups[1])
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> (full: String, groups: [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var groups: [String] = []
        for i in 1 ..< match.numberOfRanges {
            let range = match.range(at: i)
            groups.append(range.location != NSNotFound ? ns.substring(with: range) : "")
        }
        return (ns.substring(with: match.range), groups)
    }
}

// MARK: - BrandCatalogSeedEntry

/// One (brand, size) row from the bundled BrandCatalogSeed.json — an
/// offline fallback for size inference when OFF has nothing useful, or the
/// exact-match search itself is unavailable (offline review).
struct BrandCatalogSeedEntry: Codable, Sendable {
    let brand: String
    let chain: String
    /// Groups rows into a product family across sizes, e.g.
    /// "publix-greek-yogurt-nonfat-plain".
    let familyKey: String
    let name: String
    let sizeValue: Double
    let sizeUnit: String
    let packCount: Int?
    let barcode: String?
}

// MARK: - BrandCatalogSeed

/// Bundled BrandCatalogSeed.json, loaded once and grouped by `familyKey`.
enum BrandCatalogSeed {
    static let all: [BrandCatalogSeedEntry] = load()
    static let byFamilyKey: [String: [BrandCatalogSeedEntry]] = Dictionary(grouping: all, by: \.familyKey)

    static func familyCandidates(forFamilyKey familyKey: String) -> [BrandCatalogSeedEntry] {
        byFamilyKey[familyKey] ?? []
    }

    private static func load() -> [BrandCatalogSeedEntry] {
        // NOTE: despite living at Resources/Receipt/BrandCatalogSeed.json in
        // the repo, Xcode's resource copy phase flattens `path:`-sourced
        // folders to the bundle root (verified against the built app — see
        // FoodAdditives.json, loaded the same way with no `subdirectory:`).
        guard let url = Bundle.main.url(forResource: "BrandCatalogSeed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BrandCatalogSeedEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }
}
