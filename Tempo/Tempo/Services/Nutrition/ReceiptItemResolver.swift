//
// ReceiptItemResolver.swift
// Tempo
//
// Cheapest, fastest layer of the receipt line-item resolver. Raw OCR/Claude-
// structured receipt text ("PUB GRK YOG 0%", "DKB WHL GRN SD BRD") is heavily
// abbreviated and unreadable at a glance. This resolver turns it into a
// human-facing READABLE name that keeps brand + product distinctiveness
// ("Publix Greek Yogurt 0%"), unlike FoodCanonicalizer.canonicalize(_:) which
// does the OPPOSITE job — stripping brand down to a bare pantry-matching
// category name ("greek yogurt"). This file still calls FoodCanonicalizer to
// populate the canonical field, but its own abbreviation dictionary and
// expansion logic are separate and must not be conflated with
// FoodCanonicalizer's ocrAbbreviations/brandWords.
//
// Three resolution layers, cheapest first:
//   1. Learned alias (SwiftData `ReceiptItemAlias`) — a correction the user
//      made once for this exact (store chain, raw text) pair. Wins outright.
//   2. Deterministic dictionary expansion — ReceiptAbbreviations.json +
//      ReceiptStoreBrandPrefixes.json, bundled data, no network/AI call.
//   3. Fallback — best-effort titlecased raw text when neither above layer
//      recognizes anything.
//

import Foundation
import SwiftData

// MARK: - ReceiptResolutionConfidence

enum ReceiptResolutionConfidence: String, Sendable {
    /// Resolved via a user-confirmed learned alias — as good as it gets.
    case exactProduct
    /// Resolved via dictionary expansion — a readable name, but not a
    /// user-verified exact product match.
    case foodLevel
    /// Neither layer recognized anything; best-effort titlecase of raw text.
    case unknown
}

// MARK: - ReceiptResolvedItem

struct ReceiptResolvedItem: Sendable, Equatable {
    /// Human-facing name — brand + product kept distinct, e.g.
    /// "Publix Greek Yogurt 0%" from "PUB GRK YOG 0%".
    let readableName: String
    /// Output of FoodCanonicalizer.canonicalize(_:) — bare pantry-matching
    /// category name, e.g. "greek yogurt".
    let canonicalFoodName: String
    let confidence: ReceiptResolutionConfidence
    /// Display brand name if a store-brand prefix token matched
    /// (e.g. "Publix", "GreenWise", "Kirkland Signature").
    let matchedBrand: String?
    /// Parsed package size value, e.g. 16 from "16OZ". Nil for
    /// weight-priced lines (see ReceiptItemResolver.parseSize).
    let sizeValue: Double?
    /// Parsed package size unit, e.g. "oz", "l", "gal". Nil when sizeValue
    /// is nil.
    let sizeUnit: String?
    /// Parsed pack/count multiplier, e.g. 6 from "6PK", 12 from "12CT".
    let packCount: Int?
    /// "learned_alias" | "dictionary" | "fallback".
    let source: String
}

// MARK: - ReceiptSizeInfo

/// Internal parse result before it's folded into `ReceiptResolvedItem`.
private struct ReceiptSizeInfo: Sendable, Equatable {
    let sizeValue: Double?
    let sizeUnit: String?
    let packCount: Int?
}

// MARK: - ReceiptItemResolver

@MainActor
enum ReceiptItemResolver {
    // MARK: Public entry point

    /// Resolves a raw receipt line to a readable name, trying the learned
    /// alias first, then dictionary expansion, then a titlecased fallback.
    static func resolve(rawText: String, storeChain: String?, in context: ModelContext) -> ReceiptResolvedItem {
        let chain = normalizedChain(storeChain)
        let normalized = normalize(rawText)
        let size = parseSize(rawText)

        if let alias = lookupAlias(normalizedRawText: normalized, storeChain: chain, in: context) {
            return ReceiptResolvedItem(
                readableName: alias.readableName,
                canonicalFoodName: alias.canonicalFoodName,
                confidence: .exactProduct,
                matchedBrand: nil,
                sizeValue: size.sizeValue,
                sizeUnit: size.sizeUnit,
                packCount: size.packCount,
                source: "learned_alias"
            )
        }

        if let expansion = expandDictionary(rawText: rawText, storeChain: chain) {
            return ReceiptResolvedItem(
                readableName: expansion.readableName,
                canonicalFoodName: FoodCanonicalizer.canonicalize(expansion.readableName),
                confidence: .foodLevel,
                matchedBrand: expansion.matchedBrand,
                sizeValue: size.sizeValue,
                sizeUnit: size.sizeUnit,
                packCount: size.packCount,
                source: "dictionary"
            )
        }

        return ReceiptResolvedItem(
            readableName: fallbackTitleCase(rawText),
            canonicalFoodName: FoodCanonicalizer.canonicalize(rawText),
            confidence: .unknown,
            matchedBrand: nil,
            sizeValue: size.sizeValue,
            sizeUnit: size.sizeUnit,
            packCount: size.packCount,
            source: "fallback"
        )
    }

    // MARK: Learned alias (layer 2 storage)

    /// Upserts a learned alias for (storeChain, rawText). Called by the
    /// review UI when the user corrects a line item. Bumps `confirmCount`
    /// when the same correction is confirmed again.
    @discardableResult
    static func learn(
        rawText: String,
        storeChain: String?,
        readableName: String,
        canonicalFoodName: String,
        barcode: String? = nil,
        in context: ModelContext
    ) -> ReceiptItemAlias {
        let chain = normalizedChain(storeChain)
        let normalized = normalize(rawText)

        if let existing = lookupAlias(normalizedRawText: normalized, storeChain: chain, in: context) {
            existing.readableName = readableName
            existing.canonicalFoodName = canonicalFoodName
            if let barcode {
                existing.barcode = barcode
            }
            existing.confirmCount += 1
            existing.updatedAt = Date()
            try? context.save()
            return existing
        }

        let alias = ReceiptItemAlias(
            storeChain: chain,
            normalizedRawText: normalized,
            readableName: readableName,
            canonicalFoodName: canonicalFoodName,
            barcode: barcode
        )
        context.insert(alias)
        try? context.save()
        return alias
    }

    private static func lookupAlias(
        normalizedRawText: String,
        storeChain: String,
        in context: ModelContext
    ) -> ReceiptItemAlias? {
        let descriptor = FetchDescriptor<ReceiptItemAlias>(
            predicate: #Predicate { alias in
                alias.normalizedRawText == normalizedRawText && alias.storeChain == storeChain
            }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: Normalization (shared by lookup + learn — must always agree)

    /// Lowercased, whitespace-collapsed, punctuation-stripped. Both the
    /// alias lookup and `learn(...)` MUST use this so a correction made
    /// once matches every later OCR pass of the same logical item, even if
    /// whitespace or casing differs slightly.
    static func normalize(_ rawText: String) -> String {
        let lowered = rawText.lowercased()
        let punctuationStripped = lowered.replacingOccurrences(
            of: #"[^a-z0-9\s]"#,
            with: "",
            options: .regularExpression
        )
        let collapsed = punctuationStripped.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    private static func normalizedChain(_ storeChain: String?) -> String {
        let trimmed = storeChain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    // MARK: Dictionary expansion (layer 1)

    private struct DictionaryExpansion {
        let readableName: String
        let matchedBrand: String?
    }

    /// Longest-match token expansion over ReceiptAbbreviations.json, with a
    /// leading store-brand prefix (ReceiptStoreBrandPrefixes.json) detected
    /// and stripped first. Returns nil when nothing in the text was
    /// recognized (no brand, no abbreviation token) — the caller then falls
    /// back to a plain titlecase.
    private static func expandDictionary(rawText: String, storeChain: String) -> DictionaryExpansion? {
        let rawTokens = rawText.split(separator: " ").map(String.init)
        guard !rawTokens.isEmpty else {
            return nil
        }

        let (matchedBrand, remainder) = detectAndStripBrandPrefix(tokens: rawTokens, storeChain: storeChain)
        let tokens = remainder

        var outputWords: [String] = []
        var matchedAnyAbbreviation = matchedBrand != nil

        for token in tokens {
            let key = dictionaryKey(for: token)
            if let expansion = dictionaryEntry(for: key) {
                matchedAnyAbbreviation = true
                if !expansion.isEmpty {
                    outputWords.append(expansion)
                }
                // Empty expansion (e.g. "EA") means: drop this token entirely.
            } else {
                outputWords.append(formatPassthroughToken(token))
            }
        }

        guard matchedAnyAbbreviation else {
            return nil
        }

        var finalWords = outputWords
        if let matchedBrand {
            finalWords.insert(matchedBrand, at: 0)
        }

        let readable = finalWords.joined(separator: " ")
        guard !readable.isEmpty else {
            return nil
        }
        return DictionaryExpansion(readableName: readable, matchedBrand: matchedBrand)
    }

    /// Detects a leading store-brand prefix (one or more tokens, matched
    /// case-insensitively as WHOLE tokens — never a substring) and strips
    /// it from the front. Tries the tokens as printed first (so a numeric
    /// brand token like "365" for Whole Foods matches directly); only if
    /// that fails AND the very first token is pure digits (e.g. a Costco
    /// item number ahead of "KS") does it retry once with that token
    /// dropped, so an item number never blocks brand detection.
    private static func detectAndStripBrandPrefix(
        tokens: [String],
        storeChain: String
    ) -> (matchedBrand: String?, remainder: [String]) {
        if let direct = matchBrandPrefix(tokens: tokens, storeChain: storeChain) {
            return direct
        }

        if let first = tokens.first, !first.isEmpty, first.allSatisfy(\.isNumber), tokens.count > 1 {
            let withoutLeadingNumber = Array(tokens.dropFirst())
            if let retried = matchBrandPrefix(tokens: withoutLeadingNumber, storeChain: storeChain) {
                return retried
            }
        }

        return (nil, tokens)
    }

    /// Matches a brand prefix at the very front of `tokens`, or nil if none
    /// does. "GW" is special-cased per storeChain since it means Great
    /// Value on a Walmart receipt but GreenWise on a Publix receipt — see
    /// ReceiptStoreBrandPrefixes.json's `note` fields.
    private static func matchBrandPrefix(
        tokens: [String],
        storeChain: String
    ) -> (matchedBrand: String?, remainder: [String])? {
        guard let first = tokens.first else {
            return nil
        }

        if first.uppercased() == "GW" {
            let brand = storeChain.contains("walmart") ? "Great Value" : "GreenWise"
            return (brand, Array(tokens.dropFirst()))
        }

        // Longest prefix (most tokens) wins so a 3-token prefix like
        // "GOOD & GATHER" isn't shadowed by a coincidental 1-token match.
        let candidates: [(tokens: [String], displayBrand: String)] = ReceiptStoreBrandPrefixData.shared
            .flatMap { entry in
                entry.prefixes.map { prefix in
                    (prefix.uppercased().split(separator: " ").map(String.init), entry.displayBrand)
                }
            }
            .filter { !$0.tokens.isEmpty }
            .sorted { $0.tokens.count > $1.tokens.count }

        for candidate in candidates {
            guard candidate.tokens.count <= tokens.count else {
                continue
            }
            let slice = tokens.prefix(candidate.tokens.count).map { $0.uppercased() }
            if slice == candidate.tokens {
                return (candidate.displayBrand, Array(tokens.dropFirst(candidate.tokens.count)))
            }
        }

        return nil
    }

    /// Cleans a raw token into a dictionary lookup key: uppercased, trailing
    /// punctuation trimmed. Internal punctuation (e.g. the "/" in "A/B") is
    /// preserved since some dictionary keys use it.
    private static func dictionaryKey(for token: String) -> String {
        token.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
    }

    private static func dictionaryEntry(for key: String) -> String? {
        if let english = ReceiptAbbreviationData.shared.en[key] {
            return english
        }
        return ReceiptAbbreviationData.shared.it[key]
    }

    /// Formats a token that had no dictionary match. Purely numeric /
    /// numeric+unit tokens (e.g. "0%", "1.32LB") are kept close to how
    /// they were printed rather than naively `.capitalized` (which would
    /// turn "1.32LB" into the odd-looking "1.32Lb"). Ordinary words get a
    /// simple titlecase.
    private static func formatPassthroughToken(_ token: String) -> String {
        if token.range(of: #"^[\d.,/%-]+$"#, options: .regularExpression) != nil {
            return token
        }
        if let match = firstMatch(in: token, pattern: #"^(\d+(?:\.\d+)?)([A-Za-z]+)$"#) {
            let number = match.groups[0]
            let unit = match.groups[1].lowercased()
            return number + unit
        }
        guard let firstChar = token.first else {
            return token
        }
        return String(firstChar).uppercased() + token.dropFirst().lowercased()
    }

    private static func fallbackTitleCase(_ rawText: String) -> String {
        rawText
            .split(separator: " ")
            .map { formatPassthroughToken(String($0)) }
            .joined(separator: " ")
    }

    // MARK: Size / unit / pack-count parsing

    /// Scans raw text for package-size and pack-count patterns:
    /// "16OZ"/"16 OZ", "1LT"/"1L"/"1 LT", "1GAL", "6PK"/"6 PK",
    /// "12CT"/"12 CT". A weight-style value with exactly 2 decimal places
    /// followed by LB/OZ with no pack/count context (e.g. "1.32LB") is left
    /// as nil — that's a per-pound weight, handled elsewhere in the
    /// pipeline, not a package size.
    private static func parseSize(_ rawText: String) -> ReceiptSizeInfo {
        let upper = rawText.uppercased()

        var packCount: Int?
        if let match = firstMatch(in: upper, pattern: #"(\d+)\s*(PK|CT)\b"#) {
            packCount = Int(match.groups[0])
        }

        var sizeValue: Double?
        var sizeUnit: String?
        if let match = firstMatch(in: upper, pattern: #"(\d+(?:\.\d+)?)\s*(OZ|LB|GAL|LT|ML|KG|G|L)\b"#) {
            let numberString = match.groups[0]
            let unitRaw = match.groups[1]
            let decimalDigits: Int = if let dotRange = numberString.range(of: ".") {
                numberString.distance(from: dotRange.upperBound, to: numberString.endIndex)
            } else {
                0
            }
            let isWeightUnit = unitRaw == "LB" || unitRaw == "OZ"
            let looksLikeWeight = isWeightUnit && decimalDigits == 2 && packCount == nil
            if !looksLikeWeight, let value = Double(numberString) {
                sizeValue = value
                sizeUnit = normalizedSizeUnit(unitRaw)
            }
        }

        return ReceiptSizeInfo(sizeValue: sizeValue, sizeUnit: sizeUnit, packCount: packCount)
    }

    private static func normalizedSizeUnit(_ raw: String) -> String {
        switch raw {
        case "LT",
             "L": "l"
        case "GAL": "gal"
        case "KG": "kg"
        case "ML": "ml"
        case "G": "g"
        case "OZ": "oz"
        case "LB": "lb"
        default: raw.lowercased()
        }
    }

    // MARK: Regex helper

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

// MARK: - ReceiptStoreBrandPrefixEntry

struct ReceiptStoreBrandPrefixEntry: Decodable, Sendable {
    let chain: String
    let prefixes: [String]
    let displayBrand: String
    let note: String?
}

// MARK: - ReceiptStoreBrandPrefixData

/// Bundled ReceiptStoreBrandPrefixes.json, loaded once.
enum ReceiptStoreBrandPrefixData {
    static let shared: [ReceiptStoreBrandPrefixEntry] = load()

    private static func load() -> [ReceiptStoreBrandPrefixEntry] {
        guard let url = Bundle.main.url(forResource: "ReceiptStoreBrandPrefixes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ReceiptStoreBrandPrefixEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }
}

// MARK: - ReceiptAbbreviationData

/// Bundled ReceiptAbbreviations.json, loaded once. Top-level keys are
/// English abbreviation → expansion; the nested "it" object is a small
/// Italian abbreviation set kept separate so lookups never collide.
enum ReceiptAbbreviationData {
    static let shared: (en: [String: String], it: [String: String]) = load()

    private static func load() -> (en: [String: String], it: [String: String]) {
        guard let url = Bundle.main.url(forResource: "ReceiptAbbreviations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ([:], [:])
        }

        var english: [String: String] = [:]
        var italian: [String: String] = [:]
        for (key, value) in json {
            if key == "it", let nested = value as? [String: String] {
                italian = nested
            } else if let expansion = value as? String {
                english[key] = expansion
            }
        }
        return (english, italian)
    }
}
