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
        // Int(v.rounded()) traps on NaN/inf and beyond Int range.
        guard value.isFinite else {
            return "0"
        }
        if abs(value) > 1e9 {
            return String(format: "%.0f", value)
        }
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

    /// `number` with the user's decimal separator ("0,8" in Italian), for text on
    /// screen. `number` itself keeps the point: text for the AI and logic use it.
    static func displayNumber(_ value: Double) -> String {
        let plain = number(value)
        guard let separator = Locale.current.decimalSeparator, separator != "." else {
            return plain
        }
        return plain.replacingOccurrences(of: ".", with: separator)
    }

    /// Text for an editable field (no unit), in the user's decimal format.
    /// The edit sheet reads a comma back as a point.
    static func editText(_ value: Double) -> String {
        displayNumber(value)
    }

    /// Approximate weight of a countable quantity, e.g. "~400 g". nil when the
    /// food has no per-unit weight or the unit is already mass/volume.
    static func approxWeight(
        quantity: Double,
        unit: PantryUnit,
        canonicalName: String,
        purchased: Bool = false,
        english: Bool = false
    ) -> String? {
        // Staples (salt, olive oil) carry a 1 g placeholder weight, so a hint
        // like "1 bottle (~1 g)" is wrong: omit it for staples and <= 1 g.
        if FoodMacroDatabase.naturalPortions[canonicalName.lowercased()]?.isStaple == true {
            return nil
        }
        guard unit.isCountable, unit != .servings,
              let grams = unit.gramsApprox(quantity: quantity, foodName: canonicalName, purchased: purchased),
              grams > 1
        else {
            return nil
        }
        if grams >= 1000 {
            return "~" + (english ? number(grams / 1000) : displayNumber(grams / 1000)) + " kg"
        }
        return "~\(Int(grams.rounded())) g"
    }

    /// "500g", "3 pcs", "0.8 pack (~400 g)".
    /// `english: true` keeps the unit words English, for text sent to the AI.
    static func text(
        quantity: Double,
        unit: PantryUnit,
        canonicalName: String? = nil,
        purchased: Bool = false,
        english: Bool = false
    ) -> String {
        let n = english ? number(quantity) : displayNumber(quantity)
        guard unit.isCountable else {
            return "\(n)\(english ? unit.englishName : unit.displayName)"
        }
        var out = "\(n) \(english ? unit.englishLabel(forQuantity: quantity) : unit.label(forQuantity: quantity))"
        let isWhole = abs(quantity - quantity.rounded()) < 0.005
        // Weight hint for containers always; for pieces only once fractional
        // (3 whole pcs needs no gram hint, 0.5 pc does).
        if let canonicalName, unit.isContainer || !isWhole,
           let weight = approxWeight(quantity: quantity, unit: unit, canonicalName: canonicalName, purchased: purchased, english: english)
        {
            out += " (\(weight))"
        }
        return out
    }
}
