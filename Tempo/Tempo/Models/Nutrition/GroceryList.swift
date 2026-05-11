//
// GroceryList.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - GroceryList

@Model
final class GroceryList {
    @Attribute(.unique)
    var id: UUID

    /// Week-start date (Monday at 00:00, normalized).
    var weekStartDate: Date

    /// Originating meal plan, if any. Nullified on delete.
    var sourceMealPlanID: UUID?

    var generatedAt: Date

    /// `true` when the user has exported this list to Reminders.
    var exportedToReminders: Bool

    var exportedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \GroceryListItem.list)
    var items: [GroceryListItem]?

    @Transient
    var orderedItems: [GroceryListItem] {
        (items ?? []).sorted {
            ($0.category, $0.canonicalFoodName) < ($1.category, $1.canonicalFoodName)
        }
    }

    @Transient
    var itemCount: Int {
        items?.count ?? 0
    }

    @Transient
    var checkedCount: Int {
        (items ?? []).filter(\.isChecked).count
    }

    @Transient
    var isComplete: Bool {
        guard let items, !items.isEmpty else {
            return false
        }
        return items.allSatisfy(\.isChecked)
    }

    init(
        id: UUID = UUID(),
        weekStartDate: Date,
        sourceMealPlanID: UUID? = nil
    ) {
        self.id = id
        self.weekStartDate = Calendar.current.startOfDay(for: weekStartDate)
        self.sourceMealPlanID = sourceMealPlanID
        self.generatedAt = Date()
        self.exportedToReminders = false
        self.exportedAt = nil
    }
}

// MARK: - GroceryListItem

@Model
final class GroceryListItem {
    @Attribute(.unique)
    var id: UUID

    @Relationship(deleteRule: .nullify)
    var list: GroceryList?

    /// FoodCanonicalizer.canonicalize output.
    var canonicalFoodName: String

    /// Display label.
    var displayName: String

    /// Aggregated quantity needed (in `unit`).
    var quantity: Double

    var unitRaw: String

    /// Grocery category for sort/group ("produce", "protein", "dairy", "grains", "pantry").
    var category: String

    /// User-checked in the in-app list.
    var isChecked: Bool

    /// Optional notes (brand preference, substitutions).
    var notes: String?

    var createdAt: Date

    @Transient
    var unit: PantryUnit {
        get { PantryUnit(rawValue: unitRaw) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        list: GroceryList? = nil,
        canonicalFoodName: String,
        displayName: String,
        quantity: Double,
        unit: PantryUnit,
        category: String = "pantry",
        isChecked: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.list = list
        self.canonicalFoodName = canonicalFoodName
        self.displayName = displayName
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.category = category
        self.isChecked = isChecked
        self.notes = notes
        self.createdAt = Date()
    }
}
