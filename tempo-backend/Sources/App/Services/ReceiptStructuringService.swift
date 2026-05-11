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
            let userText = """
            \(storeLine)Below is the raw text extracted from a grocery receipt photo by Apple Vision (on-device OCR). \
            Structure it into the JSON shape described in the system prompt. Discard non-food rows (TOTAL, TAX, \
            CHANGE, store address, loyalty messages). For each food line item include canonical_food_name (lowercase \
            common name, no brands), display_name (title-case, brand stripped), quantity, unit, total_price, \
            quantity_grams (estimate when not printed), unit_price, price_per_kg (computed), on_sale, sale_note, \
            and confidence (0.0–1.0).

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

        let body = ReceiptClaudeRequest(
            model: AIConfig.haikuModel,
            maxTokens: 1500,
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
                confidence: item.confidence ?? 0.8
            )
        }
        let avgConfidence: Double = items.isEmpty
            ? 0
            : items.reduce(0) { $0 + $1.confidence } / Double(items.count)

        req.logger.info("Receipt structured: store=\(parsed.store) items=\(items.count) avg_conf=\(avgConfidence)")

        return .init(
            store: parsed.store,
            purchaseDate: parsed.purchaseDate,
            totalAmount: parsed.totalAmount,
            taxAmount: parsed.taxAmount,
            paymentMethod: parsed.paymentMethod,
            lineItems: items,
            confidence: avgConfidence,
            provider: provider,
            notes: parsed.notes
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
    You are a grocery RECEIPT extraction system. Convert a grocery receipt (raw text and/or photo) into a structured JSON payload of line items.

    RULES:
    1. Use canonical lowercase food names (e.g. "chicken breast", "salmon", "bananas") — never brand names. Strip "GV", "ATL", "USDA", "BNLS", and similar receipt abbreviations.
    2. For each food line: include `raw_text` exactly as printed.
    3. Discard non-food rows: subtotals, tax lines, payment lines, store address, loyalty messages, coupons, "THANK YOU" lines.
    4. Estimate `quantity_grams` when not printed (typical chicken breast ~200g/piece, banana ~120g, salmon fillet ~200g, etc).
    5. BOGO (buy one get one) → halve `total_price`, set `on_sale = true`, `sale_note = "BOGO"`.
    6. "2 for $X" deal → divide by 2 for `unit_price`, set `on_sale = true`, `sale_note = "2 for $X"`.
    7. If both sale and regular price are shown, use the SALE price as `total_price`.
    8. Compute `price_per_kg` when grams are known: (total_price / quantity_grams) * 1000.
    9. Per-line `confidence` is your honesty score 0.0–1.0 about how sure you are this line was parsed correctly.

    OUTPUT — return ONLY valid JSON. No markdown, no code fences, no commentary. Shape:
    {
      "store": "Publix",
      "purchase_date": "2026-05-11T10:30:00Z",
      "total_amount": 24.75,
      "tax_amount": 1.50,
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
          "confidence": 0.93
        }
      ],
      "notes": "Skipped 2 illegible lines."
    }

    If a field cannot be determined, use null. If the receipt is unreadable, return `line_items: []` and explain in `notes`.
    """
}

// MARK: - Errors

enum ReceiptStructuringError: AbortError {
    case missingAPIKey
    case invalidInput
    case apiError(Int)
    case malformedResponse
    case parseFailed(String)

    var status: HTTPResponseStatus {
        switch self {
        case .missingAPIKey: .internalServerError
        case .invalidInput: .badRequest
        case let .apiError(code) where code == 429: .tooManyRequests
        case .apiError: .badGateway
        case .malformedResponse, .parseFailed: .badGateway
        }
    }

    var reason: String {
        switch self {
        case .missingAPIKey: "Anthropic API key not configured."
        case .invalidInput: "Receipt structuring requires raw_text or image_base64."
        case let .apiError(code): "Claude API error (HTTP \(code))."
        case .malformedResponse: "Claude returned an unparseable receipt response."
        case let .parseFailed(detail): "Claude JSON parse failed: \(detail)."
        }
    }
}

// MARK: - Wire DTOs

struct ReceiptStructuringRequestDTO: Content {
    let rawText: String?
    let imageBase64: String?
    let imageMediaType: String?
    let storeHint: String?
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

    struct Block: Decodable {
        let type: String
        let text: String
    }
}

// MARK: - Haiku output parsing

private struct HaikuReceiptPayload: Decodable {
    let store: String
    let purchaseDate: Date?
    let totalAmount: Double?
    let taxAmount: Double?
    let paymentMethod: String?
    let lineItems: [HaikuLineItem]
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case store
        case purchaseDate
        case totalAmount
        case taxAmount
        case paymentMethod
        case lineItems
        case notes
    }
}

private struct HaikuLineItem: Decodable {
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
    }
}
