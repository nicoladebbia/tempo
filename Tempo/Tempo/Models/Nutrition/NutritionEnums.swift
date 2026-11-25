//
// NutritionEnums.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
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
        switch self {
        case .breakfast: String(localized: "Breakfast")
        case .lunch: String(localized: "Lunch")
        case .dinner: String(localized: "Dinner")
        case .snack: String(localized: "Snack")
        }
    }

    /// Fixed English name for text that is stored (planned-meal names), compared
    /// or sent to the AI, so it never changes with the app language.
    var englishName: String {
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
        case .manual: String(localized: "Manual Entry")
        case .photo: String(localized: "Photo Analysis")
        case .barcode: String(localized: "Barcode Scan")
        case .voice: String(localized: "Voice Input")
        case .imported: String(localized: "Imported")
        case .usdaSearch: String(localized: "USDA Search")
        case .recentMeal: String(localized: "Recent Meal")
        case .naturalLanguage: String(localized: "Natural Language")
        case .preset: String(localized: "Preset")
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
        case .usda: String(localized: "USDA")
        case .openFoodFacts: String(localized: "Open Food Facts")
        case .claude: String(localized: "AI Estimated")
        case .manual: String(localized: "Manual")
        case .cached: String(localized: "Cached")
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
        switch self {
        case .planned: String(localized: "Planned")
        case .eaten: String(localized: "Eaten")
        case .skipped: String(localized: "Skipped")
        case .modified: String(localized: "Modified")
        }
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
        case .strength: String(localized: "Strength")
        case .cardio: String(localized: "Cardio")
        case .soccer: String(localized: "Soccer")
        case .double: String(localized: "Double Session")
        case .rest: String(localized: "Rest")
        }
    }

    /// Fixed English name for text sent to the AI (coach tool output, prompts),
    /// so it never changes with the app language. Use `displayName` on screen.
    var englishName: String {
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
        case .leanGain: String(localized: "Lean Gain")
        case .cut: String(localized: "Cut")
        case .maintain: String(localized: "Maintain")
        }
    }

    /// Fixed English name for text sent to the AI, whatever the app language.
    var englishName: String {
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
        switch self {
        case .beginner: String(localized: "Beginner")
        case .intermediate: String(localized: "Intermediate")
        case .advanced: String(localized: "Advanced")
        }
    }

    /// Fixed English name for text sent to the AI, whatever the app language.
    var englishName: String {
        rawValue.capitalized
    }
}

// MARK: - CookingSkill

enum CookingSkill: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        switch self {
        case .beginner: String(localized: "Beginner")
        case .intermediate: String(localized: "Intermediate")
        case .advanced: String(localized: "Advanced")
        }
    }

    /// Fixed English name for text sent to the AI, whatever the app language.
    var englishName: String {
        rawValue.capitalized
    }
}

// MARK: - BiologicalSex

enum BiologicalSex: String, Codable, CaseIterable {
    case male
    case female

    var displayName: String {
        switch self {
        case .male: String(localized: "Male")
        case .female: String(localized: "Female")
        }
    }
}
