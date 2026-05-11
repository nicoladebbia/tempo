//
// NutritionTarget.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - NutritionTarget

@Model
final class NutritionTarget {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Targets

    var calorieTarget: Int

    var proteinTargetGrams: Int

    var carbsTargetGrams: Int

    var fatTargetGrams: Int

    var mealsPerDay: Int

    // MARK: - Lifecycle

    var effectiveFrom: Date

    var isActive: Bool

    // MARK: - Computed Properties

    @Transient
    var proteinCaloriePercentage: Double {
        let totalCals = Double(calorieTarget)
        guard totalCals > 0 else {
            return 0
        }
        return (Double(proteinTargetGrams) * 4.0) / totalCals * 100.0
    }

    @Transient
    var carbsCaloriePercentage: Double {
        let totalCals = Double(calorieTarget)
        guard totalCals > 0 else {
            return 0
        }
        return (Double(carbsTargetGrams) * 4.0) / totalCals * 100.0
    }

    @Transient
    var fatCaloriePercentage: Double {
        let totalCals = Double(calorieTarget)
        guard totalCals > 0 else {
            return 0
        }
        return (Double(fatTargetGrams) * 9.0) / totalCals * 100.0
    }

    @Transient
    var macroCaloriesTotal: Int {
        (proteinTargetGrams * 4) + (carbsTargetGrams * 4) + (fatTargetGrams * 9)
    }

    @Transient
    var macrosMatchCalories: Bool {
        abs(macroCaloriesTotal - calorieTarget) <= 50
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        calorieTarget: Int,
        proteinTargetGrams: Int,
        carbsTargetGrams: Int,
        fatTargetGrams: Int,
        mealsPerDay: Int = 4,
        effectiveFrom: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.calorieTarget = calorieTarget
        self.proteinTargetGrams = proteinTargetGrams
        self.carbsTargetGrams = carbsTargetGrams
        self.fatTargetGrams = fatTargetGrams
        self.mealsPerDay = mealsPerDay
        self.effectiveFrom = Calendar.current.startOfDay(for: effectiveFrom)
        self.isActive = isActive
    }
}

// MARK: - DTO

extension NutritionTarget {
    struct DTO: Codable {
        let id: UUID
        let calorie_target: Int
        let protein_target_grams: Int
        let carbs_target_grams: Int
        let fat_target_grams: Int
        let meals_per_day: Int
        let effective_from: Date
        let is_active: Bool
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            calorie_target: calorieTarget,
            protein_target_grams: proteinTargetGrams,
            carbs_target_grams: carbsTargetGrams,
            fat_target_grams: fatTargetGrams,
            meals_per_day: mealsPerDay,
            effective_from: effectiveFrom,
            is_active: isActive
        )
    }
}
