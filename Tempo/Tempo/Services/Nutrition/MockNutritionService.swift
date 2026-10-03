//
// MockNutritionService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - MockFoodSearchService

@Observable
final class MockFoodSearchService: FoodSearchServiceProtocol, @unchecked Sendable {
    func searchUSDA(query: String) async throws -> [FoodSearchResult] {
        try await Task.sleep(for: .milliseconds(200))
        return Self.sampleResults.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Sample Data

    static let sampleResults: [FoodSearchResult] = [
        FoodSearchResult(
            id: "usda_171287",
            name: "Chicken Breast, Grilled",
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            calories: 165,
            proteinGrams: 31,
            carbsGrams: 0,
            fatGrams: 3.6,
            fiberGrams: 0,
            sugarGrams: 0,
            sodiumMg: 74,
            source: .usda
        ),
        FoodSearchResult(
            id: "usda_168880",
            name: "Brown Rice, Cooked",
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            calories: 123,
            proteinGrams: 2.7,
            carbsGrams: 25.6,
            fatGrams: 1.0,
            fiberGrams: 1.6,
            sugarGrams: 0.4,
            sodiumMg: 4,
            source: .usda
        ),
        FoodSearchResult(
            id: "usda_170567",
            name: "Broccoli, Steamed",
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            calories: 35,
            proteinGrams: 2.4,
            carbsGrams: 7.2,
            fatGrams: 0.4,
            fiberGrams: 3.3,
            sugarGrams: 1.4,
            sodiumMg: 41,
            source: .usda
        ),
        FoodSearchResult(
            id: "usda_173944",
            name: "Egg, Whole, Hard-Boiled",
            brand: nil,
            servingSize: 50,
            servingUnit: "g",
            calories: 78,
            proteinGrams: 6.3,
            carbsGrams: 0.6,
            fatGrams: 5.3,
            fiberGrams: 0,
            sugarGrams: 0.6,
            sodiumMg: 62,
            source: .usda
        ),
        FoodSearchResult(
            id: "usda_170050",
            name: "Oats, Rolled, Dry",
            brand: nil,
            servingSize: 40,
            servingUnit: "g",
            calories: 152,
            proteinGrams: 5.3,
            carbsGrams: 27.4,
            fatGrams: 2.5,
            fiberGrams: 4.0,
            sugarGrams: 0.4,
            sodiumMg: 2,
            source: .usda
        ),
        FoodSearchResult(
            id: "usda_174608",
            name: "Salmon, Atlantic, Baked",
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            calories: 208,
            proteinGrams: 20.4,
            carbsGrams: 0,
            fatGrams: 13.4,
            fiberGrams: 0,
            sugarGrams: 0,
            sodiumMg: 59,
            source: .usda
        ),
        FoodSearchResult(
            id: "usda_168411",
            name: "Sweet Potato, Baked",
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            calories: 90,
            proteinGrams: 2.0,
            carbsGrams: 20.7,
            fatGrams: 0.1,
            fiberGrams: 3.3,
            sugarGrams: 6.5,
            sodiumMg: 36,
            source: .usda
        ),
        FoodSearchResult(
            id: "usda_173430",
            name: "Greek Yogurt, Plain, Nonfat",
            brand: nil,
            servingSize: 170,
            servingUnit: "g",
            calories: 100,
            proteinGrams: 17,
            carbsGrams: 6,
            fatGrams: 0.7,
            fiberGrams: 0,
            sugarGrams: 6,
            sodiumMg: 61,
            source: .usda
        ),
    ]
}

// MARK: - MockPhotoAnalysisService

@Observable
final class MockPhotoAnalysisService: PhotoAnalysisServiceProtocol, @unchecked Sendable {
    func analyzeMealPhoto(
        _ imageData: Data,
        remainingBudget: MacroBudget?
    ) async throws -> PhotoAnalysisResult {
        try await Task.sleep(for: .milliseconds(800))
        return PhotoAnalysisResult(
            items: [
                PhotoAnalysisResult.PhotoFoodItem(
                    id: "photo_1",
                    name: "Grilled Chicken Breast",
                    estimatedPortion: "~150g",
                    calories: 248,
                    proteinGrams: 46.5,
                    carbsGrams: 0,
                    fatGrams: 5.4,
                    confidence: 0.9,
                    alternatives: [
                        // Mock alternatives so the top-N picker has
                        // something to show in previews / dev builds.
                        PhotoAnalysisResult.FoodCandidate(
                            id: "photo_1_alt_pork",
                            name: "Grilled Pork Tenderloin",
                            estimatedPortion: "~150g",
                            calories: 215,
                            proteinGrams: 39.0,
                            carbsGrams: 0,
                            fatGrams: 5.7,
                            confidence: 0.55
                        ),
                        PhotoAnalysisResult.FoodCandidate(
                            id: "photo_1_alt_turkey",
                            name: "Grilled Turkey Breast",
                            estimatedPortion: "~150g",
                            calories: 200,
                            proteinGrams: 44.0,
                            carbsGrams: 0,
                            fatGrams: 2.2,
                            confidence: 0.40
                        ),
                    ]
                ),
                PhotoAnalysisResult.PhotoFoodItem(
                    id: "photo_2",
                    name: "Steamed Brown Rice",
                    estimatedPortion: "~1 cup (200g)",
                    calories: 246,
                    proteinGrams: 5.4,
                    carbsGrams: 51.2,
                    fatGrams: 2.0,
                    confidence: 0.85,
                    alternatives: [
                        PhotoAnalysisResult.FoodCandidate(
                            id: "photo_2_alt_white",
                            name: "Steamed White Rice",
                            estimatedPortion: "~1 cup (200g)",
                            calories: 260,
                            proteinGrams: 5.4,
                            carbsGrams: 56.0,
                            fatGrams: 0.4,
                            confidence: 0.55
                        ),
                    ]
                ),
                PhotoAnalysisResult.PhotoFoodItem(
                    id: "photo_3",
                    name: "Steamed Broccoli",
                    estimatedPortion: "~100g",
                    calories: 35,
                    proteinGrams: 2.4,
                    carbsGrams: 7.2,
                    fatGrams: 0.4,
                    confidence: 0.88,
                    alternatives: []
                ),
                PhotoAnalysisResult.PhotoFoodItem(
                    id: "photo_4",
                    name: "Green sauce",
                    estimatedPortion: "~30g",
                    calories: 60,
                    proteinGrams: 1.0,
                    carbsGrams: 2.0,
                    fatGrams: 5.5,
                    confidence: 0.4,
                    alternatives: [
                        PhotoAnalysisResult.FoodCandidate(
                            id: "photo_4_alt_guac",
                            name: "Guacamole",
                            estimatedPortion: "~30g",
                            calories: 50,
                            proteinGrams: 0.6,
                            carbsGrams: 2.7,
                            fatGrams: 4.5,
                            confidence: 0.35
                        ),
                    ]
                ),
            ],
            totalCalories: 589,
            totalProtein: 54.3,
            totalCarbs: 58.4,
            totalFat: 7.8,
            confidence: .high,
            verdict: "A solid post-training meal. High protein with complex carbs for recovery."
        )
    }
}

// MARK: - MockNutritionService

@Observable
final class MockNutritionService: NutritionServiceProtocol, @unchecked Sendable {
    let foodSearch: any FoodSearchServiceProtocol
    let photoAnalysis: any PhotoAnalysisServiceProtocol

    init() {
        foodSearch = MockFoodSearchService()
        photoAnalysis = MockPhotoAnalysisService()
    }
}
