//
// USDAFoodClient.swift
// Tempo
//
// Generic foods ("chicken breast", "basmati rice") from USDA FoodData
// Central, through our backend (GET /v1/foods/search) so the USDA key stays
// server-side. Needs sign-in; food search degrades to Open Food Facts +
// Tempo's built-in table without it.
//

import Foundation

// MARK: - GenericFoodSearching

protocol GenericFoodSearching: Sendable {
    func search(_ query: String, limit: Int) async throws -> [FoodProduct]
}

// MARK: - USDAFoodClient

struct USDAFoodClient: GenericFoodSearching {
    let apiClient: APIClient

    func search(_ query: String, limit: Int = 15) async throws -> [FoodProduct] {
        let response: FoodSearchResponseDTO = try await apiClient.request(
            .foodSearch(),
            queryItems: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.foods.map(\.product)
    }
}

// MARK: - FoodSearchResponseDTO

struct FoodSearchResponseDTO: Decodable, Sendable {
    let foods: [FoodDTO]
}

// MARK: - FoodDTO

struct FoodDTO: Decodable, Sendable {
    let fdcID: Int
    let name: String
    let brand: String?
    let barcode: String?
    let dataType: String
    let servingSize: Double?
    let servingUnit: String?
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let sugars: Double?
    let saturatedFat: Double?
    let fiber: Double?
    let salt: Double?

    enum CodingKeys: String, CodingKey {
        case fdcID = "fdc_id"
        case name, brand, barcode
        case dataType = "data_type"
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case kcal, protein, carbs, fat, sugars
        case saturatedFat = "saturated_fat"
        case fiber, salt
    }

    var product: FoodProduct {
        let unit = servingUnit?.lowercased()
        let servingGrams: Double? = if let servingSize, unit == "g" || unit == "grm" || unit == "ml" || unit == "mlt" {
            servingSize
        } else {
            nil
        }
        return FoodProduct(
            id: "usda:\(fdcID)",
            barcode: barcode,
            name: name,
            brand: brand,
            source: .usda,
            servingLabel: servingGrams.map { "\(Int($0.rounded())) g" },
            servingGrams: servingGrams,
            per100g: FoodProduct.Nutrients(
                kcal: kcal, protein: protein, carbs: carbs, sugars: sugars,
                fat: fat, saturatedFat: saturatedFat, fiber: fiber, salt: salt
            )
        )
    }
}

extension APIEndpoint where Response == FoodSearchResponseDTO {
    static func foodSearch() -> Self {
        APIEndpoint(path: "/v1/foods/search")
    }
}
