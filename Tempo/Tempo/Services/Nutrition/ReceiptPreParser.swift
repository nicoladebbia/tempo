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
            if pastFooter {
                i += 1; continue
            }

            // "You saved: $X" — attach to the previous item. Also accumulate
            // into the running total-savings figure (summed, not maxed) —
            // voided items don't count since they were never purchased.
            if lower.hasPrefix(youSavedPrefix) || lower.contains("you saved") {
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

            // "Promotion  -5.35" — a standalone discount line, attach to the
            // item(s) immediately above and don't treat as a product. Also
            // rolls into the running total-savings figure, same as above.
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
            // had no price yet.
            if isContinuationLine(row.text), let price = firstAmount(in: row.text, requireDollarOrTrailing: true) {
                if inVoidedSection {
                    if !voided.isEmpty, voided[voided.count - 1].totalPrice == nil {
                        voided[voided.count - 1].totalPrice = price
                        voided[voided.count - 1].saleNote = row.text.trimmingCharacters(in: .whitespaces)
                    }
                } else if !items.isEmpty, items[items.count - 1].totalPrice == nil {
                    items[items.count - 1].totalPrice = price
                    items[items.count - 1].saleNote = row.text.trimmingCharacters(in: .whitespaces)
                }
                i += 1; continue
            }

            // Otherwise: a normal item row. Extract price (if on this row)
            // and tax flag from the trailing tokens.
            var itemRow = ReceiptPreParseItemRow(rawText: row.text)
            itemRow.totalPrice = firstAmount(in: row.text)
            itemRow.taxFlag = detectTaxFlag(row.text)
            itemRow.nonFoodHint = nonFoodKeywords.contains { lower.contains($0) }
            itemRow.feeHint = feeKeywords.contains { lower.contains($0) }
            if inVoidedSection {
                voided.append(itemRow)
            } else {
                items.append(itemRow)
            }
            i += 1
        }

        result.candidateItems = items
        result.voidedItems = voided
        result.hintsBlock = buildHintsBlock(result)
        result.duplicateKey = buildDuplicateKey(store: result.storeNameGuess, total: result.totalAmount, fullText: fullText)
        return result
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

    /// A row like "$2.99/lb x 1.64 lb" or "1 @ 2 for $7.00" or "3 @ 6.71"
    /// that continues the PREVIOUS item rather than naming a new one.
    private static func isContinuationLine(_ text: String) -> Bool {
        let patterns = [
            #"^\s*\$?\d+(\.\d+)?\s*/\s*(lb|kg)\s*x\s*\d"#, // "$2.99/lb x 1.64 lb"
            #"^\s*\d+(\.\d+)?\s*(lb|kg)\s*@\s*\$?\d"#, // "2.36 lb @ 2.99/lb"
            #"^\s*\d+\s*@\s*\d"#, // "3 @ 6.71" / "1 @ 2 for $7.00"
            #"^\s*\d+(\.\d+)?\s*lb\s*@"#,
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
