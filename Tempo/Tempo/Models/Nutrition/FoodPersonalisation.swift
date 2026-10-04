//
// FoodPersonalisation.swift
// Tempo
//
// Optional taste answers from Fuel setup that the meal planner reads
// (DietaryProfile ← FuelSetupDraft → MealPlanPrompts). None is required;
// nil always means "no preference, use sensible defaults".
//

import Foundation

// MARK: - SpiceLevel

enum SpiceLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case mild
    case medium
    case hot

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .mild: "Mild"
        case .medium: "Medium"
        case .hot: "Hot"
        }
    }

    var promptLine: String {
        switch self {
        case .mild: "SPICE: mild — little or no chili heat; flavor from herbs, citrus and aromatics instead."
        case .medium: "SPICE: medium — some warmth is welcome, nothing fiery."
        case .hot: "SPICE: hot — likes real heat; use chili, hot sauce and spiced marinades freely."
        }
    }
}

// MARK: - BreakfastStyle

enum BreakfastStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case sweet
    case savoury
    case quick

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .sweet: "Sweet"
        case .savoury: "Savoury"
        case .quick: "Quick"
        }
    }

    var promptLine: String {
        switch self {
        case .sweet: "BREAKFAST STYLE: sweet (oats, yogurt and fruit, pancakes, smoothies) — no savoury breakfasts."
        case .savoury: "BREAKFAST STYLE: savoury (eggs, toast and toppings, wraps, leftovers) — no sweet breakfasts."
        case .quick: "BREAKFAST STYLE: quick — five minutes or less, or grab-and-go; no cooked-from-scratch breakfasts."
        }
    }
}

// MARK: - AppetiteSize

enum AppetiteSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case light
    case normal
    case big

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .light: "Light eater"
        case .normal: "Normal"
        case .big: "Big eater"
        }
    }

    /// nil for `.normal`: nothing to tell the planner.
    var promptLine: String? {
        switch self {
        case .light:
            "PORTIONS: light eater — smaller, denser meals, calorie-dense foods over bulk; daily macro targets do not change."
        case .normal:
            nil
        case .big:
            "PORTIONS: big eater — larger, high-volume meals that keep them full (extra veg, rice, potatoes); daily macro targets do not change."
        }
    }
}

// MARK: - Snacks

enum SnackHabit {
    static let range = 0 ... 2

    static func promptLine(_ perDay: Int) -> String {
        switch perDay {
        case ...0: "SNACKS: none — no standalone snacks; fold the calories into the main meals."
        case 1: "SNACKS: one a day (counted inside the meal total)."
        default: "SNACKS: two a day (counted inside the meal total)."
        }
    }

    static func label(_ perDay: Int) -> String {
        switch perDay {
        case ...0: "no snacks"
        case 1: "1 snack"
        default: "\(perDay) snacks"
        }
    }
}
