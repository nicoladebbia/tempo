//
// MealPlanIntake.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation

// MARK: - MealPlanIntake

struct MealPlanIntake: Sendable, Equatable {
    var cookableDaysThisWeek: Int
    var leftoverTolerance: LeftoverTolerance
    var eatingWindow: EatingWindow
    var groceryIntent: GroceryIntent?
    var recoveryAdjusted: Bool
    var temporaryExclusions: [String]

    static let `default` = MealPlanIntake(
        cookableDaysThisWeek: 4,
        leftoverTolerance: .twoToThreeDayBatches,
        eatingWindow: .default,
        groceryIntent: nil,
        recoveryAdjusted: false,
        temporaryExclusions: []
    )
}

// MARK: - LeftoverTolerance

enum LeftoverTolerance: String, Sendable, CaseIterable, Identifiable {
    case freshDaily
    case twoToThreeDayBatches
    case fullWeekPrep

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .freshDaily: "Fresh every day"
        case .twoToThreeDayBatches: "2-3 day batches"
        case .fullWeekPrep: "Full-week prep"
        }
    }

    var promptDescriptor: String {
        switch self {
        case .freshDaily: "User wants fresh meals every day. No repeating the same recipe back-to-back."
        case .twoToThreeDayBatches: "User accepts the same meal across 2-3 consecutive days. Batch cooking is welcome."
        case .fullWeekPrep: "User prefers Sunday-style meal prep. Many meals can repeat across the week."
        }
    }
}

// MARK: - EatingWindow

struct EatingWindow: Sendable, Equatable {
    var firstMealHour: Int
    var lastMealHour: Int

    static let `default` = EatingWindow(firstMealHour: 8, lastMealHour: 20)

    var isValid: Bool {
        firstMealHour >= 0 && firstMealHour < 24
            && lastMealHour > firstMealHour && lastMealHour < 24
    }

    var formattedForPrompt: String {
        let firstFormatted = String(format: "%02d:00", firstMealHour)
        let lastFormatted = String(format: "%02d:00", lastMealHour)
        return "First meal anchored at \(firstFormatted). Last meal anchored at \(lastFormatted)."
    }
}

// MARK: - GroceryIntent

struct GroceryIntent: Sendable, Equatable {
    var willShopThisWeek: Bool
    var budgetCapUSD: Int?
    var preferredStores: [String]

    var formattedForPrompt: String {
        var parts: [String] = []
        parts.append(willShopThisWeek
            ? "User is doing a grocery run this week — fresh purchases allowed."
            : "User is NOT shopping this week — meals must work from current pantry + minimal additions.")
        if let cap = budgetCapUSD {
            parts.append("Budget cap for the week: $\(cap).")
        }
        if !preferredStores.isEmpty {
            parts.append("Preferred stores: \(preferredStores.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }
}
