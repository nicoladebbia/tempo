//
// NutritionEnums.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation

// MARK: - MealType

enum MealType: String, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        case .snack: 3
        }
    }
}

// MARK: - MealSource

enum MealSource: String, Codable {
    case manual
    case photo
    case barcode
    case voice
    case imported
    case usdaSearch
    case recentMeal
    case naturalLanguage
    case preset

    var displayName: String {
        switch self {
        case .manual: "Manual Entry"
        case .photo: "Photo Analysis"
        case .barcode: "Barcode Scan"
        case .voice: "Voice Input"
        case .imported: "Imported"
        case .usdaSearch: "USDA Search"
        case .recentMeal: "Recent Meal"
        case .naturalLanguage: "Natural Language"
        case .preset: "Preset"
        }
    }
}

// MARK: - FoodDataSource

enum FoodDataSource: String, Codable {
    case usda
    case openFoodFacts = "open_food_facts"
    case claude
    case manual
    case cached

    var displayName: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "Open Food Facts"
        case .claude: "AI Estimated"
        case .manual: "Manual"
        case .cached: "Cached"
        }
    }
}

// MARK: - NutritionCoachingTrigger

enum NutritionCoachingTrigger: String, Codable {
    case mealLogged = "meal_logged"
    case dailyTargetMet = "daily_target_met"
    case dailyTargetMissed = "daily_target_missed"
    case proteinLow = "protein_low"
    case calorieOvershoot = "calorie_overshoot"
    case longGap = "long_gap"
    case weeklyReview = "weekly_review"
}

// MARK: - MealStatus

enum MealStatus: String, Codable, CaseIterable {
    case planned
    case eaten
    case skipped
    case modified

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - DayType

enum DayType: String, Codable, CaseIterable {
    case strength
    case cardio
    case soccer
    case double
    case rest

    var displayName: String {
        switch self {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .soccer: "Soccer"
        case .double: "Double Session"
        case .rest: "Rest"
        }
    }
}

// MARK: - DietaryGoal

enum DietaryGoal: String, Codable, CaseIterable {
    case leanGain
    case cut
    case maintain

    var displayName: String {
        switch self {
        case .leanGain: "Lean Gain"
        case .cut: "Cut"
        case .maintain: "Maintain"
        }
    }
}

// MARK: - SkillLevel

enum SkillLevel: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - CookingSkill

enum CookingSkill: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - BiologicalSex

enum BiologicalSex: String, Codable, CaseIterable {
    case male
    case female

    var displayName: String {
        rawValue.capitalized
    }
}
