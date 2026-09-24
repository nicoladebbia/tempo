//
// NutritionNotifications.swift
// Tempo
//

import Foundation

extension Notification.Name {
    /// Posted after the DietaryProfile is saved from ANY screen (Nutrition,
    /// Plan, Dashboard Settings). ContentView observes it at app level — so it
    /// works even if the Nutrition tab was never opened — and regenerates the
    /// active meal plan when its inputs fingerprint no longer matches.
    static let tempoDietaryProfileChanged = Notification.Name("tempo.nutrition.dietaryProfileChanged")
}
