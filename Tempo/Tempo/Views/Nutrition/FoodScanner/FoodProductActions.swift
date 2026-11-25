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
        try record(
            product, grams: grams, type: type, origin: origin,
            modelContext: modelContext, notifications: notifications, now: now
        ).logged
    }

    /// Same, returning the whole result, which is what Undo needs to take exactly this log back.
    static func record(
        _ product: FoodProduct,
        grams: Double,
        type: MealType,
        origin: MealOrigin? = nil,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil,
        now: Date = Date()
    ) throws -> EatenMealRecorder.Result {
        try EatenMealRecorder.record(
            [product.foodItem(grams: grams).mealFoodInput],
            type: type,
            eatenAt: now,
            source: product.barcode == nil ? .manual : .barcode,
            origin: origin,
            modelContext: modelContext,
            notifications: notifications,
            now: now
        )
    }

    // MARK: - Pantry

    @discardableResult
    static func addToPantry(_ product: FoodProduct, modelContext: ModelContext) throws -> PantryItem {
        try addToPantryWithUndo(product, modelContext: modelContext).item
    }

    /// Adds it and also says how to take it back: a new row goes back to archived, a row it was
    /// merged into goes back to its old quantity (`KitchenUndo.restorePantry`).
    static func addToPantryWithUndo(
        _ product: FoodProduct,
        modelContext: ModelContext
    ) throws -> (item: PantryItem, undo: [KitchenUndo.PantryItemState]) {
        let service = LocalPantryService(modelContext: modelContext)
        let before = KitchenUndo.pantryStates(of: try service.fetchAll())
        let staged = StagedPantryItem(product: product)
        let item = try service.mergeOrCreate(
            rawName: staged.name,
            quantity: staged.quantity,
            unit: staged.unit,
            storageLocation: staged.location,
            purchaseDate: Date(),
            purchaseSource: .manual,
            sourceReceiptLineItemID: nil,
            brand: staged.brand
        )
        let after = try service.fetchAll()
        return (item, KitchenUndo.pantryUndoStates(before: before, after: after))
    }

    // MARK: - Grocery list

    static func addToList(_ product: FoodProduct, modelContext: ModelContext) throws -> ListOutcome {
        try addToListReturningItem(product, modelContext: modelContext).outcome
    }

    /// Same, also giving the id of the row it added, so Undo can take that row off again.
    static func addToListReturningItem(
        _ product: FoodProduct,
        modelContext: ModelContext
    ) throws -> (outcome: ListOutcome, itemID: UUID?) {
        let service = LocalGroceryListService(modelContext: modelContext)
        guard let list = try service.fetchLatest() else {
            return (.noList, nil)
        }
        let canonical = FoodCanonicalizer.canonicalize(product.name)
        if list.activeItems.contains(where: { $0.canonicalFoodName == canonical }) {
            return (.alreadyOnList, nil)
        }
        let staged = StagedPantryItem(product: product)
        do {
            let item = try service.addItem(name: product.name, quantity: staged.quantity, unit: staged.unit, category: "pantry")
            return (.added, item.id)
        } catch GroceryListServiceError.noMealsToShop {
            return (.noList, nil)
        }
    }

    /// Takes a row this screen added off the list again. False when the row is already gone.
    @discardableResult
    static func removeFromList(itemID: UUID, modelContext: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<GroceryListItem>(predicate: #Predicate { $0.id == itemID })
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else {
            return false
        }
        return (try? LocalGroceryListService(modelContext: modelContext).deleteItem(item)) != nil
    }

    // MARK: - Inventory

    static func inventory(for product: FoodProduct, modelContext: ModelContext) -> Inventory {
        let canonical = FoodCanonicalizer.canonicalize(product.name)
        var atHome: String?
        if let item = try? LocalPantryService(modelContext: modelContext).find(canonicalName: canonical), item.quantity > 0 {
            atHome = "\(PantryQuantityFormatter.text(quantity: item.quantity, unit: item.unit)) at home"
        }
        let list = try? LocalGroceryListService(modelContext: modelContext).fetchLatest()
        let onList = (list?.activeItems ?? []).contains { $0.canonicalFoodName == canonical }
        return Inventory(atHome: atHome, onList: onList)
    }
}
