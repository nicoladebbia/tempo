//
// SupplementBarcode.swift
// Tempo
//
// Barcode normalisation for the supplement shelf. A phone camera reports a
// UPC-A as an EAN-13 with a leading 0, labels print the 12-digit form and
// typed codes lose their leading zero, so the same bottle used to be a hit or
// a miss depending on how it was read. Everything (shelf match, local cache,
// backend lookup) now goes through `normalized` first. Mirrors the backend's
// `SupplementUPC`.
//

import Foundation

struct SupplementBarcode: Equatable, Sendable {
    /// 12-digit UPC-A when the code has one, else the EAN-13 / EAN-8.
    let canonical: String
    let upcA: String?
    let ean13: String?

    /// Every spelling a stored product could carry for this barcode.
    var variants: Set<String> {
        Set([canonical, upcA, ean13].compactMap { $0 })
    }

    enum Failure: Error, Equatable {
        case badLength
        case badCheckDigit

        var message: String {
            switch self {
            case .badLength: "A barcode has 8, 12 or 13 digits. Check what you typed."
            case .badCheckDigit: "That barcode doesn't add up — one digit is off. Check it or scan again."
            }
        }
    }

    static func checkDigit(forBody body: [Int]) -> Int {
        var sum = 0
        for (offset, digit) in body.reversed().enumerated() {
            sum += digit * (offset % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    static func isValidGTIN(_ digits: String) -> Bool {
        let nums = digits.compactMap(\.wholeNumberValue)
        guard nums.count == digits.count, nums.count >= 8 else { return false }
        return checkDigit(forBody: Array(nums.dropLast())) == nums.last
    }

    /// UPC-E (8 digits, number system 0/1) → UPC-A (12).
    static func expandUPCE(_ e: String) -> String? {
        let d = e.compactMap(\.wholeNumberValue)
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

    static func normalize(_ raw: String) -> Result<SupplementBarcode, Failure> {
        var digits = raw.filter { $0.isASCII && $0.isNumber }
        guard (8 ... 14).contains(digits.count) else { return .failure(.badLength) }
        // A UPC-A that lost its leading zeros (9-11 digits).
        if digits.count > 8, digits.count < 12 {
            digits = String(repeating: "0", count: 12 - digits.count) + digits
        }
        if digits.count == 14, digits.hasPrefix("0") { digits.removeFirst() }
        if digits.count == 13, digits.hasPrefix("0") {
            let upc = String(digits.dropFirst())
            guard isValidGTIN(upc) else { return .failure(.badCheckDigit) }
            return .success(SupplementBarcode(canonical: upc, upcA: upc, ean13: digits))
        }
        switch digits.count {
        case 12:
            guard isValidGTIN(digits) else { return .failure(.badCheckDigit) }
            return .success(SupplementBarcode(canonical: digits, upcA: digits, ean13: "0" + digits))
        case 13:
            guard isValidGTIN(digits) else { return .failure(.badCheckDigit) }
            return .success(SupplementBarcode(canonical: digits, upcA: nil, ean13: digits))
        case 8:
            if let a = expandUPCE(digits), isValidGTIN(a) {
                return .success(SupplementBarcode(canonical: a, upcA: a, ean13: "0" + a))
            }
            guard isValidGTIN(digits) else { return .failure(.badCheckDigit) }
            return .success(SupplementBarcode(canonical: digits, upcA: nil, ean13: nil))
        default:
            return .failure(.badLength)
        }
    }
}

// MARK: - SupplementLookupCache

/// Remembers every product a lookup resolved so a re-scan (and a scan with no
/// signal in the shop) answers instantly. Small, on-device, keyed by canonical
/// barcode.
struct SupplementLookupCache: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "supplement.lookup.cache.v1"
    private let limit = 300

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private struct Entry: Codable {
        var code: String
        var dto: SupplementLookupDTO
    }

    private func load() -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    func dto(for barcode: SupplementBarcode) -> SupplementLookupDTO? {
        load().first { barcode.variants.contains($0.code) }?.dto
    }

    func store(_ dto: SupplementLookupDTO, for barcode: SupplementBarcode) {
        var entries = load().filter { $0.code != barcode.canonical }
        entries.append(Entry(code: barcode.canonical, dto: dto))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
