//
// MealFoodItem.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - MealFoodItem

@Model
final class MealFoodItem {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Food Info

    var name: String

    var brand: String?

    var barcode: String?

    // MARK: - Serving

    var servingSizeGrams: Double

    var servingSizeLabel: String

    var quantity: Double

    // MARK: - Macros Per Serving

    var caloriesPerServing: Double

    var proteinPerServing: Double

    var carbsPerServing: Double

    var fatPerServing: Double

    var fiberPerServing: Double?

    var sugarPerServing: Double?

    /// Sodium in milligrams per serving.
    var sodiumPerServing: Double?

    // MARK: - Data Provenance

    var dataSourceRaw: String

    var usdaFdcId: Int?

    var offProductCode: String?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var mealLog: MealLog?

    // MARK: - Computed Properties

    @Transient
    var totalCalories: Double {
        caloriesPerServing * quantity
    }

    @Transient
    var totalProtein: Double {
        proteinPerServing * quantity
    }

    @Transient
    var totalCarbs: Double {
        carbsPerServing * quantity
    }

    @Transient
    var totalFat: Double {
        fatPerServing * quantity
    }

    @Transient
    var totalFiber: Double? {
        fiberPerServing.map { $0 * quantity }
    }

    @Transient
    var totalSugar: Double? {
        sugarPerServing.map { $0 * quantity }
    }

    @Transient
    var totalSodium: Double? {
        sodiumPerServing.map { $0 * quantity }
    }

    @Transient
    var dataSource: FoodDataSource {
        get { FoodDataSource(rawValue: dataSourceRaw) ?? .manual }
        set { dataSourceRaw = newValue.rawValue }
    }

    @Transient
    var formattedServing: String {
        if quantity == 1.0 {
            return servingSizeLabel
        }
        return "\(String(format: "%.1g", quantity)) x \(servingSizeLabel)"
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        servingSizeGrams: Double,
        servingSizeLabel: String,
        quantity: Double = 1.0,
        caloriesPerServing: Double,
        proteinPerServing: Double,
        carbsPerServing: Double,
        fatPerServing: Double,
        fiberPerServing: Double? = nil,
        sugarPerServing: Double? = nil,
        sodiumPerServing: Double? = nil,
        dataSource: FoodDataSource = .manual,
        usdaFdcId: Int? = nil,
        offProductCode: String? = nil,
        mealLog: MealLog? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.servingSizeGrams = servingSizeGrams
        self.servingSizeLabel = servingSizeLabel
        // Negative quantities silently propagate as negative calories downstream.
        self.quantity = max(0, quantity)
        self.caloriesPerServing = caloriesPerServing
        self.proteinPerServing = proteinPerServing
        self.carbsPerServing = carbsPerServing
        self.fatPerServing = fatPerServing
        self.fiberPerServing = fiberPerServing
        self.sugarPerServing = sugarPerServing
        self.sodiumPerServing = sodiumPerServing
        dataSourceRaw = dataSource.rawValue
        self.usdaFdcId = usdaFdcId
        self.offProductCode = offProductCode
        self.mealLog = mealLog
    }

    /// Convenience init from service-layer input DTO.
    init(from input: MealFoodItemInput) {
        id = UUID()
        name = input.name
        brand = input.brand
        barcode = input.barcode
        servingSizeGrams = input.servingSize
        servingSizeLabel = input.servingUnit
        quantity = input.servings
        caloriesPerServing = input.calories
        proteinPerServing = input.proteinGrams
        carbsPerServing = input.carbsGrams
        fatPerServing = input.fatGrams
        fiberPerServing = nil
        sugarPerServing = nil
        sodiumPerServing = nil
        dataSourceRaw = input.source.rawValue
        usdaFdcId = nil
        offProductCode = input.source == .openFoodFacts ? input.barcode : nil
    }
}

// MARK: - DTO

extension MealFoodItem {
    struct DTO: Codable {
        let id: UUID
        let name: String
        let brand: String?
        let barcode: String?
        let serving_size_grams: Double
        let serving_size_label: String
        let quantity: Double
        let calories_per_serving: Double
        let protein_per_serving: Double
        let carbs_per_serving: Double
        let fat_per_serving: Double
        let fiber_per_serving: Double?
        let sugar_per_serving: Double?
        let sodium_per_serving: Double?
        let data_source: String
        let usda_fdc_id: Int?
        let off_product_code: String?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            name: name,
            brand: brand,
            barcode: barcode,
            serving_size_grams: servingSizeGrams,
            serving_size_label: servingSizeLabel,
            quantity: quantity,
            calories_per_serving: caloriesPerServing,
            protein_per_serving: proteinPerServing,
            carbs_per_serving: carbsPerServing,
            fat_per_serving: fatPerServing,
            fiber_per_serving: fiberPerServing,
            sugar_per_serving: sugarPerServing,
            sodium_per_serving: sodiumPerServing,
            data_source: dataSourceRaw,
            usda_fdc_id: usdaFdcId,
            off_product_code: offProductCode
        )
    }
}
