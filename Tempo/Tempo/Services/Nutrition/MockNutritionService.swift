//
// MockNutritionService.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
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

    func lookupBarcode(_ barcode: String) async throws -> FoodSearchResult? {
        try await Task.sleep(for: .milliseconds(150))
        return FoodSearchResult(
            id: "off_\(barcode)",
            name: "Fage Total 0% Greek Yogurt",
            brand: "Fage",
            servingSize: 170,
            servingUnit: "g",
            calories: 90,
            proteinGrams: 18,
            carbsGrams: 5,
            fatGrams: 0,
            fiberGrams: 0,
            sugarGrams: 5,
            sodiumMg: 65,
            source: .openFoodFacts
        )
    }

    func searchLocal(query: String, context: ModelContext) -> [CachedFood] {
        []
    }

    func cacheFood(_ food: FoodSearchResult, context: ModelContext) {
        // No-op in mock
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

// MARK: - MockMealLoggingService

@Observable
final class MockMealLoggingService: MealLoggingServiceProtocol, @unchecked Sendable {
    func logMeal(
        type: MealType,
        items: [MealFoodItemInput],
        photo: Data?,
        source: MealSource,
        context: ModelContext
    ) async throws -> MealLog {
        try await Task.sleep(for: .milliseconds(100))
        let foodItems = items.map { MealFoodItem(from: $0) }
        return MealLog(type: type, dayDate: Date(), source: source, photo: photo, items: foodItems)
    }

    func updateMeal(_ meal: MealLog, items: [MealFoodItemInput], context: ModelContext) throws {
        // No-op in mock
    }

    func deleteMeal(_ meal: MealLog, context: ModelContext) throws {
        // No-op in mock
    }

    func fetchTodayMeals(context: ModelContext) -> [MealLog] {
        Self.sampleMeals()
    }

    func fetchMeals(for date: Date, context: ModelContext) -> [MealLog] {
        Self.sampleMeals()
    }

    func todaySummary(context: ModelContext) -> DailyNutritionSummary {
        DailyNutritionSummary(
            date: Calendar.current.startOfDay(for: Date()),
            totalCalories: 1850,
            totalProtein: 142,
            totalCarbs: 210,
            totalFat: 58,
            mealsLogged: 3,
            calorieTarget: 2400,
            proteinTarget: 180,
            carbsTarget: 280,
            fatTarget: 80
        )
    }

    func syncToHealthKit(_ meal: MealLog) async throws {
        // No-op in mock
    }

    // MARK: - Sample Data

    private static func sampleMeals() -> [MealLog] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let breakfastItems = [
            MealFoodItem(from: MealFoodItemInput(
                foodId: "usda_170050",
                name: "Oats, Rolled",
                brand: nil,
                servings: 1.5,
                servingSize: 40,
                servingUnit: "g",
                calories: 152,
                proteinGrams: 5.3,
                carbsGrams: 27.4,
                fatGrams: 2.5,
                source: .usda
            )),
            MealFoodItem(from: MealFoodItemInput(
                foodId: "usda_173430",
                name: "Greek Yogurt",
                brand: nil,
                servings: 1,
                servingSize: 170,
                servingUnit: "g",
                calories: 100,
                proteinGrams: 17,
                carbsGrams: 6,
                fatGrams: 0.7,
                source: .usda
            )),
        ]

        let lunchItems = [
            MealFoodItem(from: MealFoodItemInput(
                foodId: "usda_171287",
                name: "Chicken Breast, Grilled",
                brand: nil,
                servings: 1.5,
                servingSize: 100,
                servingUnit: "g",
                calories: 165,
                proteinGrams: 31,
                carbsGrams: 0,
                fatGrams: 3.6,
                source: .usda
            )),
            MealFoodItem(from: MealFoodItemInput(
                foodId: "usda_168880",
                name: "Brown Rice",
                brand: nil,
                servings: 2,
                servingSize: 100,
                servingUnit: "g",
                calories: 123,
                proteinGrams: 2.7,
                carbsGrams: 25.6,
                fatGrams: 1.0,
                source: .usda
            )),
            MealFoodItem(from: MealFoodItemInput(
                foodId: "usda_170567",
                name: "Broccoli, Steamed",
                brand: nil,
                servings: 1,
                servingSize: 100,
                servingUnit: "g",
                calories: 35,
                proteinGrams: 2.4,
                carbsGrams: 7.2,
                fatGrams: 0.4,
                source: .usda
            )),
        ]

        let snackItems = [
            MealFoodItem(from: MealFoodItemInput(
                foodId: "usda_173944",
                name: "Hard-Boiled Eggs",
                brand: nil,
                servings: 3,
                servingSize: 50,
                servingUnit: "g",
                calories: 78,
                proteinGrams: 6.3,
                carbsGrams: 0.6,
                fatGrams: 5.3,
                source: .usda
            )),
        ]

        return [
            MealLog(type: .breakfast, dayDate: today, source: .manual, items: breakfastItems),
            MealLog(type: .lunch, dayDate: today, source: .usdaSearch, items: lunchItems),
            MealLog(type: .snack, dayDate: today, source: .manual, items: snackItems),
        ]
    }
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
                    confidence: 0.9
                ),
                PhotoAnalysisResult.PhotoFoodItem(
                    id: "photo_2",
                    name: "Steamed Brown Rice",
                    estimatedPortion: "~1 cup (200g)",
                    calories: 246,
                    proteinGrams: 5.4,
                    carbsGrams: 51.2,
                    fatGrams: 2.0,
                    confidence: 0.85
                ),
                PhotoAnalysisResult.PhotoFoodItem(
                    id: "photo_3",
                    name: "Steamed Broccoli",
                    estimatedPortion: "~100g",
                    calories: 35,
                    proteinGrams: 2.4,
                    carbsGrams: 7.2,
                    fatGrams: 0.4,
                    confidence: 0.88
                ),
            ],
            totalCalories: 529,
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
    let mealLogging: any MealLoggingServiceProtocol
    let photoAnalysis: any PhotoAnalysisServiceProtocol

    init() {
        foodSearch = MockFoodSearchService()
        mealLogging = MockMealLoggingService()
        photoAnalysis = MockPhotoAnalysisService()
    }

    func activeTarget(context: ModelContext) -> ActiveNutritionTarget? {
        ActiveNutritionTarget(
            calories: 2400,
            proteinGrams: 180,
            carbsGrams: 280,
            fatGrams: 80,
            mealsPerDay: 4
        )
    }

    func remainingBudget(context: ModelContext) -> MacroBudget {
        MacroBudget(
            caloriesRemaining: 550,
            proteinRemaining: 38,
            carbsRemaining: 70,
            fatRemaining: 22,
            calorieTarget: 2400,
            proteinTarget: 180,
            carbsTarget: 280,
            fatTarget: 80
        )
    }
}
