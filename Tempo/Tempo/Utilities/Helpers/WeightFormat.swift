//
// WeightFormat.swift
// Tempo
//
// The single place a stored-kg weight becomes text. Rounds to 0.1 (so 155 lbs,
// stored as 70.3068 kg, reads "155" — not a truncated "154" — and 62.5 kg reads
// "62.5", not "62"), drops a trailing ".0", and always speaks the user's unit.
//

import Foundation

enum WeightFormat {
    /// Number only for a stored-kg value, e.g. "155", "62.5".
    static func number(kg: Double, unit: WeightUnit) -> String {
        number(WeightUnit.kg.convert(kg, to: unit))
    }

    /// Number only for a value already in the display unit.
    static func number(_ displayValue: Double) -> String {
        let rounded = (displayValue * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    /// "155 lbs" / "62.5 kg".
    static func text(kg: Double, unit: WeightUnit) -> String {
        "\(number(kg: kg, unit: unit)) \(unit.abbreviation)"
    }

    /// A set's load: "62.5 kg", or "BW" when it carried no external weight —
    /// a bodyweight set never reads "0 kg".
    static func load(kg: Double?, unit: WeightUnit) -> String {
        guard let kg, kg > 0 else {
            return "BW"
        }
        return text(kg: kg, unit: unit)
    }

    /// A bodyweight-style set's load: "BW", "BW + 10 kg" or "BW − 15 kg" (assist).
    /// Never the effective bodyweight total — that moves with the lifter's weight.
    static func bodyweightLoad(addedKg: Double?, unit: WeightUnit) -> String {
        guard let addedKg, abs(addedKg) >= 0.05 else {
            return "BW"
        }
        let sign = addedKg > 0 ? "+" : "−"
        return "BW \(sign) \(text(kg: abs(addedKg), unit: unit))"
    }

    /// A history row's top-set load, equipment-aware: bodyweight-style lifts
    /// read "BW" / "BW + 10 kg", everything else "62.5 kg" (or "BW" at 0).
    static func setLoad(kg: Double?, addedKg: Double?, bodyweight: Bool, unit: WeightUnit) -> String {
        bodyweight ? bodyweightLoad(addedKg: addedKg, unit: unit) : load(kg: kg, unit: unit)
    }

    /// Compact load for tight chips: "62.5", or "BW".
    static func compactLoad(kg: Double?, unit: WeightUnit) -> String {
        guard let kg, kg > 0 else {
            return "BW"
        }
        return number(kg: kg, unit: unit)
    }

    /// Volume totals: "12.4k lbs" from 1,000 up, otherwise whole units.
    static func volumeText(kg: Double, unit: WeightUnit) -> String {
        let value = WeightUnit.kg.convert(kg, to: unit)
        if value >= 1000 {
            return String(format: "%.1fk %@", value / 1000, unit.abbreviation)
        }
        return "\(Int(value.rounded())) \(unit.abbreviation)"
    }

    /// A number the athlete typed, accepting a decimal comma ("5,2" → 5.2) as
    /// the `.decimalPad` keyboard produces it in comma locales.
    static func parseDecimal(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else {
            return nil
        }
        return Double(cleaned)
    }
}
