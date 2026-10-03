//
// FoodProductActions.swift
// Tempo
//
// What the Food check product page can DO with a product: log it, put it in
// the pantry, put it on the grocery list, and say what you already have.
// Kept out of the view so each action is testable against an in-memory store.
//

import Foundation
import SwiftData

@MainActor
enum FoodProductActions {
    enum ListOutcome: Equatable {
        case added
        case alreadyOnList
        /// No grocery list exists yet — nothing to add to.
        case noList
    }

    struct Inventory: Equatable {
        /// "2 pcs at home" — nil when none is in the pantry.
        var atHome: String?
        var onList: Bool

        /// "2 pcs at home · on your list", "Not at home · not on your list".
        var line: String {
            let home = atHome ?? "Not at home"
            return onList ? "\(home) · on your list" : "\(home) · not on your list"
        }
    }

    // MARK: - Log

    /// Logs `grams` of `product` as `type`, through the same write path as the
    /// meal logger. Returns what was logged.
    @discardableResult
    static func log(
        _ product: FoodProduct,
        grams: Double,
        type: MealType,
        origin: MealOrigin? = nil,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil,
        now: Date = Date()
    ) throws -> MealMacros {
        let result = try EatenMealRecorder.record(
            [product.foodItem(grams: grams).mealFoodInput],
            type: type,
            eatenAt: now,
            source: product.barcode == nil ? .manual : .barcode,
            origin: origin,
            modelContext: modelContext,
            notifications: notifications,
            now: now
        )
        return result.logged
    }

    // MARK: - Pantry

    @discardableResult
    static func addToPantry(_ product: FoodProduct, modelContext: ModelContext) throws -> PantryItem {
        let staged = StagedPantryItem(product: product)
        return try LocalPantryService(modelContext: modelContext).mergeOrCreate(
            rawName: staged.name,
            quantity: staged.quantity,
            unit: staged.unit,
            storageLocation: staged.location,
            purchaseDate: Date(),
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil,
            brand: staged.brand
        )
    }

    // MARK: - Grocery list

    static func addToList(_ product: FoodProduct, modelContext: ModelContext) throws -> ListOutcome {
        let service = LocalGroceryListService(modelContext: modelContext)
        guard let list = try service.fetchLatest() else {
            return .noList
        }
        let canonical = FoodCanonicalizer.canonicalize(product.name)
        if list.activeItems.contains(where: { $0.canonicalFoodName == canonical }) {
            return .alreadyOnList
        }
        let staged = StagedPantryItem(product: product)
        do {
            _ = try service.addItem(name: product.name, quantity: staged.quantity, unit: staged.unit, category: "pantry")
        } catch GroceryListServiceError.noMealsToShop {
            return .noList
        }
        return .added
    }

    // MARK: - Inventory

    static func inventory(for product: FoodProduct, modelContext: ModelContext) -> Inventory {
        let canonical = FoodCanonicalizer.canonicalize(product.name)
        var atHome: String?
        if let item = try? LocalPantryService(modelContext: modelContext).find(canonicalName: canonical), item.quantity > 0 {
            atHome = "\(format(item.quantity)) \(item.unit.displayName) at home"
        }
        let list = try? LocalGroceryListService(modelContext: modelContext).fetchLatest()
        let onList = (list?.activeItems ?? []).contains { $0.canonicalFoodName == canonical }
        return Inventory(atHome: atHome, onList: onList)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
