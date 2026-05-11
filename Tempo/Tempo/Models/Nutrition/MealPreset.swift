//
// MealPreset.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

@Model
final class MealPreset {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Preset Info

    var name: String

    var foodItemsJSON: Data?

    // MARK: - Macro Totals

    var totalCalories: Double

    var totalProtein: Double

    var totalCarbs: Double

    var totalFat: Double

    // MARK: - Metadata

    var mealTypeRaw: String

    var useCount: Int

    var lastUsedAt: Date?

    var createdAt: Date

    // MARK: - Computed Properties

    @Transient
    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    @Transient
    var foodItems: [MealFoodItemInput] {
        get {
            guard let data = foodItemsJSON else {
                return []
            }
            return (try? JSONDecoder().decode([MealFoodItemInput].self, from: data)) ?? []
        }
        set {
            foodItemsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        foodItems: [MealFoodItemInput] = [],
        totalCalories: Double = 0,
        totalProtein: Double = 0,
        totalCarbs: Double = 0,
        totalFat: Double = 0,
        mealType: MealType = .snack,
        useCount: Int = 0,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        foodItemsJSON = foodItems.isEmpty ? nil : try? JSONEncoder().encode(foodItems)
        self.totalCalories = totalCalories
        self.totalProtein = totalProtein
        self.totalCarbs = totalCarbs
        self.totalFat = totalFat
        mealTypeRaw = mealType.rawValue
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
    }

    /// Record a use of this preset.
    func recordUse() {
        useCount += 1
        lastUsedAt = Date()
    }
}
