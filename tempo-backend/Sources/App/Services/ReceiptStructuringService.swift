import Foundation
import Vapor

// MARK: - Receipt Structuring Service

// Takes a raw OCR text (preferred) and/or a base64 image, asks Claude Haiku
// Vision to produce structured line items, returns the parsed result. Uses the
// same retry/JSON-extraction logic as InsightService but with a vision-shaped
// content array (text + image blocks).

// Mirrors NutriTrack services/price_scanner.py PRICE_SCAN_SYSTEM prompt,
// adapted for receipts (multi-item rather than single shelf tag).

actor ReceiptStructuringService {
    static let shared = ReceiptStructuringService()

    // MARK: - Public API

    func structureReceipt(
        request: ReceiptStructuringRequestDTO,
        on req: Request
    ) async throws -> ReceiptStructuringResponseDTO {
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw ReceiptStructuringError.missingAPIKey
        }
        guard request.rawText != nil || request.imageBase64 != nil else {
            throw ReceiptStructuringError.invalidInput
        }

        var contentBlocks: [ReceiptClaudeContentBlock] = []
        if let raw = request.rawText, !raw.isEmpty {
            let storeLine = request.storeHint.map { "Store hint: \($0)\n" } ?? ""
            let chainHintLine = request.storeChainHint.map { "Store chain hint: \($0)\n" } ?? ""
            // Dictionary hints are abbreviation->expansion pairs the iOS client
            // already resolved deterministically (e.g. from a local dictionary).
            // Told to Claude explicitly so it PREFERS these over guessing —
            // it should still fall back to its own judgement for anything not
            // covered by the list.
            let dictionaryHintsBlock: String = {
                guard let hints = request.dictionaryHints, !hints.isEmpty else { return "" }
                let lines = hints.map { "- \($0)" }.joined(separator: "\n")
                return "\nKnown abbreviation expansions (prefer these when they apply to a raw line):\n\(lines)\n"
            }()
            let userText = """
            \(storeLine)\(chainHintLine)Below is the raw text extracted from a grocery receipt photo by Apple Vision (on-device OCR). \
            Structure it into the JSON shape described in the system prompt. Discard non-item rows (subtotal/total/tax \
            summary lines, payment lines, store address, loyalty messages) — but DO capture voided items separately per \
            the system prompt's rules (they must NOT appear in line_items). For each item include canonical_food_name \
            (lowercase common name, no brands — for non-food items use a short lowercase generic name), display_name \
            (title-case, brand stripped), quantity, unit, total_price, quantity_grams (estimate when not printed and the \
            item is food), unit_price, price_per_kg (computed for food), on_sale, sale_note, is_non_food, is_fee, \
            tax_flag, category_hint, line_discount, and confidence (0.0–1.0).
            \(dictionaryHintsBlock)
            Raw receipt text:
            ---
            \(raw)
            ---
            """
            contentBlocks.append(.init(type: "text", text: userText, source: nil))
        }
        if let b64 = request.imageBase64, !b64.isEmpty {
            let mediaType = request.imageMediaType ?? "image/jpeg"
            contentBlocks.append(.init(
                type: "image",
                text: nil,
                source: .init(type: "base64", mediaType: mediaType, data: b64)
            ))
            if request.rawText == nil || request.rawText?.isEmpty == true {
                contentBlocks.append(.init(
                    type: "text",
                    text: "Read this grocery receipt photo and produce the structured JSON described in the system prompt. " +
                        (request.storeHint.map { "Store hint: \($0). " } ?? "") +
                        "Skip non-food rows. Estimate quantity_grams when not printed.",
                    source: nil
                ))
            }
        }

        // 8192, not 1500: a full grocery receipt's structured JSON (30+ items,
        // ~12 lines each) blows well past 1500 tokens. At 1500 Claude's output
        // was truncated mid-array ("sale_note": null, <cut>), the JSON failed
        // to parse, and the endpoint returned a cryptic 502. 8192 is Haiku's
        // headroom; the stop_reason guard below catches the rare overflow.
        let body = ReceiptClaudeRequest(
            model: AIConfig.haikuModel,
            maxTokens: 8192,
            temperature: 0.2,
            system: Self.systemPrompt,
            messages: [.init(role: "user", content: contentBlocks)]
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(body)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: "x-api-key", value: apiKey)
        headers.add(name: "anthropic-version", value: "2023-06-01")

        let response = try await req.client.post(
            URI(string: "https://api.anthropic.com/v1/messages"),
            headers: headers
        ) { clientReq in
            clientReq.body = .init(data: bodyData)
        }

        guard response.status == .ok else {
            let bodyString = response.body.map { String(buffer: $0) } ?? ""
            req.logger.error("Claude receipt structuring HTTP \(response.status.code): \(bodyString)")
            throw ReceiptStructuringError.apiError(Int(response.status.code))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rawResponse = try response.content.decode(ReceiptClaudeRawResponse.self, using: decoder)

        // If Claude stopped because it hit the token cap, the JSON is
        // incomplete by definition — bail with a clear error instead of
        // feeding a truncated array to the decoder (which produced the old
        // cryptic 502 + "not valid JSON" log spam).
        if rawResponse.stopReason == "max_tokens" {
            req.logger.warning("Receipt structuring truncated: Claude hit max_tokens (response incomplete)")
            throw ReceiptStructuringError.responseTruncated
        }

        guard let textBlock = rawResponse.content.first(where: { $0.type == "text" }) else {
            throw ReceiptStructuringError.malformedResponse
        }

        // Parse JSON, tolerant of markdown wrapping.
        let jsonString = extractJSON(from: textBlock.text)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ReceiptStructuringError.malformedResponse
        }
        let parser = JSONDecoder()
        parser.keyDecodingStrategy = .convertFromSnakeCase
        // NOTE: no dateDecodingStrategy — purchase_date is decoded as a String
        // (see HaikuReceiptPayload) and parsed in code via ReceiptDateParser.
        // A dateDecodingStrategy closure MUST return a Date (can't return nil),
        // so any unparseable date would throw and 502 the whole receipt even
        // though the field is optional. String-then-parse never throws.

        let parsed: HaikuReceiptPayload
        do {
            parsed = try parser.decode(HaikuReceiptPayload.self, from: jsonData)
        } catch {
            req.logger.error("Receipt JSON parse failed: \(error) | raw=\(jsonString.prefix(500))")
            throw ReceiptStructuringError.parseFailed(error.localizedDescription)
        }

        let provider = (request.rawText?.isEmpty == false) ? "vision_and_haiku" : "haiku_vision"
        let items: [ReceiptStructuringResponseDTO.Item] = parsed.lineItems.map { item in
            let canonical = item.canonicalFoodName.lowercased()
            let display = item.displayName.isEmpty ? canonical.capitalized : item.displayName
            return .init(
                rawText: item.rawText,
                canonicalFoodName: canonical,
                displayName: display,
                quantity: item.quantity,
                unit: item.unit,
                quantityGrams: item.quantityGrams,
                unitPrice: item.unitPrice,
                totalPrice: item.totalPrice,
                pricePerKg: item.pricePerKg,
                onSale: item.onSale ?? false,
                saleNote: item.saleNote,
                confidence: item.confidence ?? 0.8,
                isNonFood: item.isNonFood,
                isFee: item.isFee,
                taxFlag: item.taxFlag,
                categoryHint: item.categoryHint,
                lineDiscount: item.lineDiscount
            )
        }
        let avgConfidence: Double = items.isEmpty
            ? 0
            : items.reduce(0) { $0 + $1.confidence } / Double(items.count)

        req.logger.info("Receipt structured: store=\(parsed.store) items=\(items.count) avg_conf=\(avgConfidence)")

        return .init(
            store: parsed.store,
            purchaseDate: ReceiptDateParser.parse(parsed.purchaseDate),
            totalAmount: parsed.totalAmount,
            taxAmount: parsed.taxAmount,
            paymentMethod: parsed.paymentMethod,
            lineItems: items,
            confidence: avgConfidence,
            provider: provider,
            notes: parsed.notes,
            subtotalAmount: parsed.subtotalAmount,
            savingsAmount: parsed.savingsAmount,
            couponTotal: parsed.couponTotal,
            currency: parsed.currency,
            storeChain: parsed.storeChain
        )
    }

    // MARK: - JSON cleanup

    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return trimmed
        }
        if let start = trimmed.range(of: "{"), let end = trimmed.range(of: "}", options: .backwards) {
            return String(trimmed[start.lowerBound ... end.upperBound])
        }
        return trimmed
    }

    // MARK: - Prompt

    private static let systemPrompt: String = """
    You are a grocery RECEIPT extraction system. Convert a grocery receipt (raw text and/or photo) into a structured JSON payload of line items. You mostly see Publix (a US chain) but may also see Walmart, Target, Costco, Whole Foods, Trader Joe's, Aldi, Lidl, and Italian chains (Esselunga, Conad, Carrefour) or other regional grocers. Apply the pattern-based rules below generically rather than hard-coding any one chain's layout.

    BASICS
    1. Use canonical lowercase food names (e.g. "chicken breast", "salmon", "bananas") — never brand names. Strip "GV", "ATL", "USDA", "BNLS", store-brand prefixes, and item numbers some chains (Walmart, Target, Costco) print before the name.
    2. For each line include `raw_text` exactly as printed.
    3. Discard pure summary rows: subtotal/total/tax lines themselves, payment/card lines, store address, loyalty/rewards messages, "THANK YOU" footers. These are NOT line items and have no place in `line_items`.
    4. Estimate `quantity_grams` when not printed and the item is food (typical chicken breast ~200g/piece, banana ~120g, salmon fillet ~200g, etc). Leave null for non-food items.
    5. Compute `price_per_kg` when grams are known: (total_price / quantity_grams) * 1000. Null for non-food.
    6. Per-line `confidence` is your honesty score 0.0–1.0 about how sure you are this line was parsed correctly.
    7. Negative `total_price` is VALID and expected for a return/refund line — never reject or reinterpret it as an error.

    VOIDED ITEMS (do not drop this rule)
    Publix (and others) sometimes print a "Voided Items" section near the end listing items that were scanned then voided BEFORE the sale finalized. These must NOT be returned in `line_items` and must NOT be counted toward `total_amount`/`subtotal_amount` — the printed subtotal already excludes them. Example: a line "GV WHIPPED CREAM 2.79" appearing under a "Voided Items" heading is skipped entirely, not included with a negative price.

    SALES, COUPONS, DISCOUNTS
    8. BOGO (buy one get one) → halve `total_price`, set `on_sale = true`, `sale_note = "BOGO"`.
    9. "2 for $X" / "3 for $X" deal → divide by count for `unit_price`, set `on_sale = true`, `sale_note = "2 for $X"`.
    10. If both sale and regular price are shown, use the SALE price as `total_price`.
    11. "You saved: $X.XX" printed on the line directly below an item attaches to THAT item: set `line_discount = X.XX` and `sale_note` to something like "Saved $2.00" (`total_price` is already the discounted price as printed — do not subtract the saving again).
       Example:
         "BOGO OATLY OAT MILK      4.29 F"
         "  You saved: $4.29"
       → one line item, `total_price: 4.29`, `line_discount: 4.29`, `on_sale: true`, `sale_note: "You saved $4.29"`.
    12. Some discounts instead print as their own line literally named "Promotion" (or "Coupon", "Discount") with a NEGATIVE amount, e.g. `-5.35`, not tied to a specific item above it. Do NOT emit this as a food line item and do NOT drop it — add its absolute value into the top-level `coupon_total` (sum of all such order-level reductions). A per-item coupon that clearly discounts one specific product above it should instead be folded into that item's `line_discount`, same as a "You saved" note.
    13. Deposits/bottle fees (CRV) and bag fees are fees, not food and not general merchandise: set `is_fee = true` (leave `is_non_food` false/null for these).

    WEIGHTS AND MULTI-QUANTITY LINES
    14. A weight line printed directly under a produce item ("$2.99/lb x 1.64 lb" or "2.36 lb @ 2.99/lb") belongs to THAT item, not a separate line: set `quantity` = the weight, `unit = "lb"`, `unit_price` = the per-lb price, `total_price` = the printed extended price.
    15. A multi-quantity line under an item ("3 @ 6.71", "1 @ 2 for $7.00", "1 @ 3 for $10.00") also belongs to that item: derive `quantity` and `unit_price` accordingly, keep `total_price` as printed.

    TAX FLAGS
    16. Publix prints a per-item tax flag: F (food, tax-exempt), T (taxable non-food or taxed food), FT (food but still taxed, e.g. some beverages). Copy it as printed into `tax_flag` ("F"/"T"/"FT") when present, else null. Report `tax_amount` exactly as printed on the receipt — do NOT try to recompute it or get confused if summing F-flagged items' prices doesn't multiply cleanly to the tax; only T/FT lines are taxed, and that math is the client's problem, not yours.

    NON-FOOD ITEMS
    17. Household goods, pharmacy items, gift cards, and lottery tickets DO appear on grocery receipts and must still be captured as line items — set `is_non_food = true` and give them a reasonable lowercase `canonical_food_name` (e.g. "dryer sheets", "dish soap", "candle"). Real examples: "Downy Sht Lav & Van" (dryer sheets), "Dawn Pwash Lemon" (dish soap), "Y/C Catching Rays" (a Yankee Candle) — these typically carry tax_flag "T".

    DEPARTMENT HEADERS
    18. Section-divider lines printed as their own row ("PRODUCE", "DELI", "BAKERY", etc.) are not items — skip them as `line_items`, but set `category_hint` on the items that follow, until the next department header.

    LOCALE AWARENESS
    19. Non-US receipts may use comma decimals ("2,49"), € or £ symbols, VAT/IVA lines, "TOTALE" (=total), "SCONTO" (=discount), "RESO" (=return), "ANNULLO" (=voided — treat like Voided Items above), and DD/MM/YYYY dates. Infer the 3-letter ISO `currency` code ("USD" default, "EUR", "GBP", …) from symbols/store locale and normalize all amounts to plain decimal numbers regardless of the printed decimal separator.
    20. Infer a short lowercase `store_chain` slug from the store name (e.g. "publix", "walmart", "costco", "target", "trader_joes", "whole_foods", "aldi", "esselunga", "conad"; use "unknown" if you can't tell).

    OUTPUT — return ONLY valid JSON. No markdown, no code fences, no commentary. Shape (null is fine for anything you can't determine):
    {
      "store": "Publix",
      "store_chain": "publix",
      "currency": "USD",
      "purchase_date": "2026-05-11T10:30:00Z",
      "subtotal_amount": 150.82,
      "total_amount": 153.93,
      "tax_amount": 3.11,
      "savings_amount": 14.36,
      "coupon_total": 5.35,
      "payment_method": "VISA",
      "line_items": [
        {
          "raw_text": "GV CHKN BRST 1.32LB",
          "canonical_food_name": "chicken breast",
          "display_name": "Chicken Breast",
          "quantity": 1.32,
          "unit": "lb",
          "quantity_grams": 599,
          "unit_price": 4.99,
          "total_price": 6.59,
          "price_per_kg": 11.00,
          "on_sale": false,
          "sale_note": null,
          "confidence": 0.93,
          "is_non_food": false,
          "is_fee": false,
          "tax_flag": "F",
          "category_hint": "MEAT",
          "line_discount": null
        },
        {
          "raw_text": "Downy Sht Lav & Van",
          "canonical_food_name": "dryer sheets",
          "display_name": "Dryer Sheets",
          "quantity": 1,
          "unit": "unit",
          "quantity_grams": null,
          "unit_price": 8.49,
          "total_price": 8.49,
          "price_per_kg": null,
          "on_sale": false,
          "sale_note": null,
          "confidence": 0.9,
          "is_non_food": true,
          "is_fee": false,
          "tax_flag": "T",
          "category_hint": null,
          "line_discount": null
        }
      ],
      "notes": "Skipped 2 illegible lines. Excluded 1 voided item per Voided Items section."
    }

    If the receipt is unreadable, return `line_items: []` and explain in `notes`.
    """
}

// MARK: - Errors

enum ReceiptStructuringError: AbortError {
    case missingAPIKey
    case invalidInput
    case apiError(Int)
    case malformedResponse
    case parseFailed(String)
    /// Claude hit max_tokens before finishing the JSON — the receipt was too
    /// long to structure in one response. Distinct from parseFailed so the
    /// client gets an actionable message instead of a generic parse error.
    case responseTruncated

    var status: HTTPResponseStatus {
        switch self {
        case .missingAPIKey: .internalServerError
        case .invalidInput: .badRequest
        case let .apiError(code) where code == 429: .tooManyRequests
        case .apiError: .badGateway
        case .malformedResponse, .parseFailed: .badGateway
        // 422, NOT 502: truncation is a permanent failure for this payload —
        // retrying sends the identical receipt and gets identical truncation.
        // 502 is retryable on the client (3x, 10s each = ~40s hang); 422 is not.
        case .responseTruncated: .unprocessableEntity
        }
    }

    var reason: String {
        switch self {
        case .missingAPIKey: "Anthropic API key not configured."
        case .invalidInput: "Receipt structuring requires raw_text or image_base64."
        case let .apiError(code): "Claude API error (HTTP \(code))."
        case .malformedResponse: "Claude returned an unparseable receipt response."
        case let .parseFailed(detail): "Claude JSON parse failed: \(detail)."
        case .responseTruncated: "This receipt is too long to read in one pass. Try a photo of fewer items at a time."
        }
    }
}

// MARK: - Wire DTOs

struct ReceiptStructuringRequestDTO: Content {
    let rawText: String?
    let imageBase64: String?
    let imageMediaType: String?
    let storeHint: String?
    /// Short normalized chain slug the CLIENT already knows (e.g. "publix") —
    /// distinct from `storeHint` (a free-text store name/address line). When
    /// present it's passed straight through to Claude as a hint, same as
    /// `storeHint`.
    let storeChainHint: String?
    /// "ABBREVIATION -> expansion" strings the iOS client already resolved
    /// deterministically (e.g. from a bundled dictionary) before ever calling
    /// this endpoint. Optional and backward compatible — an old client that
    /// never sends this still gets a normal response.
    let dictionaryHints: [String]?
}

struct ReceiptStructuringResponseDTO: Content {
    let store: String
    let purchaseDate: Date?
    let totalAmount: Double?
    let taxAmount: Double?
    let paymentMethod: String?
    let lineItems: [Item]
    let confidence: Double
    let provider: String
    let notes: String?
    /// Printed subtotal before tax, when Claude can read it.
    let subtotalAmount: Double?
    /// Printed total savings line (e.g. "SAVINGS: $14.36"), when present.
    let savingsAmount: Double?
    /// Sum of order-level coupons/promotions not tied to a single line item
    /// (e.g. a "Promotion -5.35" line, or a store-wide coupon). Per-item
    /// discounts live on `Item.lineDiscount` instead.
    let couponTotal: Double?
    /// 3-letter ISO currency code Claude inferred from symbols/locale
    /// ("USD", "EUR", "GBP", …). Nil when it couldn't tell — clients should
    /// default to "USD".
    let currency: String?
    /// Short normalized chain slug Claude inferred (e.g. "publix", "walmart",
    /// "costco", "trader_joes", "unknown").
    let storeChain: String?

    struct Item: Content {
        let rawText: String
        let canonicalFoodName: String
        let displayName: String
        let quantity: Double
        let unit: String
        let quantityGrams: Double?
        let unitPrice: Double?
        let totalPrice: Double
        let pricePerKg: Double?
        let onSale: Bool
        let saleNote: String?
        let confidence: Double
        /// Household/pharmacy/gift-card/lottery etc — not food, but still a
        /// real line item (not a fee).
        let isNonFood: Bool?
        /// Deposits/bottle fees (CRV), bag fees — a fee, not food and not
        /// "non-food merchandise" (kept distinct so the app can show fees
        /// separately from groceries).
        let isFee: Bool?
        /// Publix-style per-item tax flag as printed: "F" (food, tax-exempt),
        /// "T" (taxable non-food or taxed food), "FT" (food but still taxed).
        /// Passed through as printed, never recomputed here.
        let taxFlag: String?
        /// Department section header this item fell under on the receipt
        /// (e.g. "PRODUCE", "DELI"), when one was printed above it.
        let categoryHint: String?
        /// Per-line coupon/discount amount already reflected in `totalPrice`
        /// (i.e. informational — NOT subtracted again by the client).
        let lineDiscount: Double?
    }
}

// MARK: - Vision-shaped Claude DTOs (kept private — InsightService text-only DTOs unchanged)

private struct ReceiptClaudeRequest: Codable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [ReceiptClaudeMessage]
}

private struct ReceiptClaudeMessage: Codable {
    let role: String
    let content: [ReceiptClaudeContentBlock]
}

private struct ReceiptClaudeContentBlock: Codable {
    let type: String
    let text: String?
    let source: Source?

    struct Source: Codable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }
}

private struct ReceiptClaudeRawResponse: Decodable {
    let content: [Block]
    /// "end_turn" = complete, "max_tokens" = output was truncated.
    let stopReason: String?

    struct Block: Decodable {
        let type: String
        let text: String
    }

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

// MARK: - Haiku output parsing

// MARK: - Date parsing

/// Lenient parse of Claude's purchase_date string → Date?. Never throws: an
/// unrecognized or nil string yields nil so a bad date never fails the receipt.
enum ReceiptDateParser {
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) {
            return d
        }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) {
            return d
        }
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(identifier: "UTC")
        dateOnly.dateFormat = "yyyy-MM-dd"
        if let d = dateOnly.date(from: raw) {
            return d
        }
        return nil
    }
}

/// Non-private so AppTests can decode-test against real Claude JSON — this is
/// the path that has 502'd three times (413, truncation, date typeMismatch).
struct HaikuReceiptPayload: Decodable {
    let store: String
    /// Decoded as a raw String (Claude emits ISO 8601 like
    /// "2026-06-04T21:20:00Z"); parsed to Date in code via ReceiptDateParser
    /// so a malformed date yields nil instead of 502ing the whole receipt.
    let purchaseDate: String?
    let totalAmount: Double?
    let taxAmount: Double?
    let paymentMethod: String?
    let lineItems: [HaikuLineItem]
    let notes: String?
    // New, optional — see ReceiptStructuringResponseDTO for meaning. Absent
    // in old cached/replayed responses decodes fine as nil.
    let subtotalAmount: Double?
    let savingsAmount: Double?
    let couponTotal: Double?
    let currency: String?
    let storeChain: String?

    enum CodingKeys: String, CodingKey {
        case store
        case purchaseDate
        case totalAmount
        case taxAmount
        case paymentMethod
        case lineItems
        case notes
        case subtotalAmount
        case savingsAmount
        case couponTotal
        case currency
        case storeChain
    }
}

struct HaikuLineItem: Decodable {
    let rawText: String
    let canonicalFoodName: String
    let displayName: String
    let quantity: Double
    let unit: String
    let quantityGrams: Double?
    let unitPrice: Double?
    let totalPrice: Double
    let pricePerKg: Double?
    let onSale: Bool?
    let saleNote: String?
    let confidence: Double?
    // New, optional — see ReceiptStructuringResponseDTO.Item for meaning.
    let isNonFood: Bool?
    let isFee: Bool?
    let taxFlag: String?
    let categoryHint: String?
    let lineDiscount: Double?

    enum CodingKeys: String, CodingKey {
        case rawText
        case canonicalFoodName
        case displayName
        case quantity
        case unit
        case quantityGrams
        case unitPrice
        case totalPrice
        case pricePerKg
        case onSale
        case saleNote
        case confidence
        case isNonFood
        case isFee
        case taxFlag
        case categoryHint
        case lineDiscount
    }
}
