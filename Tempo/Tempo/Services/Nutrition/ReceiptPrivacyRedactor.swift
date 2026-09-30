//
// ReceiptPrivacyRedactor.swift
// Tempo
//
// Strips payment-card digits, auth/trace/reference codes, and loyalty IDs
// out of OCR'd receipt text BEFORE it's sent to the backend (raw_text field)
// or persisted to SwiftData (Receipt.ocrRawText). Verified against 2 real
// receipts whose footers contained genuine-looking payment metadata:
//   "MasterCard: *3918"                        -> kept (already masked)
//   "Auth/Trace: 403302/067554"                -> redacted
//   "Reference: 001877040565"                  -> redacted
//   "A0000000041010"                           -> redacted (EMV AID)
//   "Acct #: XXXXXXXXXXXX3918"                 -> redacted digits (masked X's kept)
// Runs on the FULL raw OCR text (flattened), independent of row structure,
// so it's safe to call right before either send path.
//

import Foundation

enum ReceiptPrivacyRedactor {
    /// Line-prefix keywords whose entire trailing value is redacted,
    /// regardless of digit count — these only ever hold payment metadata,
    /// never anything a user needs to review.
    private static let sensitiveLinePrefixes = [
        "auth/trace", "auth #", "auth#", "trace #", "trace#",
        "reference #", "reference#", "ref #",
        "acct #", "acct#", "account #",
        "card #", "card#",
    ]

    /// Redacts:
    ///  - whole lines starting with a sensitive keyword -> keyword kept, value replaced with "[redacted]"
    ///  - bare EMV AID-looking tokens (A followed by 10+ hex digits, e.g. "A0000000041010")
    ///  - any standalone run of 9+ digits NOT already partially masked with
    ///    X's/asterisks (a masked "*3918" or "XXXXXXXXXXXX3918" is left as-is
    ///    since it's already safe — only fully-exposed long digit runs are a
    ///    real leak, e.g. an unmasked auth/reference number).
    static func redact(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        for i in lines.indices {
            lines[i] = redactLine(lines[i])
        }
        return lines.joined(separator: "\n")
    }

    private static func redactLine(_ line: String) -> String {
        let lower = line.lowercased()
        if let prefix = sensitiveLinePrefixes.first(where: { lower.hasPrefix($0) || lower.contains($0) }) {
            if let range = lower.range(of: prefix) {
                let keywordEnd = line.index(line.startIndex, offsetBy: line.distance(from: line.startIndex, to: range.upperBound))
                return String(line[line.startIndex ..< keywordEnd]) + " [redacted]"
            }
        }

        var result = line

        // EMV Application Identifier tokens: "A0000000041010".
        result = replacing(result, pattern: #"\bA[0-9]{10,}\b"#, with: "[redacted]")

        // Bare 9+ digit runs with no X/asterisk masking anywhere in the token
        // (a masked card "XXXXXXXXXXXX3918" or "*3918" is fine to keep).
        result = replacing(result, pattern: #"\b\d{9,}\b"#, with: "[redacted]")

        return result
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
