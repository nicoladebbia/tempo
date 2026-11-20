import Foundation

// MARK: - Nutrient

/// Every nutrient the Nutritionist tracks, with its USDA FoodData Central
/// `nutrientId` (verified against a live `foods/search` response, 2026-11-20).
/// Raw values are stable wire keys: they are stored in the food cache and sent
/// to the app, so never rename a case.
///
/// Units are fixed per nutrient (USDA reports one unit per nutrient id), so a
/// `[Nutrient: Double]` map is always in `unit`, per 100 g of food.
enum Nutrient: String, CaseIterable, Codable, Sendable {
    // Vitamins
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK
    case thiamin, riboflavin, niacin, pantothenicAcid, vitaminB6, folate, vitaminB12, choline
    // Minerals
    case calcium, iron, magnesium, phosphorus, potassium, sodium, zinc, copper, manganese, selenium
    // Fats
    case omega3ALA, epa, dha, saturatedFat, cholesterol
    // Other
    case fiber

    enum Unit: String, Codable, Sendable {
        case mg, mcg, g
    }

    enum Category: String, Codable, Sendable {
        case vitamin, mineral, fat, other
    }

    /// USDA nutrient id used in `foodNutrients[].nutrientId`.
    var usdaId: Int {
        switch self {
        case .vitaminA: 1106 // Vitamin A, RAE
        case .vitaminC: 1162
        case .vitaminD: 1114 // Vitamin D (D2 + D3), µg
        case .vitaminE: 1109 // alpha-tocopherol
        case .vitaminK: 1185 // phylloquinone
        case .thiamin: 1165
        case .riboflavin: 1166
        case .niacin: 1167
        case .pantothenicAcid: 1170
        case .vitaminB6: 1175
        case .folate: 1190 // Folate, DFE
        case .vitaminB12: 1178
        case .choline: 1180
        case .calcium: 1087
        case .iron: 1089
        case .magnesium: 1090
        case .phosphorus: 1091
        case .potassium: 1092
        case .sodium: 1093
        case .zinc: 1095
        case .copper: 1098
        case .manganese: 1101
        case .selenium: 1103
        case .omega3ALA: 1404
        case .epa: 1278
        case .dha: 1272
        case .saturatedFat: 1258
        case .cholesterol: 1253
        case .fiber: 1079
        }
    }

    var unit: Unit {
        switch self {
        case .vitaminA, .vitaminD, .vitaminK, .folate, .vitaminB12, .selenium:
            .mcg
        case .omega3ALA, .epa, .dha, .saturatedFat, .fiber:
            .g
        default:
            .mg
        }
    }

    var category: Category {
        switch self {
        case .vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .thiamin, .riboflavin, .niacin,
             .pantothenicAcid, .vitaminB6, .folate, .vitaminB12, .choline:
            .vitamin
        case .calcium, .iron, .magnesium, .phosphorus, .potassium, .sodium, .zinc, .copper, .manganese, .selenium:
            .mineral
        case .omega3ALA, .epa, .dha, .saturatedFat, .cholesterol:
            .fat
        case .fiber:
            .other
        }
    }

    /// Plain-English name for the app.
    var displayName: String {
        switch self {
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminK: "Vitamin K"
        case .thiamin: "Thiamin (B1)"
        case .riboflavin: "Riboflavin (B2)"
        case .niacin: "Niacin (B3)"
        case .pantothenicAcid: "Pantothenic acid (B5)"
        case .vitaminB6: "Vitamin B6"
        case .folate: "Folate"
        case .vitaminB12: "Vitamin B12"
        case .choline: "Choline"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .magnesium: "Magnesium"
        case .phosphorus: "Phosphorus"
        case .potassium: "Potassium"
        case .sodium: "Sodium"
        case .zinc: "Zinc"
        case .copper: "Copper"
        case .manganese: "Manganese"
        case .selenium: "Selenium"
        case .omega3ALA: "Omega-3 (ALA)"
        case .epa: "EPA"
        case .dha: "DHA"
        case .saturatedFat: "Saturated fat"
        case .cholesterol: "Cholesterol"
        case .fiber: "Fiber"
        }
    }

    /// Reverse lookup used when reading USDA rows.
    static let byUSDAId: [Int: Nutrient] = Dictionary(uniqueKeysWithValues: allCases.map { ($0.usdaId, $0) })
}

// MARK: - Micronutrient extraction

enum MicronutrientExtractor {
    /// Per-100g amounts for every catalogued nutrient present in a USDA food,
    /// keyed by `Nutrient.rawValue` (the cache and wire format). Missing
    /// nutrients are simply absent: absent means "USDA doesn't report it for
    /// this food", never "zero". Negative values (rounding artefacts) clamp to 0.
    static func extract(from food: USDASearchRawResponse.Food) -> [String: Double] {
        var out: [String: Double] = [:]
        for row in food.foodNutrients ?? [] {
            guard let id = row.nutrientId, let nutrient = Nutrient.byUSDAId[id], let value = row.value else { continue }
            out[nutrient.rawValue] = max(0, value)
        }
        return out
    }
}
