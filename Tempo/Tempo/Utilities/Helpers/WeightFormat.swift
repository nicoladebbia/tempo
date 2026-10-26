//
// WeightFormat.swift
// Tempo
//
// The single place a stored-kg weight becomes text. Rounds to 0.1 (so 155 lbs
// stored as 70.3068 kg reads "155", not a truncated "154", and 62.5 kg reads
// "62.5", not "62"), drops a trailing ".0", and always uses the user's unit.
//

import Foundation

enum WeightFormat {
    /// Number only, e.g. "155", "62.5". `kg` is the stored value.
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

    /// "155 lbs × 5", or "BW × 10" when the set had no external load.
    static func setText(kg: Double, reps: Int, unit: WeightUnit) -> String {
        kg > 0 ? "\(text(kg: kg, unit: unit)) × \(reps)" : "BW × \(reps)"
    }

    /// Parses a user-typed decimal that may use a comma ("5,2" → 5.2).
    static func parseDecimal(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    /// Volume totals: "12.4k lbs" from 1000 up, otherwise whole units.
    static func volumeText(kg: Double, unit: WeightUnit) -> String {
        let value = WeightUnit.kg.convert(kg, to: unit)
        if value >= 1000 {
            return String(format: "%.1fk %@", value / 1000, unit.abbreviation)
        }
        return "\(Int(value.rounded())) \(unit.abbreviation)"
    }
}

/// One set that actually happened: the heaviest session's top set, with ties
/// broken by reps — never the heaviest weight from one session glued to the
/// most reps from another.
struct ExerciseBestSet: Equatable {
    let weightKg: Double
    let reps: Int

    static func pick(from history: [ExerciseHistory]) -> ExerciseBestSet? {
        pick(pairs: history.compactMap { row -> (weightKg: Double, reps: Int)? in
            guard let reps = row.bestSetReps, reps > 0 else { return nil }
            return (row.bestSetWeight ?? 0, reps)
        })
    }

    static func pick(pairs: [(weightKg: Double, reps: Int)]) -> ExerciseBestSet? {
        let best = pairs.max { a, b in
            a.weightKg != b.weightKg ? a.weightKg < b.weightKg : a.reps < b.reps
        }
        return best.map { ExerciseBestSet(weightKg: $0.weightKg, reps: $0.reps) }
    }
}
