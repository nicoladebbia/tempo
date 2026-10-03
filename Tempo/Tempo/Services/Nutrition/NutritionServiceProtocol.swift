//
// NutritionServiceProtocol.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - NutritionServiceProtocol

// Composes food search, meal logging, and photo analysis sub-services.

protocol NutritionServiceProtocol: Sendable {
    var foodSearch: any FoodSearchServiceProtocol { get }
    var photoAnalysis: any PhotoAnalysisServiceProtocol { get }
}

// MARK: - NutritionService

@Observable
final class NutritionService: NutritionServiceProtocol, @unchecked Sendable {
    let foodSearch: any FoodSearchServiceProtocol
    let photoAnalysis: any PhotoAnalysisServiceProtocol

    init(
        foodSearch: any FoodSearchServiceProtocol,
        photoAnalysis: any PhotoAnalysisServiceProtocol
    ) {
        self.foodSearch = foodSearch
        self.photoAnalysis = photoAnalysis
    }

    // MARK: - Factory

    static func live(apiClient: APIClient) -> NutritionService {
        let foodSearch = FoodSearchService()
        // Per INTELLIGENCE_REMEDIATION_PLAN.md §3 — photo analysis now proxies
        // through the backend instead of calling Anthropic directly.
        let photoAnalysis = PhotoAnalysisService(foodSearch: foodSearch, apiClient: apiClient)
        return NutritionService(
            foodSearch: foodSearch,
            photoAnalysis: photoAnalysis
        )
    }
}
