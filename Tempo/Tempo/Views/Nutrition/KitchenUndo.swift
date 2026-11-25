//
// KitchenUndo.swift
// Tempo
//
// A few seconds to take back what you just removed in the Kitchen: a pantry
// item, a grocery item, a supplement, a receipt. The toast is the app's own
// Undo toast (`ToastData` with an action, shown by the Fuel toast host), not a
// second one. What Undo puts back is exact:
//   - pantry items and supplements are soft-deleted (`isArchived`), so Undo
//     flips the flag (and the quantity, for "Used up") back;
//   - a grocery item is really deleted, so a snapshot of every field puts the
//     same row back (same id) and takes the food off the list's "dismissed"
//     shelf it was put on;
//   - a receipt is not deleted until the Undo window has passed (`KitchenPendingReceipts`),
//     so its photo and lines are never touched while you can still change your mind.
//

import Foundation
import Observation
import SwiftData
import UIKit

// MARK: - KitchenUndo

@MainActor
enum KitchenUndo {
    /// How long Undo stays on screen (the toast's own duration).
    static let window: TimeInterval = FuelLogToast.undoWindow

    /// Shows "<message>" with an Undo button. `undo` runs on tap and dismisses the toast.
    static func offer(_ message: String, undo: @escaping @MainActor () -> Void) {
        FuelLogToast.post(ToastData(message: message, style: .info, actionTitle: "Undo") {
            undo()
        })
    }

    // MARK: Pantry

    /// What a pantry row looked like before it was removed or used up.
    struct PantryItemState: Equatable {
        let id: UUID
        let quantity: Double
        let isArchived: Bool

        init(_ item: PantryItem) {
            id = item.id
            quantity = item.quantity
            isArchived = item.isArchived
        }
    }

    static func pantryStates(of items: [PantryItem]) -> [PantryItemState] {
        items.map(PantryItemState.init)
    }

    /// Puts pantry rows back as they were. Returns how many were restored
    /// (a row the store no longer has is skipped).
    @discardableResult
    static func restorePantry(_ states: [PantryItemState], in context: ModelContext, now: Date = Date()) -> Int {
        var restored = 0
        for state in states {
            let id = state.id
            var descriptor = FetchDescriptor<PantryItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let item = try? context.fetch(descriptor).first else {
                continue
            }
            item.isArchived = state.isArchived
            item.quantity = state.quantity
            item.updatedAt = now
            restored += 1
        }
        try? context.save()
        return restored
    }

    // MARK: Supplements

    /// Brings a deleted supplement back to the shelf (and its reminders).
    @discardableResult
    static func restoreSupplement(id: UUID, in context: ModelContext, now: Date = Date()) -> Bool {
        var descriptor = FetchDescriptor<Supplement>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let supplement = try? context.fetch(descriptor).first else {
            return false
        }
        supplement.isArchived = false
        supplement.updatedAt = now
        try? context.save()
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
        return true
    }
}

// MARK: - Undo through the view model

/// The Kitchen's remove actions, each followed by an Undo toast. They sit on the
/// view model so the page reloads (and the grocery list follows the pantry) the
/// same way after a removal and after taking it back.
extension NutritionTabViewModel {
    /// Takes a pantry row off the shelf (the same soft delete as before).
    func archivePantryItemWithUndo(_ item: PantryItem) {
        let states = KitchenUndo.pantryStates(of: [item])
        let name = item.displayName
        archivePantryItem(item)
        KitchenUndo.offer("\(name) removed.") { [self] in
            restorePantry(states)
        }
    }

    /// "Used up": the row stays, at zero.
    func markPantryItemUsedUp(_ item: PantryItem) {
        let states = KitchenUndo.pantryStates(of: [item])
        let name = item.displayName
        updatePantryItem(item, quantity: 0)
        KitchenUndo.offer("\(name) used up.") { [self] in
            restorePantry(states)
        }
    }

    /// Empties the pantry, with Undo for the whole lot.
    func emptyPantryWithUndo() {
        let states = KitchenUndo.pantryStates(of: pantryState.items)
        let removed = emptyPantry()
        guard removed > 0 else {
            return
        }
        KitchenUndo.offer("\(FuelWords.count(removed, "item")) removed.") { [self] in
            restorePantry(states)
        }
    }

    /// Puts pantry rows back as they were and lets the list follow.
    func restorePantry(_ states: [KitchenUndo.PantryItemState]) {
        guard let context = pantryModelContext else {
            return
        }
        KitchenUndo.restorePantry(states, in: context)
        reloadPantry()
        reapplyPantryToGrocery()
    }

    /// Takes a row off the grocery list with a few seconds to put it back.
    func deleteGroceryItemWithUndo(_ item: GroceryListItem) {
        let snapshot = GroceryItemSnapshot(item)
        let name = item.displayName
        deleteGroceryItem(item)
        guard groceryState.lastError == nil else {
            return
        }
        KitchenUndo.offer("\(name) removed.") { [self] in
            guard let context = groceryState.latest?.modelContext ?? pantryModelContext else {
                return
            }
            snapshot.restore(in: context)
            redrawGroceryList()
        }
    }

    /// The page shows `groceryState.latest`, and putting the same list object back is not
    /// seen as a change (a removal redraws because SwiftData reports it; a row put back
    /// does not). Clearing it first makes the page read the list again, in one pass.
    private func redrawGroceryList() {
        guard let latest = (try? groceryService?.fetchLatest()) ?? groceryState.latest else {
            return
        }
        groceryState.latest = nil
        groceryState.latest = latest
    }

    /// After a row is ticked off: a few seconds to un-tick it.
    func offerUndoCheck(of item: GroceryListItem) {
        let id = item.id
        KitchenUndo.offer("\(item.displayName) checked off.") { [self] in
            guard let current = groceryState.latest?.items?.first(where: { $0.id == id }), current.isChecked else {
                return
            }
            toggleGroceryItem(current)
        }
    }
}

// MARK: - GroceryItemSnapshot

/// Every field of a grocery row, taken before it is deleted, so Undo can put
/// the same row back.
struct GroceryItemSnapshot {
    let id: UUID
    let listID: UUID?
    let canonicalFoodName: String
    let displayName: String
    let quantity: Double
    let unitRaw: String
    let category: String
    let isChecked: Bool
    let isManual: Bool
    let isBought: Bool
    let boughtAt: Date?
    let estimatedPriceUSD: Double?
    let priceSourceRaw: String?
    let notes: String?
    let createdAt: Date
    /// True when deleting this row added its food to the list's "dismissed"
    /// shelf (so a pantry sync does not bring it back). Undo takes it off again.
    let addedToDismissed: Bool

    /// Take it before the delete: the delete itself edits the list.
    init(_ item: GroceryListItem) {
        id = item.id
        listID = item.list?.id
        canonicalFoodName = item.canonicalFoodName
        displayName = item.displayName
        quantity = item.quantity
        unitRaw = item.unitRaw
        category = item.category
        isChecked = item.isChecked
        isManual = item.isManual
        isBought = item.isBought
        boughtAt = item.boughtAt
        estimatedPriceUSD = item.estimatedPriceUSD
        priceSourceRaw = item.priceSourceRaw
        notes = item.notes
        createdAt = item.createdAt
        // The same rule `LocalGroceryListService.deleteItem` follows.
        if !item.isManual, !item.isBought, let list = item.list {
            addedToDismissed = !(list.dismissedFoods ?? []).contains(item.canonicalFoodName.lowercased())
        } else {
            addedToDismissed = false
        }
    }

    /// Puts the row back on its list. Nil when its list is gone. An item that
    /// is already back is returned as it is (a double tap on Undo does nothing twice).
    /// The Reminders entry the delete removed is not recreated: the next export does.
    @discardableResult
    @MainActor
    func restore(in context: ModelContext) -> GroceryListItem? {
        let itemID = id
        var existing = FetchDescriptor<GroceryListItem>(predicate: #Predicate { $0.id == itemID })
        existing.fetchLimit = 1
        if let back = try? context.fetch(existing).first {
            return back
        }
        guard let listID else {
            return nil
        }
        var listQuery = FetchDescriptor<GroceryList>(predicate: #Predicate { $0.id == listID })
        listQuery.fetchLimit = 1
        guard let list = try? context.fetch(listQuery).first else {
            return nil
        }
        let item = GroceryListItem(
            id: id, list: list, canonicalFoodName: canonicalFoodName, displayName: displayName,
            quantity: quantity, unit: PantryUnit(rawValue: unitRaw) ?? .grams, category: category,
            isChecked: isChecked, isManual: isManual, isBought: isBought, boughtAt: boughtAt,
            estimatedPriceUSD: estimatedPriceUSD, priceSource: priceSourceRaw.flatMap(GroceryPriceSource.init(rawValue:)),
            notes: notes
        )
        item.unitRaw = unitRaw
        item.createdAt = createdAt
        context.insert(item)
        if addedToDismissed {
            let food = canonicalFoodName.lowercased()
            list.dismissedFoods = (list.dismissedFoods ?? []).filter { $0 != food }
        }
        try? context.save()
        return item
    }
}

// MARK: - KitchenPendingReceipts

/// Receipts the user deleted that are waiting out their Undo window. They are
/// hidden at once and really deleted when the window has passed, unless Undo
/// brings them back first, so a receipt's photo and lines are never touched
/// while there is still a way back. The window is a timer, not a screen:
/// leaving the page does not cut it short. When the app goes to the background
/// the waiting deletes are done at once (nothing can be undone from there).
@MainActor
@Observable
final class KitchenPendingReceipts {
    static let shared = KitchenPendingReceipts()

    /// Ids hidden from the lists while their Undo is open.
    private(set) var hidden: Set<UUID> = []

    private struct Waiting {
        let task: Task<Void, Never>
        let delete: @MainActor () -> Void
        let finished: @MainActor () -> Void
    }

    @ObservationIgnored
    private var waiting: [UUID: Waiting] = [:]
    /// Lives as long as the app (one shared instance), so the observer is never removed.
    init(center: NotificationCenter = .default) {
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitAll() }
        }
    }

    func isHidden(_ id: UUID) -> Bool {
        hidden.contains(id)
    }

    /// Hides the receipt with this id and runs `delete` after `window` unless
    /// `undo` is called first; `finished` runs after the delete (reload the lists).
    func schedule(
        id: UUID,
        window: TimeInterval = KitchenUndo.window,
        delete: @escaping @MainActor () -> Void,
        finished: @escaping @MainActor () -> Void
    ) {
        waiting[id]?.task.cancel()
        hidden.insert(id)
        let task = Task { @MainActor [weak self] in
            // A little past the toast, so a tap on Undo at the last second still lands.
            try? await Task.sleep(for: .seconds(window + 0.5))
            guard !Task.isCancelled else {
                return
            }
            self?.commit(id)
        }
        waiting[id] = Waiting(task: task, delete: delete, finished: finished)
    }

    /// Brings a hidden receipt back. False when it was already deleted.
    @discardableResult
    func undo(_ id: UUID) -> Bool {
        waiting[id]?.task.cancel()
        waiting[id] = nil
        return hidden.remove(id) != nil
    }

    /// Deletes every receipt still waiting, now.
    func commitAll() {
        for id in Array(waiting.keys) {
            commit(id)
        }
    }

    private func commit(_ id: UUID) {
        guard let entry = waiting.removeValue(forKey: id) else {
            return
        }
        entry.task.cancel()
        entry.delete()
        hidden.remove(id)
        entry.finished()
    }
}
