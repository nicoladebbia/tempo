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
