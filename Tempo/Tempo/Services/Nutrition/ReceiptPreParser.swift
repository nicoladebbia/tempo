//
// ReceiptPreParser.swift
// Tempo
//
// Deterministic, on-device pre-parse of the row-reconstructed OCR output
// (VisionReceiptOCRResult.rows) BEFORE it's sent to the backend / Claude
// Haiku structuring call. Nothing here calls the network or an LLM — it's
// pure string/regex logic over rows, verified against 3 real, hand-checked
// Publix receipts (see scratchpad ground truth during development).
//
// What this buys us:
//  - Totals (subtotal/tax/total/savings/payment) extracted with certainty
//    from the printed numbers, instead of trusting Haiku to transcribe them
//    correctly every time.
//  - The "Voided Items" section identified and stripped out BEFORE the
//    prompt ever sees it, so a voided item can't accidentally get counted
//    as a purchase (verified: Publix's printed subtotal already excludes
//    voided items entirely).
//  - "You saved: $X" lines and "Promotion  -$X" discount lines attached to
//    the item row above them, since Haiku doesn't always get attribution
//    right when a discount spans two OCR rows.
//  - Weight ("$2.99/lb x 1.64 lb") and multi-qty ("3 @ 6.71", "1 @ 2 for
//    $7.00") continuation lines paired back to the item above, when the
//    item's own row had no price (common — Publix prints those on the
//    NEXT line for weighed/promo items).
//  - A short "DETECTED" hints block appended to the text sent to the
//    prompt, and a machine-checkable result for ReceiptCrossChecker.
//

import Foundation

// MARK: - ReceiptPreParseItemRow

struct ReceiptPreParseItemRow: Sendable, Equatable {
    /// The item's own row text (name [+ tax flag] [+ price if same row]).
    var rawText: String
    /// Price parsed from this row or a continuation row below it.
    var totalPrice: Double?
    /// Publix-style tax flag if detected trailing the row ("F", "T", "FT", "N").
    var taxFlag: String?
    /// "You saved: $X.XX" attached from the row(s) below.
    var youSaved: Double?
    /// Printed sale/quantity note as-is ("$2.99/lb x 1.64 lb", "1 @ 2 for $7.00", "3 @ 6.71").
    var saleNote: String?
    /// A "Promotion  -5.35" style line attached instead of / in addition to youSaved.
    var promotionAdjustment: Double?
    /// True when the row is itself a standalone discount line (e.g. "Promotion -5.35")
    /// rather than a purchasable item — callers should not treat this as a product.
    var isDiscountLine: Bool = false
    /// Heuristic: household/pharmacy/non-grocery keyword matched.
    var nonFoodHint: Bool = false
    /// Heuristic: deposit/bottle/bag fee keyword matched.
    var feeHint: Bool = false
    /// The source row's Vision OCR confidence — used only to pick the
    /// better reading when the same physical line was detected twice
    /// (see the near-duplicate dedup pass in `parse`).
    var confidence: Double = 1.0
}

// MARK: - ReceiptPreParseResult

struct ReceiptPreParseResult: Sendable {
    var subtotalAmount: Double?
    var taxAmount: Double?
    var totalAmount: Double?
    var paymentAmount: Double?
    var paymentMethod: String?
    var savingsAmount: Double?
    /// ISO 4217-ish 3-letter code, best-effort from symbols/keywords. Defaults "USD".
    var currencyCode: String = "USD"
    var isLikelyNonUSLocale: Bool = false
    /// Rows classified as real purchasable items (Voided Items section and
    /// totals/footer rows already excluded).
    var candidateItems: [ReceiptPreParseItemRow] = []
    /// Rows found inside a "Voided Items" section — kept for display/audit,
    /// must NOT be counted as purchases or in totals.
    var voidedItems: [ReceiptPreParseItemRow] = []
    /// Sparse department/category header hints in row order ("PRODUCE", "DELI"...).
    var departmentHints: [String] = []
    /// Best-effort store name from the header block.
    var storeNameGuess: String?
    /// A short human-readable summary block to append to the text sent to
    /// the structuring prompt so Haiku doesn't have to re-derive totals.
    var hintsBlock: String = ""
    /// store|date|total fingerprint for duplicate-scan detection, when a
    /// date and total were both confidently parsed.
    var duplicateKey: String?
}

// MARK: - ReceiptPreParser

enum ReceiptPreParser {
    // MARK: Section / keyword vocabulary

    private static let voidedSectionMarkers = ["voided items", "voided item"]
    private static let subtotalKeywords = ["subtotal", "sub total", "order total", "totale parziale"]
    private static let taxKeywords = ["sales tax", "tax", "iva", "vat"]
    private static let totalKeywords = ["grand total", "total", "totale"]
    private static let paymentKeywords = ["cash", "credit", "debit", "mastercard", "visa", "amex", "payment", "contactless"]
    // NOTE: "you saved" is deliberately NOT in this list. On every real
    // receipt checked (3/3 Publix receipts, hand-verified), "You saved:
    // $X.XX" is a PER-ITEM trailing note, not a standalone aggregate-total
    // line — it's handled by the dedicated per-item attachment block below,
    // which also accumulates into `savingsAmount` by summing (verified:
    // summing every per-item "you saved" + "Promotion" note reproduces the
    // receipt's printed total-savings line exactly on all 3 receipts). If
    // "you saved" were also matched here, this check runs FIRST in the loop
    // and would swallow every such line as a one-off aggregate (keeping only
    // the LAST value via `max`, dropping the rest) — the per-item attach
    // block below would then never run, silently losing every per-item
    // savings note. Caught by a failing unit test before this ever shipped.
    private static let savingsKeywords = ["savings", "your savings", "special price savings"]
    private static let youSavedPrefix = "you saved"
    private static let promotionKeyword = "promotion"
    private static let footerStopMarkers = [
        "thank you",
        "club publix",
        "terms & conditions",
        "publix super markets",
        "receipt id",
        "www.",
        ".com",
        // Payment/card detail block — these lines were leaking through as
        // spurious candidate items on real receipts (Auth/Trace, Reference,
        // EMV AID, card network/entry-method lines all sit between the
        // "SAVINGS" banner and the true footer boilerplate, none of which
        // the markers above catch).
        "auth/trace",
        "reference:",
        "debit mastercard",
        "credit card",
        "entry method",
        "a0000000",
    ]

    private static let nonFoodKeywords = [
        "downy", "dawn ", "tide", "gain ", "bounty", "charmin", "clorox", "lysol",
        "candle", "batteries", "gift card", "lottery", "detergent", "soap",
        "shampoo", "toothpaste", "vitamin", "advil", "tylenol", "bandage",
    ]
    private static let feeKeywords = ["deposit", "bottle deposit", "crv", "bag fee", "carrier bag"]
    private static let localeKeywords = ["totale", "sconto", "reso", "annullo", "iva "]

    // MARK: - Entry point

    static func parse(rows: [VisionReceiptOCRResult.Row], storeHint: String?) -> ReceiptPreParseResult {
        var result = ReceiptPreParseResult()
        guard !rows.isEmpty else {
            return result
        }

        // Row order sanity check — belt-and-suspenders. `VisionReceiptOCR.recognize`
        // already applies `correctRowOrderIfReversed` to its output, so rows
        // reaching here from the normal scan path are already corrected;
        // this catches any other caller that hands `parse` raw rows
        // directly (e.g. a degraded reconstruction from persisted text).
        // See `VisionReceiptOCR.correctRowOrderIfReversed` for why this
        // matters: footer boilerplate landing in the first few rows instead
        // of the last silently discards every real item row further down
        // (confirmed on a real receipt: subtotal/tax/total still matched
        // via keyword search, but only 1 of 29 items survived).
        let rows = VisionReceiptOCR.correctRowOrderIfReversed(rows)

        // Currency / locale detection over the whole text first.
        let fullText = rows.map(\.text).joined(separator: "\n")
        result.currencyCode = detectCurrency(fullText)
        result.isLikelyNonUSLocale = result.currencyCode != "USD"
            || localeKeywords.contains { fullText.lowercased().contains($0) }
            || fullText.range(of: #"\b\d{1,2}/\d{1,2}/\d{4}\b"#, options: .regularExpression) == nil
            && fullText.range(of: #"\b\d{1,2}[.-]\d{1,2}[.-]\d{4}\b"#, options: .regularExpression) != nil

        result.storeNameGuess = storeHint ?? guessStoreName(rows: rows)

        // Find the "Voided Items" section boundary, if present, so its rows
        // are excluded from the candidate item list entirely.
        let voidedStartIndex = rows.firstIndex { row in
            let lower = row.text.lowercased()
            return voidedSectionMarkers.contains { lower.contains($0) }
        }
        // Footer/legal boilerplate starts here — also excluded.
        let footerStartIndex = rows.firstIndex { row in
            let lower = row.text.lowercased()
            return footerStopMarkers.contains { lower.contains($0) }
        }

        var pendingDepartment: String?
        var items: [ReceiptPreParseItemRow] = []
        var voided: [ReceiptPreParseItemRow] = []
        var i = 0
        while i < rows.count {
            let row = rows[i]
            let lower = row.text.lowercased()
            let inVoidedSection = voidedStartIndex.map { i > $0 } ?? false
            let pastFooter = footerStartIndex.map { i >= $0 } ?? false

            // Totals block — parse regardless of section, these are single facts.
            if let value = matchedAmount(in: row.text, keywords: subtotalKeywords) {
                result.subtotalAmount = value
                i += 1; continue
            }
            if let value = matchedAmount(in: row.text, keywords: taxKeywords) {
                result.taxAmount = value
                i += 1; continue
            }
            if let value = matchedAmount(in: row.text, keywords: totalKeywords), !lower.contains("subtotal") {
                result.totalAmount = value
                i += 1; continue
            }
            if let value = matchedAmount(in: row.text, keywords: paymentKeywords) {
                result.paymentAmount = value
                result.paymentMethod = result.paymentMethod ?? bestPaymentMethodGuess(lower)
                i += 1; continue
            }
            if let value = matchedAmount(in: row.text, keywords: savingsKeywords) {
                result.savingsAmount = max(result.savingsAmount ?? 0, value)
                i += 1; continue
            }
            if lower.contains(voidedSectionMarkers[0]) {
                i += 1; continue // the "Voided Items" header row itself
            }
            // "Change    6.68" — the summary block's change-due line, not a
            // product. "cash"/"credit"/"debit" above already catch the rest
            // of that block; this one slipped through as a false item since
            // "change" isn't in paymentKeywords (deliberately, to keep
            // paymentAmount meaning "what was tendered", not the change).
            if lower.hasPrefix("change") {
                i += 1; continue
            }
            if pastFooter {
                i += 1; continue
            }
            // Store header block (address/phone/manager line) — only
            // before the first real item has been found, since these
            // phrases never legitimately recur mid-receipt. Confirmed as a
            // real false-item source on all 3 real receipts (street
            // address, city/state/zip, phone number, and "Store Manager:"
            // lines all had no price and no other exclusion rule).
            if items.isEmpty, isLikelyStoreHeaderLine(row.text) {
                i += 1; continue
            }
            // Row 0 only — see isLikelyBareStoreNameLine's doc comment.
            if i == 0, items.isEmpty,
               isLikelyBareStoreNameLine(row.text, nextRowText: rows.indices.contains(i + 1) ? rows[i + 1].text : nil)
            {
                i += 1; continue
            }

            // "You saved: $X" — attach to the previous item. Also accumulate
            // into the running total-savings figure (summed, not maxed) —
            // voided items don't count since they were never purchased.
            // Matched on "saved" alone (not the full "you saved" phrase):
            // OCR regularly misreads the leading "You" as "fou", "Vou", or
            // drops it to "ou" (confirmed on 2 real receipts), and a
            // standalone "saved: $X.XX" line is never anything else on a
            // Publix receipt.
            if lower.hasPrefix(youSavedPrefix) || lower.contains("you saved") || lower.contains("saved") {
                if let value = firstAmount(in: row.text) {
                    if inVoidedSection {
                        if !voided.isEmpty {
                            voided[voided.count - 1].youSaved = value
                        }
                    } else if !items.isEmpty {
                        items[items.count - 1].youSaved = value
                        result.savingsAmount = (result.savingsAmount ?? 0) + value
                    }
                }
                i += 1; continue
            }

            // "Promotion  -5.35" — a standalone discount line. Attaches its
            // adjustment to the item immediately above (for display) AND is
            // itself appended as its own `isDiscountLine`-flagged row — the
            // truth data for receipt r3 confirms a printed "Promotion" line
            // is a real row the store itself prints as one of its N listed
            // lines (subtotal reconciles only when it's included), so
            // dropping it entirely mis-modeled the receipt rather than
            // fixing an over-count. Also rolls into the running
            // total-savings figure, same as "You saved".
            if lower.hasPrefix(promotionKeyword) {
                if let value = firstAmount(in: row.text) {
                    let magnitude = abs(value)
                    if !items.isEmpty {
                        items[items.count - 1].promotionAdjustment = magnitude
                        if !inVoidedSection {
                            result.savingsAmount = (result.savingsAmount ?? 0) + magnitude
                        }
                    }
                    var discountRow = ReceiptPreParseItemRow(rawText: row.text, totalPrice: -magnitude)
                    discountRow.isDiscountLine = true
                    discountRow.confidence = row.confidence
                    if inVoidedSection {
                        voided.append(discountRow)
                    } else {
                        items.append(discountRow)
                    }
                }
                i += 1; continue
            }

            // Department header: short, ALL CAPS, no digits, no $ sign, not a
            // known section/footer keyword. Used only as a category hint.
            // BUT: a bare weighed-item name ("BANANAS", "AVOCADO") looks
            // identical to the loose single-all-caps-token fallback below —
            // if the VERY NEXT row is a weight/qty continuation line, this
            // is that item's name, not a department header. Caught by a
            // failing unit test before this ever hit a real receipt: without
            // this guard, single-word weighed items were silently dropped
            // (classified as a department hint, never added as a candidate
            // item, so their continuation-line price had nothing to attach
            // to and was discarded entirely).
            let nextIsContinuation = (i + 1 < rows.count) && isContinuationLine(rows[i + 1].text)
            if isLikelyDepartmentHeader(row.text), !nextIsContinuation {
                pendingDepartment = row.text.trimmingCharacters(in: .whitespaces)
                result.departmentHints.append(pendingDepartment!)
                i += 1; continue
            }

            // Continuation-only rows (weight/qty lines with no leading item
            // name of their own) attach to the PREVIOUS row when that row
            // had no price yet. Matched on shape alone (not requiring a
            // parseable price too) and ALWAYS consumed here — a continuation
            // line whose price regex happens to fail (OCR noise) must still
            // never fall through to the generic item bucket below, or it
            // becomes a spurious candidate item with a garbled name and no
            // real price (a confirmed over-count source on real receipts).
            if isContinuationLine(row.text) {
                if let price = firstAmount(in: row.text, requireDollarOrTrailing: true) {
                    if inVoidedSection {
                        if !voided.isEmpty, voided[voided.count - 1].totalPrice == nil {
                            voided[voided.count - 1].totalPrice = price
                            voided[voided.count - 1].saleNote = row.text.trimmingCharacters(in: .whitespaces)
                        }
                    } else if !items.isEmpty, items[items.count - 1].totalPrice == nil {
                        items[items.count - 1].totalPrice = price
                        items[items.count - 1].saleNote = row.text.trimmingCharacters(in: .whitespaces)
                    }
                }
                i += 1; continue
            }

            // A row with no letters at all (just digits/currency/punctuation)
            // is never a real item on its own — it's almost always a price
            // fragment split off during row reconstruction (confirmed as a
            // false-item source on real receipts: bare "5.15", "150.00"
            // rows). Any legitimate bare-number line (weight/qty
            // continuations) was already consumed by `isContinuationLine`
            // above, so anything reaching here with no letters is noise.
            if !row.text.contains(where: \.isLetter) {
                i += 1; continue
            }

            // Otherwise: a normal item row. Extract price (if on this row)
            // and tax flag from the trailing tokens.
            var itemRow = ReceiptPreParseItemRow(rawText: row.text)
            itemRow.totalPrice = firstAmount(in: row.text)
            itemRow.taxFlag = detectTaxFlag(row.text)
            itemRow.nonFoodHint = nonFoodKeywords.contains { lower.contains($0) }
            itemRow.feeHint = feeKeywords.contains { lower.contains($0) }
            itemRow.confidence = row.confidence
            if inVoidedSection {
                voided.append(itemRow)
            } else {
                items.append(itemRow)
            }
            i += 1
        }

        result.candidateItems = Self.dedupeNearDuplicateReadings(items)
        result.voidedItems = voided
        result.hintsBlock = buildHintsBlock(result)
        result.duplicateKey = buildDuplicateKey(store: result.storeNameGuess, total: result.totalAmount, fullText: fullText)
        return result
    }

    // MARK: - Near-duplicate dedup

    /// Row reconstruction can occasionally emit the SAME physical receipt
    /// line twice with different OCR garbling (e.g. Vision reads a partly
    /// shadowed line once cleanly and once as noise from an overlapping
    /// text box). Confirmed on real receipts: "Hazelnuts...5.99" also
    /// appearing as "HazP nUTS 5.99". Both copies carry the same printed
    /// price and highly overlapping letters, so: when two candidate items
    /// share an exact non-nil `totalPrice` AND their lowercase-letters-only
    /// text is a strong match (Jaccard over character bigrams), keep only
    /// the higher-OCR-confidence reading and drop the other as a duplicate
    /// rather than a second, false item.
    /// Only rows within this many positions of each other are considered —
    /// a genuine duplicate OCR reading of one physical text box lands
    /// immediately adjacent in the row list (Vision emits both boxes back
    /// to back). Without this window, two DIFFERENT items that merely
    /// happen to share a common price point (very common: $2.99, $4.99…)
    /// and a few overlapping words could be wrongly collapsed into one,
    /// silently dropping a real purchased item — the opposite failure mode
    /// from the over-counting bug this round set out to fix, and worse
    /// (silent data loss vs. a visible extra row). Code-review finding,
    /// round 2.
    private static let nearDuplicateWindow = 3

    private static func dedupeNearDuplicateReadings(_ rows: [ReceiptPreParseItemRow]) -> [ReceiptPreParseItemRow] {
        guard rows.count > 1 else {
            return rows
        }
        var dropped = Set<Int>()
        for i in 0 ..< rows.count {
            if dropped.contains(i) {
                continue
            }
            guard let priceI = rows[i].totalPrice else {
                continue
            }
            for j in (i + 1) ..< min(i + 1 + nearDuplicateWindow, rows.count) {
                if dropped.contains(j) {
                    continue
                }
                guard let priceJ = rows[j].totalPrice, abs(priceI - priceJ) < 0.005 else {
                    continue
                }
                guard letterBigramSimilarity(rows[i].rawText, rows[j].rawText) >= 0.5 else {
                    continue
                }
                // Same price, similar text -> near-duplicate OCR reading of
                // one physical line. Drop the lower-confidence copy.
                if rows[i].confidence >= rows[j].confidence {
                    dropped.insert(j)
                } else {
                    dropped.insert(i)
                }
            }
        }
        guard !dropped.isEmpty else {
            return rows
        }
        return rows.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
    }

    /// Character-bigram Jaccard similarity over lowercase-letters-only text
    /// (digits/punctuation/spacing stripped so OCR noise in those positions
    /// doesn't affect the score). Cheap and order-sensitive enough to avoid
    /// matching two genuinely different short item names that merely share
    /// a few letters.
    /// Not private: reused by `ReceiptMultiPhotoStitcher` to detect
    /// near-duplicate row re-reads at the seam between two shots of the
    /// same long receipt.
    static func letterBigramSimilarity(_ a: String, _ b: String) -> Double {
        func bigrams(_ s: String) -> Set<String> {
            let letters = Array(s.lowercased().filter(\.isLetter))
            guard letters.count >= 2 else {
                return letters.isEmpty ? [] : [String(letters)]
            }
            var result = Set<String>()
            for i in 0 ..< (letters.count - 1) {
                result.insert(String(letters[i ... i + 1]))
            }
            return result
        }
        let ba = bigrams(a)
        let bb = bigrams(b)
        if ba.isEmpty || bb.isEmpty {
            return ba == bb ? 1.0 : 0.0
        }
        let intersection = ba.intersection(bb).count
        let union = ba.union(bb).count
        guard union > 0 else {
            return 0
        }
        return Double(intersection) / Double(union)
    }

    // MARK: - Amount parsing

    /// Matches `$1,234.56` / `1234.56` / `1.234,56` (EU) / `1,234.56`. Also
    /// tolerates OCR digit confusions minimally (no correction here — that's
    /// the structuring model's job for genuinely ambiguous digits; this only
    /// needs to find a plausible amount token).
    private static func firstAmount(in text: String, requireDollarOrTrailing: Bool = false) -> Double? {
        let pattern = #"[-]?[\$€£]?\s?\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else {
            return nil
        }
        var token = ns.substring(with: last.range)
        let isNegative = token.contains("-")
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "$€£- "))
        // Normalize EU comma-decimal ("1.234,56" or "2,49") to a Double.
        if token.contains(","), token.contains(".") {
            // Whichever separator appears LAST is the decimal separator.
            if token.lastIndex(of: ",")! > token.lastIndex(of: ".")! {
                token = token.replacingOccurrences(of: ".", with: "")
                token = token.replacingOccurrences(of: ",", with: ".")
            } else {
                token = token.replacingOccurrences(of: ",", with: "")
            }
        } else if token.contains(","), !token.contains(".") {
            token = token.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(token) else {
            return nil
        }
        return isNegative ? -value : value
    }

    private static func matchedAmount(in text: String, keywords: [String]) -> Double? {
        let lower = text.lowercased()
        guard keywords.contains(where: { lower.contains($0) }) else {
            return nil
        }
        return firstAmount(in: text)
    }

    private static func detectCurrency(_ text: String) -> String {
        if text.contains("€") {
            return "EUR"
        }
        if text.contains("£") {
            return "GBP"
        }
        if text.contains("$") {
            return "USD"
        }
        return "USD"
    }

    // MARK: - Row classification helpers

    private static func isLikelyDepartmentHeader(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2, trimmed.count < 24 else {
            return false
        }
        guard trimmed == trimmed.uppercased() else {
            return false
        }
        guard trimmed.range(of: #"\d"#, options: .regularExpression) == nil else {
            return false
        }
        guard !trimmed.contains("$"), !trimmed.contains("*") else {
            return false
        }
        let known = ["PRODUCE", "DELI", "BAKERY", "MEAT", "SEAFOOD", "DAIRY", "FROZEN", "GROCERY", "PHARMACY", "FLORAL", "HBC"]
        return known.contains(trimmed) || (trimmed.split(separator: " ").count == 1 && trimmed.count < 12)
    }

    /// Store address/phone/manager block lines — confirmed false-item
    /// sources on all 3 real receipts ("1100 6th St", "Miami Beach, FL
    /// 33139-6312", "(305) 535-2212", "Store Manager: Anthony Padilla").
    /// Only ever meaningful before the first real item, so callers should
    /// gate this on `items.isEmpty`.
    private static func isLikelyStoreHeaderLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("store manager") {
            return true
        }
        // Phone: "(305) 535-2212", "305-535-2212", or a bare "(305)".
        if text.range(of: #"\(?\d{3}\)?[\s.-]?\d{3}[\s.-]\d{4}"#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"^\(\d{3}\)\s*$"#, options: .regularExpression) != nil {
            return true
        }
        // Street address: "1100 6th St", "1100 Gth St" (OCR misread of "6th").
        if text.range(
            of: #"^\d{1,6}\s+\S+\s+(St|Street|Ave|Avenue|Blvd|Rd|Dr|Way|Ct|Hwy)\.?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        // "Miami Beach, FL 33139-6312" / "Miami Beach. FL 33139"
        if text.range(of: #"[,.]\s*[A-Za-z]{2}\s*\d{5}"#, options: .regularExpression) != nil {
            return true
        }
        // Store cross-street nickname, e.g. "Fifth & Alton" (some Publix
        // branches are named by their intersection rather than a street
        // address). Matched on genuine Title Case words only (each word
        // capitalized, rest lowercase) so it never catches an all-caps
        // abbreviated item name that happens to contain "&" (e.g.
        // "Dwny Sht Lav & Van" — a real truth item on receipt r3).
        if text.range(
            of: #"^[A-Z][a-z]+\s*&\s*[A-Z][a-z]+$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }

    /// Bare store name/logo line — the VERY FIRST row of the receipt only
    /// ("Publix.", "Target", "Walmart"): a short word/phrase, letters only,
    /// no digits, no price, no continuation line following it (so it can't
    /// be an item whose price is on the next row). Deliberately NOT part of
    /// `isLikelyStoreHeaderLine` (which is shape-based and would just as
    /// happily match a department header like "PRODUCE" or a single-word
    /// item like "BANANAS" wherever they occur) — restricted to `i == 0` at
    /// the call site instead, which a department header or item name is
    /// never at on a real receipt (something always prints above them).
    /// Confirmed false-item source on r1: a bare "Publix." row at index 0
    /// slipped through every other filter and became item #1, which then
    /// disabled the `items.isEmpty`-gated header-line filter for every
    /// genuine header line that followed it (the real address/phone/
    /// manager block right after it).
    ///
    /// Excludes ALL-CAPS text deliberately: a store's printed logo line is
    /// virtually always Title Case ("Publix.", "Target"), while a bare
    /// ALL-CAPS word at row 0 is indistinguishable from — and in practice
    /// usually IS — a department header ("PRODUCE") or single-word item
    /// name, which this helper must not swallow (confirmed regression:
    /// `test_departmentHeader_collectedAsHint_notAsItem` uses "PRODUCE" as
    /// its first row).
    private static func isLikelyBareStoreNameLine(_ text: String, nextRowText: String?) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z' ]{0,23}[.,]?$"#, options: .regularExpression) != nil else {
            return false
        }
        guard trimmed.split(separator: " ").count <= 2 else {
            return false
        }
        guard trimmed != trimmed.uppercased() else {
            return false
        }
        if let nextRowText, isContinuationLine(nextRowText) {
            return false
        }
        return true
    }

    /// A row like "$2.99/lb x 1.64 lb" or "1 @ 2 for $7.00" or "3 @ 6.71"
    /// that continues the PREVIOUS item rather than naming a new one.
    /// `[l1]b` throughout matches "lb" OR Vision's very common OCR misread
    /// of it as "1b" (lowercase L -> digit 1) — confirmed on 2 real
    /// receipts ("$2.99/1b x 1.64 lb"). Similarly `[il1]` in the qty
    /// position tolerates "1" being misread as "i"/"l" ("i @ 2 for $7.19").
    private static func isContinuationLine(_ text: String) -> Bool {
        let patterns = [
            #"^\s*\$?\d+(\.\d+)?\s*/\s*[l1]b\s*x\s*\d"#, // "$2.99/lb x 1.64 lb" (or "/1b")
            #"^\s*\d+(\.\d+)?\s*[l1]b\s*@\s*\$?\d"#, // "2.36 lb @ 2.99/lb"
            #"^\s*[il\d]+\s*@\s*\d"#, // "3 @ 6.71" / "1 @ 2 for $7.00" / "i @ 2 for $7.19"
            #"^\s*\d+(\.\d+)?\s*[l1]b\s*@"#,
            #"^\s*\$?\d+[.,]\d{2}\s*x\s*\d+\b"#, // "$7.49 x 3" / "$7,49 x 3" multi-buy unit price
        ]
        let lower = text.lowercased()
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    /// Trailing "F" / "T" / "FT" / "N" Publix-style tax flag token.
    private static func detectTaxFlag(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: #"\b(FT|F|T|N)\b\s*$"#, options: .regularExpression) else {
            return nil
        }
        return String(trimmed[match]).trimmingCharacters(in: .whitespaces)
    }

    private static func bestPaymentMethodGuess(_ lower: String) -> String? {
        if lower.contains("mastercard") {
            return "MasterCard"
        }
        if lower.contains("visa") {
            return "Visa"
        }
        if lower.contains("amex") {
            return "Amex"
        }
        if lower.contains("cash") {
            return "Cash"
        }
        if lower.contains("debit") {
            return "Debit"
        }
        if lower.contains("credit") {
            return "Credit"
        }
        return nil
    }

    private static func guessStoreName(rows: [VisionReceiptOCRResult.Row]) -> String? {
        // Heuristic: first row with letters, no digits, reasonably short —
        // almost always the store's logo/name line at the very top.
        for row in rows.prefix(3) {
            let trimmed = row.text.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 1, trimmed.count < 30, trimmed.range(of: #"\d"#, options: .regularExpression) == nil {
                return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".®"))
            }
        }
        return nil
    }

    // MARK: - Hints block (fed to the structuring prompt)

    private static func buildHintsBlock(_ result: ReceiptPreParseResult) -> String {
        var lines = ["DETECTED (from deterministic on-device pre-parse — prefer these over your own re-reading when present):"]
        if let s = result.subtotalAmount {
            lines.append("- subtotal: \(s)")
        }
        if let t = result.taxAmount {
            lines.append("- tax: \(t)")
        }
        if let g = result.totalAmount {
            lines.append("- total: \(g)")
        }
        if let sv = result.savingsAmount {
            lines.append("- total savings: \(sv)")
        }
        if !result.voidedItems.isEmpty {
            let names = result.voidedItems.map(\.rawText).joined(separator: "; ")
            lines.append("- VOIDED items (already excluded below — do NOT re-add these as line items): \(names)")
        }
        if !result.departmentHints.isEmpty {
            lines.append("- department headers seen: \(result.departmentHints.joined(separator: ", "))")
        }
        if result.isLikelyNonUSLocale {
            lines.append("- likely non-US locale, currency=\(result.currencyCode)")
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    private static func buildDuplicateKey(store: String?, total: Double?, fullText: String) -> String? {
        guard let total else {
            return nil
        }
        // Prefer an explicit date if we can find one; else fall back to just
        // store+total (weaker, but still catches the common "scanned the
        // same receipt twice in a row" case within the same session).
        let datePattern = #"\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b"#
        let dateToken = fullText.range(of: datePattern, options: .regularExpression).map { String(fullText[$0]) }
        let storeKey = (store ?? "unknown").lowercased().trimmingCharacters(in: .whitespaces)
        let totalKey = String(format: "%.2f", total)
        return [storeKey, dateToken ?? "", totalKey].joined(separator: "|")
    }
}
