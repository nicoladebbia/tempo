//
// PackageSizeParser.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation

/// Parses `FoodProduct.quantityLabel` ("500 g", "1 L", "6 x 33 cl", "12 oz")
/// into a pantry quantity + unit, for barcode→pantry prefill. Best-effort:
/// unparseable labels return nil and the barcode flow falls back to "1
/// piece" so the user can just fix it before saving.
enum PackageSizeParser {
    static func parse(_ label: String?) -> (quantity: Double, unit: PantryUnit)? {
        guard let label else {
            return nil
        }
        let normalized = label
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            return nil
        }

        // Multipack: "6 x 33 cl", "4x125g", "6 × 330ml"
        if let multipack = parseMultipack(normalized) {
            return multipack
        }
        return parseSingle(normalized)
    }

    private static func parseMultipack(_ text: String) -> (Double, PantryUnit)? {
        // "<count> x <amount><unit>" with optional spaces, 'x' or '×'.
        let pattern = #"(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)\s*([a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        guard let countRange = Range(match.range(at: 1), in: text),
              let amountRange = Range(match.range(at: 2), in: text),
              let unitRange = Range(match.range(at: 3), in: text),
              let count = Double(text[countRange]),
              let amount = Double(text[amountRange]),
              let unit = canonicalUnit(String(text[unitRange]))
        else {
            return nil
        }
        let (grams, base) = normalizeToBase(amount: amount, unit: unit)
        return (count * grams, base)
    }

    private static func parseSingle(_ text: String) -> (Double, PantryUnit)? {
        let pattern = #"(\d+(?:\.\d+)?)\s*([a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        guard let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let amount = Double(text[amountRange]),
              let unit = canonicalUnit(String(text[unitRange]))
        else {
            return nil
        }
        return normalizeToBase(amount: amount, unit: unit)
    }

    /// Maps a raw label unit to a `PantryUnit`, folding sub-units (cl, mg)
    /// into the nearest supported one via `normalizeToBase`.
    private enum RawUnit: String {
        case g
        case kg
        case mg
        case ml
        case cl
        case l
        case oz
        case lb
        case lbs
    }

    private static func canonicalUnit(_ raw: String) -> RawUnit? {
        RawUnit(rawValue: raw)
    }

    /// Converts to the PantryUnit family the app already speaks, folding cl→ml (×10) and mg→g (÷1000).
    private static func normalizeToBase(amount: Double, unit: RawUnit) -> (Double, PantryUnit) {
        switch unit {
        case .g: (amount, .grams)
        case .kg: (amount, .kilograms)
        case .mg: (amount / 1000, .grams)
        case .ml: (amount, .milliliters)
        case .cl: (amount * 10, .milliliters)
        case .l: (amount, .liters)
        case .oz: (amount, .ounces)
        case .lb,
             .lbs: (amount, .pounds)
        }
    }
}
