//
// LabelFacts.swift
// Tempo
//
// Pure logic behind the scanned-product label page: UK FSA traffic-light
// levels, the per-100 g / per-serving switch, and which of the product's
// allergens the user has flagged. No UI here so it can be unit-tested.
//

import Foundation

enum LabelFacts {
    // MARK: - Traffic lights

    enum Level: Int, Comparable, Sendable {
        case low
        case medium
        case high

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            }
        }
    }

    enum Nutrient: CaseIterable, Sendable {
        case fat
        case saturatedFat
        case sugars
        case salt
    }

    /// UK FSA front-of-pack thresholds. Solids per 100 g: fat 3 / 17.5,
    /// saturates 1.5 / 5, sugars 5 / 22.5, salt 0.3 / 1.5. Drinks per 100 ml
    /// use the lower drink table. `medium` is the top of "low", `high` the top
    /// of "medium": a value at exactly the limit stays in the lower band.
    static func thresholds(for nutrient: Nutrient, isBeverage: Bool) -> (medium: Double, high: Double) {
        switch (nutrient, isBeverage) {
        case (.fat, false): (3, 17.5)
        case (.fat, true): (1.5, 8.75)
        case (.saturatedFat, false): (1.5, 5)
        case (.saturatedFat, true): (0.75, 2.5)
        case (.sugars, false): (5, 22.5)
        case (.sugars, true): (2.5, 11.25)
        case (.salt, false): (0.3, 1.5)
        case (.salt, true): (0.3, 0.75)
        }
    }

    /// Level of a value expressed PER 100 g (or 100 ml). nil when unknown.
    static func level(of nutrient: Nutrient, per100: Double?, isBeverage: Bool) -> Level? {
        guard let per100 else {
            return nil
        }
        let limits = thresholds(for: nutrient, isBeverage: isBeverage)
        if per100 > limits.high {
            return .high
        }
        return per100 > limits.medium ? .medium : .low
    }

    static func level(of nutrient: Nutrient, in product: FoodProduct) -> Level? {
        let n = product.per100g
        let value: Double? = switch nutrient {
        case .fat: n.fat
        case .saturatedFat: n.saturatedFat
        case .sugars: n.sugars
        case .salt: n.salt
        }
        return level(of: nutrient, per100: value, isBeverage: product.isBeverage)
    }

    // MARK: - Basis (per 100 g / per serving)

    enum Basis: Equatable, Sendable {
        case per100
        case perServing
    }

    /// The printed serving, when it is a usable number that differs from 100.
    static func servingGrams(of product: FoodProduct) -> Double? {
        guard let grams = product.servingGrams, grams > 0, grams != 100 else {
            return nil
        }
        return grams
    }

    /// Grams the displayed numbers (and the Log button) refer to.
    static func grams(for basis: Basis, product: FoodProduct) -> Double {
        if basis == .perServing, let serving = servingGrams(of: product) {
            return serving
        }
        return 100
    }

    static func nutrients(for basis: Basis, product: FoodProduct) -> FoodProduct.Nutrients {
        basis == .per100 || servingGrams(of: product) == nil
            ? product.per100g
            : product.nutrients(forGrams: grams(for: basis, product: product))
    }

    // MARK: - Allergens vs the user's profile

    /// True when `displayAllergen` ("Milk", "Tree nuts"…) is something the
    /// user told Tempo to avoid: a diet flag or a free-text allergy.
    static func isFlagged(displayAllergen: String, context: FoodFitContext) -> Bool {
        switch displayAllergen {
        case "Gluten" where context.glutenFree: return true
        case "Milk" where context.lactoseFree: return true
        case "Tree nuts" where context.nutFree, "Peanuts" where context.nutFree: return true
        case "Crustaceans" where context.shellfishAllergy, "Molluscs" where context.shellfishAllergy: return true
        default: break
        }
        let name = displayAllergen.lowercased()
        return context.allergies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { $0.count >= 3 && name.contains($0) }
    }
}
