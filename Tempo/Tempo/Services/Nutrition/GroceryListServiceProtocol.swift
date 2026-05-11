//
// GroceryListServiceProtocol.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - GroceryListServiceProtocol

@MainActor
protocol GroceryListServiceProtocol: Sendable {
    /// Generate (or regenerate) the grocery list for the given week. If a list
    /// for that week already exists, it's replaced.
    @discardableResult
    func generate(
        from mealPlan: WeeklyMealPlan,
        pantry: any PantryServiceProtocol,
        weekStartDate: Date
    ) throws -> GroceryList

    func fetchLatest() throws -> GroceryList?
    func fetchAll() throws -> [GroceryList]

    func toggleChecked(_ item: GroceryListItem) throws

    /// Export the list to Apple Reminders. Throws if the user hasn't granted
    /// access. Marks the list as exported on success.
    func exportToReminders(_ list: GroceryList) async throws

    func delete(_ list: GroceryList) throws
}

// MARK: - GroceryListServiceError

enum GroceryListServiceError: Error, LocalizedError, Sendable {
    case noMealsToShop
    case remindersAccessDenied
    case remindersExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noMealsToShop: "No meals found in the active plan."
        case .remindersAccessDenied: "Tempo can't add items to Reminders without permission. Enable Reminders access in Settings."
        case let .remindersExportFailed(detail): "Reminders export failed: \(detail)"
        }
    }
}
