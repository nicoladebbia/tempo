//
// PantryQuantityFormatter.swift
// Tempo
//
// Created by Tempo on 30/09/2026.
//
//

import Foundation

/// One place that turns a pantry quantity into text, so every surface (pantry
/// rows, edit sheet, voice confirm, grocery rows) reads the same. Container
/// and count units are tracked in fractions, so 100 g eaten from a 500 g pack
/// shows "0.8 pack (~400 g)" rather than "1 pack" or "0 pack".
enum PantryQuantityFormatter {
    /// "1", "0.8", "0.83", "12.5" — never "0.80000000001".
    static func number(_ value: Double) -> String {
        let v = PantryDecrementService.clean(value)
        if abs(v - v.rounded()) < 0.005 {
            return String(Int(v.rounded()))
        }
        let formatted = abs(v) >= 10 ? String(format: "%.1f", v) : String(format: "%.2f", v)
        var trimmed = formatted
        while trimmed.hasSuffix("0") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }

    /// Text for an editable field (decimal point, no unit).
    static func editText(_ value: Double) -> String {
        number(value)
    }

    /// Approximate weight of a countable quantity, e.g. "~400 g". nil when the
    /// food has no per-unit weight or the unit is already mass/volume.
    static func approxWeight(quantity: Double, unit: PantryUnit, canonicalName: String) -> String? {
        guard unit.isCountable, unit != .servings,
              let grams = unit.gramsApprox(quantity: quantity, foodName: canonicalName),
              grams > 0
        else {
            return nil
        }
        if grams >= 1000 {
            return "~" + number(grams / 1000) + " kg"
        }
        return "~\(Int(grams.rounded())) g"
    }

    /// "500g", "3 pcs", "0.8 pack (~400 g)".
    static func text(quantity: Double, unit: PantryUnit, canonicalName: String? = nil) -> String {
        let n = number(quantity)
        guard unit.isCountable else {
            return "\(n)\(unit.displayName)"
        }
        var out = "\(n) \(unit.label(forQuantity: quantity))"
        let isWhole = abs(quantity - quantity.rounded()) < 0.005
        // Weight hint for containers always; for pieces only once fractional
        // (3 whole pcs needs no gram hint, 0.5 pc does).
        if let canonicalName, unit.isContainer || !isWhole,
           let weight = approxWeight(quantity: quantity, unit: unit, canonicalName: canonicalName)
        {
            out += " (\(weight))"
        }
        return out
    }
}
