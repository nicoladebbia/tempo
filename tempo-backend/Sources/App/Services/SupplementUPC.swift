import Foundation

// MARK: - SupplementUPC

//
// Barcode normalisation. A phone camera reports a UPC-A as an EAN-13 with a
// leading 0 ("0748927028669"), labels print the 12-digit form, and DSLD
// stores it grouped ("7 48927 02866 9"). Look-ups used to send whatever the
// scanner produced, so the same product hit or missed depending on the
// scanner. Everything now goes through `normalize` first.

struct NormalizedUPC: Equatable, Sendable {
    /// Cache / dedupe key: the 12-digit UPC-A when the code has one, else the
    /// EAN-13 / EAN-8.
    let canonical: String
    /// 12-digit UPC-A when the code is (or embeds) one.
    let upcA: String?
    /// 13-digit EAN form (UPC-A with a leading 0, or the EAN-13 itself).
    let ean13: String?

    /// Spellings Open Food Facts style APIs may know the product under.
    var offCandidates: [String] {
        var out: [String] = []
        for code in [ean13, upcA, canonical] {
            if let code, !out.contains(code) { out.append(code) }
        }
        return out
    }

    /// DSLD keeps the label's own spacing: UPC-A as "7 48927 02866 9".
    /// Returns the quoted phrase forms to try, grouped first, then the plain digits.
    var dsldPhrases: [String] {
        var out: [String] = []
        if let upcA {
            let d = Array(upcA)
            out.append("\"\(d[0]) \(String(d[1 ... 5])) \(String(d[6 ... 10])) \(d[11])\"")
            out.append("\"\(upcA)\"")
        } else if canonical.count == 13 {
            let d = Array(canonical)
            out.append("\"\(d[0]) \(String(d[1 ... 6])) \(String(d[7 ... 11])) \(d[12])\"")
            out.append("\"\(canonical)\"")
        } else {
            out.append("\"\(canonical)\"")
        }
        return out
    }

    /// Digit strings a DSLD `upcSku` may legitimately equal for this barcode.
    var matchDigits: Set<String> {
        Set([upcA, ean13, canonical].compactMap { $0 })
    }
}

enum SupplementUPC {
    enum Failure: Error, Equatable {
        case badLength
        case badCheckDigit
    }

    /// GTIN check digit over the body (everything but the last digit).
    static func checkDigit(forBody body: [Int]) -> Int {
        // Weights alternate 3,1 starting from the digit next to the check digit.
        var sum = 0
        for (offset, digit) in body.reversed().enumerated() {
            sum += digit * (offset % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    static func isValidGTIN(_ digits: String) -> Bool {
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count == digits.count, nums.count >= 8 else { return false }
        return checkDigit(forBody: Array(nums.dropLast())) == nums.last
    }

    /// UPC-E (8 digits, number system 0/1) → UPC-A (12).
    static func expandUPCE(_ e: String) -> String? {
        let d = e.compactMap { $0.wholeNumberValue }
        guard d.count == 8, d[0] == 0 || d[0] == 1 else { return nil }
        let m = Array(d[1 ... 6])
        let body: [Int]
        switch m[5] {
        case 0, 1, 2: body = [d[0], m[0], m[1], m[5], 0, 0, 0, 0, m[2], m[3], m[4]]
        case 3: body = [d[0], m[0], m[1], m[2], 0, 0, 0, 0, 0, m[3], m[4]]
        case 4: body = [d[0], m[0], m[1], m[2], m[3], 0, 0, 0, 0, 0, m[4]]
        default: body = [d[0], m[0], m[1], m[2], m[3], m[4], 0, 0, 0, 0, m[5]]
        }
        return (body + [d[7]]).map(String.init).joined()
    }

    /// Strips non-digits, pads/trims to the real GTIN length and checks the
    /// check digit. Throws on a code that cannot be a barcode.
    static func normalize(_ raw: String) throws -> NormalizedUPC {
        var digits = raw.filter { $0.isASCII && $0.isNumber }
        guard (6 ... 14).contains(digits.count) else { throw Failure.badLength }

        // Dropped leading zeros (spreadsheet / typed codes): 6-7 digits can
        // only be a short UPC-E-ish code; 9-11 digits are a UPC-A that lost zeros.
        if digits.count < 12, digits.count > 8 {
            digits = String(repeating: "0", count: 12 - digits.count) + digits
        }
        // GTIN-14 with a leading 0 indicator is the same product as the 13/12.
        if digits.count == 14, digits.hasPrefix("0") { digits.removeFirst() }
        if digits.count == 13, digits.hasPrefix("0") {
            let upc = String(digits.dropFirst())
            guard isValidGTIN(upc) else { throw Failure.badCheckDigit }
            return NormalizedUPC(canonical: upc, upcA: upc, ean13: digits)
        }

        switch digits.count {
        case 12:
            guard isValidGTIN(digits) else { throw Failure.badCheckDigit }
            return NormalizedUPC(canonical: digits, upcA: digits, ean13: "0" + digits)
        case 13:
            guard isValidGTIN(digits) else { throw Failure.badCheckDigit }
            return NormalizedUPC(canonical: digits, upcA: nil, ean13: digits)
        case 8:
            if let a = expandUPCE(digits), isValidGTIN(a) {
                return NormalizedUPC(canonical: a, upcA: a, ean13: "0" + a)
            }
            guard isValidGTIN(digits) else { throw Failure.badCheckDigit }
            return NormalizedUPC(canonical: digits, upcA: nil, ean13: nil)
        default:
            throw Failure.badLength
        }
    }
}
