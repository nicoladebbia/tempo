//
// CachedFood.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

@Model
final class CachedFood {
    // MARK: - Identity

    @Attribute(.unique)
    var id: String

    // MARK: - Food Info

    var name: String

    var brand: String?

    // MARK: - Macros Per Serving

    var servingSize: Double

    var servingUnit: String

    var calories: Double

    var proteinGrams: Double

    var carbsGrams: Double

    var fatGrams: Double

    var fiberGrams: Double?

    var sugarGrams: Double?

    /// Sodium in milligrams per serving.
    var sodiumMg: Double?

    // MARK: - Data Provenance

    var sourceRaw: String

    // MARK: - Cache Metadata

    var searchKeywords: String

    var cachedAt: Date

    var useCount: Int

    // MARK: - Computed Properties

    @Transient
    var source: FoodDataSource {
        FoodDataSource(rawValue: sourceRaw) ?? .cached
    }

    // MARK: - Init

    init(from result: FoodSearchResult) {
        id = result.id
        name = result.name
        brand = result.brand
        servingSize = result.servingSize
        servingUnit = result.servingUnit
        calories = result.calories
        proteinGrams = result.proteinGrams
        carbsGrams = result.carbsGrams
        fatGrams = result.fatGrams
        fiberGrams = result.fiberGrams
        sugarGrams = result.sugarGrams
        sodiumMg = result.sodiumMg
        sourceRaw = result.source.rawValue
        var keywords = result.name.lowercased()
        if let brand = result.brand {
            keywords += " \(brand.lowercased())"
        }
        searchKeywords = keywords
        cachedAt = Date()
        useCount = 0
    }

    // MARK: - Conversion

    func toFoodSearchResult() -> FoodSearchResult {
        FoodSearchResult(
            id: id,
            name: name,
            brand: brand,
            servingSize: servingSize,
            servingUnit: servingUnit,
            calories: calories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams,
            sugarGrams: sugarGrams,
            sodiumMg: sodiumMg,
            source: .cached
        )
    }

    /// Creates a MealFoodItem from this cached food.
    func toMealFoodItem(quantity: Double = 1.0) -> MealFoodItem {
        MealFoodItem(
            name: name,
            brand: brand,
            servingSizeGrams: servingSize,
            servingSizeLabel: "\(Int(servingSize))\(servingUnit)",
            quantity: quantity,
            caloriesPerServing: calories,
            proteinPerServing: proteinGrams,
            carbsPerServing: carbsGrams,
            fatPerServing: fatGrams,
            fiberPerServing: fiberGrams,
            sugarPerServing: sugarGrams,
            sodiumPerServing: sodiumMg
        )
    }
}
