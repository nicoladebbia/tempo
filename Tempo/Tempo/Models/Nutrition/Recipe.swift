//
// Recipe.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - RecipeMealType

enum RecipeMealType: String, Codable, CaseIterable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case preWorkout = "pre_workout"
    case postWorkout = "post_workout"
    case any
}

// MARK: - RecipeDifficulty

enum RecipeDifficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case medium
    case hard
}

// MARK: - RecipeSkill

enum RecipeSkill: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case advanced
}

// MARK: - RecipeSource

enum RecipeSource: String, Codable, CaseIterable, Sendable {
    case userCreated = "user_created"
    case aiGenerated = "ai_generated"
    case imported
    case seeded
}

// MARK: - Recipe

@Model
final class Recipe {
    @Attribute(.unique)
    var id: UUID

    var name: String

    /// Lowercased, hyphen-separated. Stable for deeplinks.
    var slug: String

    var recipeDescription: String?

    var cuisine: String?

    var mealTypeRaw: String

    var servings: Int

    var prepMinutes: Int?

    var cookMinutes: Int?

    var difficultyRaw: String

    var skillRaw: String

    /// Flat array of equipment names (e.g. ["oven","stovetop"]). Stored as JSON.
    var equipmentJSON: Data?

    /// Flat array of dietary tags (e.g. ["high_protein","gluten_free"]).
    var dietaryTagsJSON: Data?

    /// Denormalized macro totals — computed at save time from ingredients.
    var totalCalories: Double

    var totalProteinGrams: Double

    var totalCarbsGrams: Double

    var totalFatGrams: Double

    var totalFiberGrams: Double?

    var sourceRaw: String

    var sourceURL: String?

    var photoPath: String?

    var timesCooked: Int

    var lastCookedAt: Date?

    var userRating: Int?

    var isFavorite: Bool

    var isArchived: Bool

    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]?

    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]?

    // MARK: - Computed

    @Transient
    var mealType: RecipeMealType {
        get { RecipeMealType(rawValue: mealTypeRaw) ?? .any }
        set { mealTypeRaw = newValue.rawValue }
    }

    @Transient
    var difficulty: RecipeDifficulty {
        get { RecipeDifficulty(rawValue: difficultyRaw) ?? .easy }
        set { difficultyRaw = newValue.rawValue }
    }

    @Transient
    var skill: RecipeSkill {
        get { RecipeSkill(rawValue: skillRaw) ?? .beginner }
        set { skillRaw = newValue.rawValue }
    }

    @Transient
    var source: RecipeSource {
        get { RecipeSource(rawValue: sourceRaw) ?? .userCreated }
        set { sourceRaw = newValue.rawValue }
    }

    @Transient
    var equipment: [String] {
        get {
            guard let data = equipmentJSON else {
                return []
            }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            equipmentJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var dietaryTags: [String] {
        get {
            guard let data = dietaryTagsJSON else {
                return []
            }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            dietaryTagsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var orderedIngredients: [RecipeIngredient] {
        (ingredients ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    @Transient
    var orderedSteps: [RecipeStep] {
        (steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    @Transient
    var totalMinutes: Int {
        (prepMinutes ?? 0) + (cookMinutes ?? 0)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        slug: String? = nil,
        recipeDescription: String? = nil,
        cuisine: String? = nil,
        mealType: RecipeMealType = .any,
        servings: Int = 1,
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        difficulty: RecipeDifficulty = .easy,
        skill: RecipeSkill = .beginner,
        equipment: [String] = [],
        dietaryTags: [String] = [],
        totalCalories: Double = 0,
        totalProteinGrams: Double = 0,
        totalCarbsGrams: Double = 0,
        totalFatGrams: Double = 0,
        totalFiberGrams: Double? = nil,
        source: RecipeSource = .userCreated,
        sourceURL: String? = nil,
        photoPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug ?? Self.makeSlug(from: name)
        self.recipeDescription = recipeDescription
        self.cuisine = cuisine
        self.mealTypeRaw = mealType.rawValue
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.difficultyRaw = difficulty.rawValue
        self.skillRaw = skill.rawValue
        self.totalCalories = totalCalories
        self.totalProteinGrams = totalProteinGrams
        self.totalCarbsGrams = totalCarbsGrams
        self.totalFatGrams = totalFatGrams
        self.totalFiberGrams = totalFiberGrams
        self.sourceRaw = source.rawValue
        self.sourceURL = sourceURL
        self.photoPath = photoPath
        self.timesCooked = 0
        self.lastCookedAt = nil
        self.userRating = nil
        self.isFavorite = false
        self.isArchived = false
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
        // Set JSON fields last so they pick up the closures above.
        self.equipmentJSON = try? JSONEncoder().encode(equipment)
        self.dietaryTagsJSON = try? JSONEncoder().encode(dietaryTags)
    }

    // MARK: - Helpers

    static func makeSlug(from name: String) -> String {
        let lower = name.lowercased()
        let allowed = CharacterSet.alphanumerics
        let parts = lower.unicodeScalars.split { !allowed.contains($0) }
        return parts.map(String.init).joined(separator: "-")
    }

    /// Recompute denormalized macro totals from current ingredients.
    func recomputeMacroTotals() {
        let items = ingredients ?? []
        totalCalories = items.reduce(0) { $0 + ($1.calories ?? 0) }
        totalProteinGrams = items.reduce(0) { $0 + ($1.proteinGrams ?? 0) }
        totalCarbsGrams = items.reduce(0) { $0 + ($1.carbsGrams ?? 0) }
        totalFatGrams = items.reduce(0) { $0 + ($1.fatGrams ?? 0) }
        let fiberSum = items.reduce(0) { $0 + ($1.fiberGrams ?? 0) }
        totalFiberGrams = fiberSum > 0 ? fiberSum : nil
        updatedAt = Date()
    }
}

// MARK: - RecipeIngredient

@Model
final class RecipeIngredient {
    @Attribute(.unique)
    var id: UUID

    @Relationship(deleteRule: .nullify)
    var recipe: Recipe?

    var orderIndex: Int

    /// Canonical food name (output of FoodCanonicalizer).
    var canonicalFoodName: String

    /// User-visible label ("200g chicken breast, cubed").
    var displayName: String

    /// Grams used in the recipe — drives macro calc.
    var quantityGrams: Double

    /// Optional UI-only quantity string ("1 cup", "2 tbsp").
    var displayQuantity: String?

    var calories: Double?
    var proteinGrams: Double?
    var carbsGrams: Double?
    var fatGrams: Double?
    var fiberGrams: Double?

    var isOptional: Bool

    /// JSON array of substitute canonical names ("turkey breast", "tofu").
    var substitutesJSON: Data?

    @Transient
    var substitutes: [String] {
        get {
            guard let data = substitutesJSON else {
                return []
            }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            substitutesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        id: UUID = UUID(),
        recipe: Recipe? = nil,
        orderIndex: Int,
        canonicalFoodName: String,
        displayName: String,
        quantityGrams: Double,
        displayQuantity: String? = nil,
        calories: Double? = nil,
        proteinGrams: Double? = nil,
        carbsGrams: Double? = nil,
        fatGrams: Double? = nil,
        fiberGrams: Double? = nil,
        isOptional: Bool = false,
        substitutes: [String] = []
    ) {
        self.id = id
        self.recipe = recipe
        self.orderIndex = orderIndex
        self.canonicalFoodName = canonicalFoodName
        self.displayName = displayName
        self.quantityGrams = quantityGrams
        self.displayQuantity = displayQuantity
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.isOptional = isOptional
        self.substitutesJSON = try? JSONEncoder().encode(substitutes)
    }
}

// MARK: - RecipeStep

@Model
final class RecipeStep {
    @Attribute(.unique)
    var id: UUID

    @Relationship(deleteRule: .nullify)
    var recipe: Recipe?

    var orderIndex: Int

    var instruction: String

    var durationMinutes: Int?

    var temperature: String?

    var equipment: String?

    init(
        id: UUID = UUID(),
        recipe: Recipe? = nil,
        orderIndex: Int,
        instruction: String,
        durationMinutes: Int? = nil,
        temperature: String? = nil,
        equipment: String? = nil
    ) {
        self.id = id
        self.recipe = recipe
        self.orderIndex = orderIndex
        self.instruction = instruction
        self.durationMinutes = durationMinutes
        self.temperature = temperature
        self.equipment = equipment
    }
}
