//
// DietaryProfile.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

@Model
final class DietaryProfile {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Dietary Preferences

    var isLactoseFree: Bool

    var noCoffee: Bool

    var isGlutenFree: Bool = false

    var isVegetarian: Bool = false

    var isVegan: Bool = false

    var isHalal: Bool = false

    var isNutFree: Bool = false

    var isShellFishAllergy: Bool = false

    var cookingSkillRaw: String = "beginner"

    var allergiesJSON: Data?

    var dislikedFoodsJSON: Data?

    // MARK: - Goals & Body Composition

    var primaryGoalRaw: String

    var bodyFatPercent: Double?

    var currentWeightKg: Double

    var heightCm: Double

    var age: Int

    var biologicalSexRaw: String

    // MARK: - Training

    var trainingFrequency: Int

    var skillLevelRaw: String

    // MARK: - Lifecycle

    var isActive: Bool

    var createdAt: Date

    var updatedAt: Date

    // MARK: - Computed Properties

    @Transient
    var allergies: [String] {
        get {
            guard let data = allergiesJSON else {
                return []
            }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            allergiesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var dislikedFoods: [String] {
        get {
            guard let data = dislikedFoodsJSON else {
                return []
            }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            dislikedFoodsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var primaryGoal: DietaryGoal {
        get { DietaryGoal(rawValue: primaryGoalRaw) ?? .maintain }
        set { primaryGoalRaw = newValue.rawValue }
    }

    @Transient
    var biologicalSex: BiologicalSex {
        get { BiologicalSex(rawValue: biologicalSexRaw) ?? .male }
        set { biologicalSexRaw = newValue.rawValue }
    }

    @Transient
    var skillLevel: SkillLevel {
        get { SkillLevel(rawValue: skillLevelRaw) ?? .intermediate }
        set { skillLevelRaw = newValue.rawValue }
    }

    @Transient
    var cookingSkill: CookingSkill {
        get { CookingSkill(rawValue: cookingSkillRaw) ?? .beginner }
        set { cookingSkillRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        isLactoseFree: Bool = false,
        noCoffee: Bool = false,
        isGlutenFree: Bool = false,
        isVegetarian: Bool = false,
        isVegan: Bool = false,
        isHalal: Bool = false,
        isNutFree: Bool = false,
        isShellFishAllergy: Bool = false,
        cookingSkill: CookingSkill = .beginner,
        allergies: [String] = [],
        dislikedFoods: [String] = [],
        primaryGoal: DietaryGoal = .maintain,
        bodyFatPercent: Double? = nil,
        currentWeightKg: Double = 75,
        heightCm: Double = 175,
        age: Int = 22,
        biologicalSex: BiologicalSex = .male,
        trainingFrequency: Int = 4,
        skillLevel: SkillLevel = .intermediate,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isLactoseFree = isLactoseFree
        self.noCoffee = noCoffee
        self.isGlutenFree = isGlutenFree
        self.isVegetarian = isVegetarian
        self.isVegan = isVegan
        self.isHalal = isHalal
        self.isNutFree = isNutFree
        self.isShellFishAllergy = isShellFishAllergy
        cookingSkillRaw = cookingSkill.rawValue
        allergiesJSON = allergies.isEmpty ? nil : try? JSONEncoder().encode(allergies)
        dislikedFoodsJSON = dislikedFoods.isEmpty ? nil : try? JSONEncoder().encode(dislikedFoods)
        primaryGoalRaw = primaryGoal.rawValue
        self.bodyFatPercent = bodyFatPercent
        self.currentWeightKg = currentWeightKg
        self.heightCm = heightCm
        self.age = age
        biologicalSexRaw = biologicalSex.rawValue
        self.trainingFrequency = trainingFrequency
        skillLevelRaw = skillLevel.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
