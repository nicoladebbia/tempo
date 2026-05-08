//
// PlannedMeal.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - PlannedFood

struct PlannedFood: Codable {
    let name: String
    let quantityGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

// MARK: - PlannedMeal

@Model
final class PlannedMeal {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Scheduling

    /// Calendar date normalized to midnight.
    var dayDate: Date

    /// Meal slot number (1-6).
    var mealNumber: Int

    /// Display name (e.g. "Breakfast", "Lunch").
    var mealName: String

    /// Scheduled time as HH:mm string (e.g. "07:30").
    var scheduledTime: String

    // MARK: - Foods

    var foodsJSON: Data?

    // MARK: - Macro Totals

    var totalCalories: Double

    var totalProtein: Double

    var totalCarbs: Double

    var totalFat: Double

    // MARK: - Status

    var statusRaw: String

    var linkedMealLogID: UUID?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var mealPlan: WeeklyMealPlan?

    // MARK: - Computed Properties

    @Transient
    var foods: [PlannedFood] {
        get {
            guard let data = foodsJSON else {
                return []
            }
            return (try? JSONDecoder().decode([PlannedFood].self, from: data)) ?? []
        }
        set {
            foodsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var status: MealStatus {
        get { MealStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    @Transient
    var formattedTime: String {
        scheduledTime
    }

    @Transient
    var foodCount: Int {
        foods.count
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        dayDate: Date,
        mealNumber: Int = 1,
        mealName: String = "Meal",
        scheduledTime: String = "12:00",
        foods: [PlannedFood] = [],
        totalCalories: Double = 0,
        totalProtein: Double = 0,
        totalCarbs: Double = 0,
        totalFat: Double = 0,
        status: MealStatus = .planned,
        linkedMealLogID: UUID? = nil,
        mealPlan: WeeklyMealPlan? = nil
    ) {
        self.id = id
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        self.mealNumber = mealNumber
        self.mealName = mealName
        self.scheduledTime = scheduledTime
        foodsJSON = foods.isEmpty ? nil : try? JSONEncoder().encode(foods)
        self.totalCalories = totalCalories
        self.totalProtein = totalProtein
        self.totalCarbs = totalCarbs
        self.totalFat = totalFat
        statusRaw = status.rawValue
        self.linkedMealLogID = linkedMealLogID
        self.mealPlan = mealPlan
    }

    /// Recalculate totals from current foods.
    func recalculateTotals() {
        let currentFoods = foods
        totalCalories = currentFoods.reduce(0) { $0 + $1.calories }
        totalProtein = currentFoods.reduce(0) { $0 + $1.proteinG }
        totalCarbs = currentFoods.reduce(0) { $0 + $1.carbsG }
        totalFat = currentFoods.reduce(0) { $0 + $1.fatG }
    }
}
