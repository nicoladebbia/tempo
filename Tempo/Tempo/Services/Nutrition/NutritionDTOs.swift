//
// NutritionDTOs.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation

// MARK: - NutritionError

enum NutritionError: Error {
    case foodNotFound
    case barcodeNotFound
    case searchFailed(String)
    case apiKeyMissing
    case rateLimited(retryAfter: TimeInterval?)
    case networkError(String)
    case photoAnalysisFailed(String)
    case noFoodDetected
    case unclearPhoto
    case invalidResponse
    case mealNotFound
    case healthKitWriteFailed(String)
    case contextUnavailable
}

// MARK: - FoodSearchResult

struct FoodSearchResult: Identifiable, Equatable {
    let id: String
    let name: String
    let brand: String?
    let servingSize: Double
    let servingUnit: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let sodiumMg: Double?
    let source: FoodDataSource

    static func == (lhs: FoodSearchResult, rhs: FoodSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - MealFoodItemInput

struct MealFoodItemInput: Codable {
    let foodId: String
    let name: String
    let brand: String?
    let servings: Double
    let servingSize: Double
    let servingUnit: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let source: FoodDataSource
    /// Packaged products from the scanner / food search keep their barcode.
    var barcode: String? = nil

    /// Scaled values based on serving count.
    var totalCalories: Double {
        calories * servings
    }

    var totalProtein: Double {
        proteinGrams * servings
    }

    var totalCarbs: Double {
        carbsGrams * servings
    }

    var totalFat: Double {
        fatGrams * servings
    }
}

// MARK: - DailyNutritionSummary

struct DailyNutritionSummary {
    let date: Date
    let totalCalories: Double
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let mealsLogged: Int
    let calorieTarget: Double?
    let proteinTarget: Double?
    let carbsTarget: Double?
    let fatTarget: Double?

    var calorieProgress: Double? {
        guard let target = calorieTarget, target > 0 else {
            return nil
        }
        return totalCalories / target
    }

    var proteinProgress: Double? {
        guard let target = proteinTarget, target > 0 else {
            return nil
        }
        return totalProtein / target
    }

    var carbsProgress: Double? {
        guard let target = carbsTarget, target > 0 else {
            return nil
        }
        return totalCarbs / target
    }

    var fatProgress: Double? {
        guard let target = fatTarget, target > 0 else {
            return nil
        }
        return totalFat / target
    }

    static let empty = DailyNutritionSummary(
        date: Date(),
        totalCalories: 0,
        totalProtein: 0,
        totalCarbs: 0,
        totalFat: 0,
        mealsLogged: 0,
        calorieTarget: nil,
        proteinTarget: nil,
        carbsTarget: nil,
        fatTarget: nil
    )
}

// MARK: - MacroBudget

struct MacroBudget {
    let caloriesRemaining: Double
    let proteinRemaining: Double
    let carbsRemaining: Double
    let fatRemaining: Double
    let calorieTarget: Double
    let proteinTarget: Double
    let carbsTarget: Double
    let fatTarget: Double

    var isOverCalories: Bool {
        caloriesRemaining < 0
    }

    var isOverProtein: Bool {
        proteinRemaining < 0
    }

    static let empty = MacroBudget(
        caloriesRemaining: 0,
        proteinRemaining: 0,
        carbsRemaining: 0,
        fatRemaining: 0,
        calorieTarget: 0,
        proteinTarget: 0,
        carbsTarget: 0,
        fatTarget: 0
    )
}

// MARK: - ActiveNutritionTarget

struct ActiveNutritionTarget {
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let mealsPerDay: Int
}

// MARK: - PhotoAnalysisResult

struct PhotoAnalysisResult {
    let items: [PhotoFoodItem]
    let totalCalories: Double
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let confidence: PhotoConfidence
    let verdict: String

    struct PhotoFoodItem: Identifiable {
        let id: String
        let name: String
        let estimatedPortion: String
        let calories: Double
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let confidence: Double
        /// Top-3 alternative identifications from the vision model, ranked
        /// by confidence. The displayed item (name/macros above) is the
        /// model's best guess; alternatives let the user correct it
        /// ("this looks like chicken — or maybe pork?") without re-running
        /// the photo analysis. Empty when the model returned no
        /// alternatives or for legacy responses pre-top-N.
        let alternatives: [FoodCandidate]
    }

    /// One alternative identification from the vision model. Includes its
    /// own macro estimates so swapping to it is a complete replacement,
    /// not a name-only change.
    struct FoodCandidate: Identifiable {
        let id: String
        let name: String
        let estimatedPortion: String
        let calories: Double
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let confidence: Double
    }

    enum PhotoConfidence: String {
        case high
        case medium
        case low

        init(score: Double) {
            if score >= 0.8 {
                self = .high
            } else if score >= 0.5 {
                self = .medium
            } else {
                self = .low
            }
        }
    }
}

// MARK: - FdcSearchResponse

struct FdcSearchResponse: Codable {
    let totalHits: Int
    let currentPage: Int
    let totalPages: Int
    let foods: [FdcFoodItem]
}

// MARK: - FdcFoodItem

struct FdcFoodItem: Codable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandName: String?
    let brandOwner: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [FdcNutrient]

    /// Convert to app-level FoodSearchResult.
    func toFoodSearchResult() -> FoodSearchResult {
        let cal = nutrientValue(for: 1008) ?? 0 // Energy (kcal)
        let protein = nutrientValue(for: 1003) ?? 0 // Protein
        let carbs = nutrientValue(for: 1005) ?? 0 // Carbohydrates
        let fat = nutrientValue(for: 1004) ?? 0 // Total fat
        let fiber = nutrientValue(for: 1079) // Fiber
        let sugar = nutrientValue(for: 2000) // Sugars
        let sodium = nutrientValue(for: 1093) // Sodium

        let serving = servingSize ?? 100
        let unit = servingSizeUnit ?? "g"

        return FoodSearchResult(
            id: "usda_\(fdcId)",
            name: description.capitalized,
            brand: brandName ?? brandOwner,
            servingSize: serving,
            servingUnit: unit,
            calories: cal,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            sugarGrams: sugar,
            sodiumMg: sodium,
            source: .usda
        )
    }

    private func nutrientValue(for nutrientId: Int) -> Double? {
        foodNutrients.first { $0.nutrientId == nutrientId }?.value
    }
}

// MARK: - FdcNutrient

struct FdcNutrient: Codable {
    let nutrientId: Int
    let nutrientName: String
    let nutrientNumber: String?
    let unitName: String?
    let value: Double?
}

// MARK: - OFFProductResponse

struct OFFProductResponse: Codable {
    let code: String
    let status: Int
    let statusVerbose: String?
    let product: OFFProduct?

    enum CodingKeys: String, CodingKey {
        case code
        case status
        case product
        case statusVerbose = "status_verbose"
    }
}

// MARK: - OFFProduct

struct OFFProduct: Codable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: Double?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case brands
        case nutriments
        case productName = "product_name"
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
    }

    func toFoodSearchResult(barcode: String) -> FoodSearchResult? {
        guard let name = productName, !name.isEmpty else {
            return nil
        }
        let n = nutriments

        return FoodSearchResult(
            id: "off_\(barcode)",
            name: name,
            brand: brands,
            servingSize: servingQuantity ?? 100,
            servingUnit: "g",
            calories: n?.energyKcalServing ?? n?.energyKcal100g ?? 0,
            proteinGrams: n?.proteinsServing ?? n?.proteins100g ?? 0,
            carbsGrams: n?.carbohydratesServing ?? n?.carbohydrates100g ?? 0,
            fatGrams: n?.fatServing ?? n?.fat100g ?? 0,
            fiberGrams: n?.fiberServing ?? n?.fiber100g,
            sugarGrams: n?.sugarsServing ?? n?.sugars100g,
            sodiumMg: n?.sodiumServing.map { $0 * 1000 } ?? n?.sodium100g.map { $0 * 1000 },
            source: .openFoodFacts
        )
    }
}

// MARK: - OFFNutriments

struct OFFNutriments: Codable {
    let energyKcal100g: Double?
    let energyKcalServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let carbohydrates100g: Double?
    let carbohydratesServing: Double?
    let fat100g: Double?
    let fatServing: Double?
    let fiber100g: Double?
    let fiberServing: Double?
    let sugars100g: Double?
    let sugarsServing: Double?
    let sodium100g: Double?
    let sodiumServing: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
        case fiber100g = "fiber_100g"
        case fiberServing = "fiber_serving"
        case sugars100g = "sugars_100g"
        case sugarsServing = "sugars_serving"
        case sodium100g = "sodium_100g"
        case sodiumServing = "sodium_serving"
    }
}

// MARK: - ClaudeMessagesRequest

struct ClaudeMessagesRequest: Codable {
    let model: String
    let maxTokens: Int
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

// MARK: - ClaudeMessage

struct ClaudeMessage: Codable {
    let role: String
    let content: [ClaudeContent]
}

// MARK: - ClaudeContent

enum ClaudeContent: Codable {
    case text(String)
    case image(mediaType: String, data: String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }

    struct ImageSource: Codable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(mediaType, data):
            try container.encode("image", forKey: .type)
            try container.encode(ImageSource(type: "base64", mediaType: mediaType, data: data), forKey: .source)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "image":
            let source = try container.decode(ImageSource.self, forKey: .source)
            self = .image(mediaType: source.mediaType, data: source.data)
        default:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        }
    }
}

// MARK: - ClaudeMessagesResponse

struct ClaudeMessagesResponse: Codable {
    let id: String
    let content: [ClaudeResponseContent]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case stopReason = "stop_reason"
    }
}

// MARK: - ClaudeResponseContent

struct ClaudeResponseContent: Codable {
    let type: String
    let text: String?
}

// MARK: - ClaudeFoodAnalysis

/// Parsed JSON from Claude's analysis response.
struct ClaudeFoodAnalysis: Codable {
    let items: [ClaudeFoodItem]
    let confidence: Double
    let verdict: String

    struct ClaudeFoodItem: Codable {
        let name: String
        let portion: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let confidence: Double
        /// Up to 3 ranked alternative identifications. Optional so existing
        /// pre-top-N response shapes (and the mock service) decode cleanly.
        let alternatives: [ClaudeFoodAlternative]?
    }

    struct ClaudeFoodAlternative: Codable {
        let name: String
        let portion: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let confidence: Double
    }
}
