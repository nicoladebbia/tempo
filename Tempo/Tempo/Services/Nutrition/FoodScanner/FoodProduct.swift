//
// FoodProduct.swift
// Tempo
//
// One packaged or generic food as the scanner, food search and the product
// screen see it — whatever the source (Open Food Facts, USDA, Tempo's
// built-in table, or a product the user added by photographing its label).
// Nutrients are per 100 g (per 100 ml for drinks); a serving is optional.
//

import Foundation

// MARK: - FoodProduct

struct FoodProduct: Codable, Equatable, Hashable, Sendable, Identifiable {
    enum Source: String, Codable, Sendable {
        case openFoodFacts
        case usda
        case builtIn
        case userAdded
    }

    /// Barcode for packaged products; "usda:<fdcId>" / "builtin:<name>" otherwise.
    var id: String
    var barcode: String?
    var name: String
    var brand: String?
    var source: Source

    /// Package size as printed ("500 g").
    var quantityLabel: String?
    /// Serving as printed ("150 g", "1 pot (125 g)") and its weight in grams.
    var servingLabel: String?
    var servingGrams: Double?
    var isBeverage: Bool = false

    var per100g: Nutrients

    /// Official Nutri-Score from the source (a–e) and its points. nil when
    /// the source has none — `FoodScore` then estimates it from `per100g`.
    var nutriScoreGrade: String?
    var nutriScorePoints: Int?
    /// NOVA processing group 1–4 (4 = ultra-processed).
    var novaGroup: Int?

    /// Additive codes, lowercase without prefix ("e330").
    var additives: [String] = []
    /// Allergen tags without prefix ("milk", "gluten").
    var allergens: [String] = []
    /// Label tags without prefix ("organic", "eu-organic", "vegan").
    var labels: [String] = []
    /// Category tags without prefix, most specific LAST ("yogurts", "skyr").
    var categories: [String] = []
    /// "palm-oil", "vegan", "non-vegan", "vegetarian", "maybe-vegan", …
    var ingredientsAnalysis: [String] = []
    var ingredientsText: String?

    var imageURL: URL?
    var imageSmallURL: URL?

    struct Nutrients: Codable, Equatable, Hashable, Sendable {
        var kcal: Double?
        var protein: Double?
        var carbs: Double?
        var sugars: Double?
        var fat: Double?
        var saturatedFat: Double?
        var fiber: Double?
        var salt: Double?

        /// Enough to log it and to score it.
        var hasCoreMacros: Bool {
            kcal != nil && protein != nil && carbs != nil && fat != nil
        }
    }

    var isOrganic: Bool {
        labels.contains { $0 == "organic" || $0 == "eu-organic" || $0.hasSuffix("-organic") || $0 == "ab-agriculture-biologique" }
    }

    /// Nutrients for `grams` of the product.
    func nutrients(forGrams grams: Double) -> Nutrients {
        let factor = grams / 100
        func scale(_ value: Double?) -> Double? {
            value.map { $0 * factor }
        }
        return Nutrients(
            kcal: scale(per100g.kcal),
            protein: scale(per100g.protein),
            carbs: scale(per100g.carbs),
            sugars: scale(per100g.sugars),
            fat: scale(per100g.fat),
            saturatedFat: scale(per100g.saturatedFat),
            fiber: scale(per100g.fiber),
            salt: scale(per100g.salt)
        )
    }

    /// Default portion when the user adds it: the printed serving, else 100 g.
    var defaultPortionGrams: Double {
        if let servingGrams, servingGrams > 0 {
            return servingGrams
        }
        return 100
    }

    /// "Arla · Skyr" style line.
    var displayName: String {
        if let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) {
            return "\(brand) \(name)"
        }
        return name
    }

    /// Grams parsed from a label like "150 g", "1 pot (125 g)", "250ml".
    static func grams(fromLabel label: String?) -> Double? {
        guard let label else {
            return nil
        }
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(g|gr|grams?|ml|mL|cl|l)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(label.startIndex..., in: label)
        guard let match = regex.matches(in: label, range: range).last,
              let numberRange = Range(match.range(at: 1), in: label),
              let unitRange = Range(match.range(at: 2), in: label),
              let value = Double(label[numberRange].replacingOccurrences(of: ",", with: "."))
        else {
            return nil
        }
        switch label[unitRange].lowercased() {
        case "cl": return value * 10
        case "l": return value * 1000
        default: return value
        }
    }
}
