@testable import App
import Testing
import Foundation

// MARK: - Receipt structuring decode tests
//
// This decode path has 502'd in production three times — 413 (image too big),
// truncation (maxTokens too low), and a date typeMismatch (Claude emits
// purchase_date as an ISO STRING but the struct decoded Date with the default
// numeric-timestamp strategy). Each was found via a deploy + on-device rescan.
//
// These tests feed REAL Claude JSON (captured from Railway logs) through the
// exact decoder the service uses, so the next field mismatch is caught here —
// locally, in seconds — instead of via another deploy cycle.

@Suite("Receipt structuring decode")
struct ReceiptStructuringDecodeTests {

    /// Mirrors the parser configured in ReceiptStructuringService: snake_case
    /// keys, NO dateDecodingStrategy (purchase_date is a String).
    private func makeParser() -> JSONDecoder {
        let parser = JSONDecoder()
        parser.keyDecodingStrategy = .convertFromSnakeCase
        return parser
    }

    /// The exact shape Claude returned for the Publix receipt that 502'd —
    /// purchase_date is an ISO 8601 STRING, which broke the old Date decode.
    private let realClaudeJSON = """
    {
      "store": "Publix",
      "purchase_date": "2026-06-04T21:20:00Z",
      "total_amount": 88.54,
      "tax_amount": 1.00,
      "payment_method": "MasterCard",
      "line_items": [
        {
          "raw_text": "Mentos Sweet Mint Gum",
          "canonical_food_name": "chewing gum",
          "display_name": "Chewing Gum",
          "quantity": 1,
          "unit": "unit",
          "quantity_grams": null,
          "unit_price": 4.99,
          "total_price": 4.99,
          "price_per_kg": null,
          "on_sale": false,
          "sale_note": null,
          "confidence": 0.9
        }
      ],
      "notes": null
    }
    """

    @Test("decodes real Claude JSON with an ISO-string purchase_date")
    func decodesRealClaudeJSON() throws {
        let data = Data(realClaudeJSON.utf8)
        let parsed = try makeParser().decode(HaikuReceiptPayload.self, from: data)

        #expect(parsed.store == "Publix")
        #expect(parsed.purchaseDate == "2026-06-04T21:20:00Z")
        #expect(parsed.lineItems.count == 1)
        #expect(parsed.lineItems.first?.canonicalFoodName == "chewing gum")
        #expect(parsed.totalAmount == 88.54)
    }

    @Test("ISO 8601 purchase_date parses to a Date")
    func parsesISODate() {
        let d = ReceiptDateParser.parse("2026-06-04T21:20:00Z")
        #expect(d != nil)
    }

    @Test("ISO 8601 with fractional seconds parses")
    func parsesFractionalISODate() {
        let d = ReceiptDateParser.parse("2026-06-04T21:20:00.500Z")
        #expect(d != nil)
    }

    @Test("date-only string parses")
    func parsesDateOnly() {
        let d = ReceiptDateParser.parse("2026-06-04")
        #expect(d != nil)
    }

    @Test("unparseable / nil / empty date yields nil, never throws")
    func badDateYieldsNil() {
        #expect(ReceiptDateParser.parse(nil) == nil)
        #expect(ReceiptDateParser.parse("") == nil)
        #expect(ReceiptDateParser.parse("not a date") == nil)
        #expect(ReceiptDateParser.parse("June 4th") == nil)
    }

    @Test("decode still succeeds when purchase_date is null")
    func decodesNullDate() throws {
        let json = realClaudeJSON.replacingOccurrences(
            of: "\"2026-06-04T21:20:00Z\"",
            with: "null"
        )
        let parsed = try makeParser().decode(HaikuReceiptPayload.self, from: Data(json.utf8))
        #expect(parsed.purchaseDate == nil)
        #expect(parsed.lineItems.count == 1)
    }
}
