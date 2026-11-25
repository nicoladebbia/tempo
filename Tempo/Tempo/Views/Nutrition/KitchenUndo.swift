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
//     same row back (same id), takes the food off the list's "dismissed"
//     shelf it was put on, and puts its Reminders entry back;
//   - ticking a grocery item off (or back on) is one flag, so Undo sets it back;
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

    /// Where an Undo toast goes by default: the one Fuel toast host. A page with a bar pinned to
    /// the bottom (Store Mode, Scan a receipt, Took it) shows its own instead, above that bar,
    /// because the host's toast rests on the bar and a tap on its Undo reaches the bar.
    typealias Present = (ToastData) -> Void

    static let hostPresent: Present = { FuelLogToast.post($0) }

    /// "<message>" with an Undo button. `undo` runs on tap and dismisses the toast.
    static func undoToast(_ message: String, undo: @escaping @MainActor () -> Void) -> ToastData {
        ToastData(message: message, style: .info, actionTitle: "Undo") {
            undo()
        }
    }

    /// Shows "<message>" with an Undo button. `undo` runs on tap and dismisses the toast.
    static func offer(_ message: String, present: Present = hostPresent, undo: @escaping @MainActor () -> Void) {
        present(undoToast(message, undo: undo))
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

        init(id: UUID, quantity: Double, isArchived: Bool) {
            self.id = id
            self.quantity = quantity
            self.isArchived = isArchived
        }
    }

    static func pantryStates(of items: [PantryItem]) -> [PantryItemState] {
        items.map(PantryItemState.init)
    }

    /// What to put back after items were added to the pantry: a row that was already there goes
    /// back to its old quantity, a row that was created goes back to archived (gone from the shelf).
    /// `before` is the shelf as it was, `after` the shelf now. Rows that did not change are left out.
    static func pantryUndoStates(before: [PantryItemState], after: [PantryItem]) -> [PantryItemState] {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return after.compactMap { item in
            guard let was = old[item.id] else {
                return PantryItemState(id: item.id, quantity: item.quantity, isArchived: true)
            }
            return was.quantity == item.quantity && !item.isArchived ? nil : was
        }
    }

    /// Removes the prices a manual pantry add wrote (one per purchase), so taking the add back
    /// also takes its price out of the history.
    @discardableResult
    static func removePriceEntries(
        ofItems ids: Set<UUID>,
        since start: Date,
        in context: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<PantryPriceEntry>(predicate: #Predicate { $0.purchaseDate >= start })
        let doomed = ((try? context.fetch(descriptor)) ?? []).filter {
            $0.sourcePantryItemID.map(ids.contains) ?? false
        }
        for entry in doomed {
            context.delete(entry)
        }
        if !doomed.isEmpty {
            try? context.save()
        }
        return doomed.count
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

// MARK: - Grocery ticks

extension KitchenUndo {
    /// Ticks a supplement taken (or not taken) for today and offers the flip back. The flip is the
    /// same toggle the check button uses, so the shelf's stock and the macros come back exactly.
    /// Returns whether it is taken now.
    @discardableResult
    static func toggleSupplementTaken(
        supplementID: UUID?, name: String, in context: ModelContext, present: Present = hostPresent
    ) -> Bool {
        // The day is pinned: an Undo tapped after midnight still changes the day that was ticked.
        let day = Date()
        let nowTaken = SupplementIntakeStore.toggle(supplementID: supplementID, name: name, day: day, in: context)
        HapticManager.lightImpact()
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
        offer(nowTaken ? "\(name) taken." : "\(name) marked not taken.", present: present) {
            // If something else changed it in the meantime, leave it as it is now.
            if SupplementIntakeStore.toggle(supplementID: supplementID, name: name, day: day, in: context) == nowTaken {
                SupplementIntakeStore.toggle(supplementID: supplementID, name: name, day: day, in: context)
            }
            NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
        }
        return nowTaken
    }

    static func groceryItem(id: UUID, in context: ModelContext) -> GroceryListItem? {
        var descriptor = FetchDescriptor<GroceryListItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Sets a grocery row's ticked flag to `checked`. False when the row is gone; true also when it
    /// already is (a second tap on Undo changes nothing).
    @discardableResult
    static func setGroceryChecked(id: UUID, to checked: Bool, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<GroceryListItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? context.fetch(descriptor).first else {
            return false
        }
        if item.isChecked != checked {
            item.isChecked = checked
            try? context.save()
        }
        return true
    }
}

// MARK: - Saved meals, food-check history, staples

/// A saved meal, taken before it is deleted, so Undo can put the same one back.
struct MealPresetSnapshot {
    let id: UUID
    let name: String
    let foodItems: [MealFoodItemInput]
    let totals: MealMacros
    let mealType: MealType
    let useCount: Int
    let lastUsedAt: Date?
    let createdAt: Date
    let isPinned: Bool

    init(_ preset: MealPreset) {
        id = preset.id
        name = preset.name
        foodItems = preset.foodItems
        totals = MealMacros(
            calories: preset.totalCalories, protein: preset.totalProtein,
            carbs: preset.totalCarbs, fat: preset.totalFat
        )
        mealType = preset.mealType
        useCount = preset.useCount
        lastUsedAt = preset.lastUsedAt
        createdAt = preset.createdAt
        isPinned = preset.isPinned
    }

    /// Puts the saved meal back (same id, favourite flag and use count). True when it is there afterwards.
    @discardableResult
    func restore(in context: ModelContext) -> Bool {
        let id = id
        var descriptor = FetchDescriptor<MealPreset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil {
            return true
        }
        context.insert(MealPreset(
            id: id, name: name, foodItems: foodItems,
            totalCalories: totals.calories, totalProtein: totals.protein,
            totalCarbs: totals.carbs, totalFat: totals.fat,
            mealType: mealType, useCount: useCount, lastUsedAt: lastUsedAt,
            createdAt: createdAt, isPinned: isPinned
        ))
        return (try? context.save()) != nil
    }
}

/// A Food check history or favourites row, taken before it is removed.
struct ScannedFoodSnapshot {
    let productID: String
    let name: String
    let productJSON: Data
    let lastViewedAt: Date
    let viewCount: Int
    let isFavorite: Bool
    let isUserAdded: Bool
    let photoData: Data?
    let lastLoggedGrams: Double?

    init(_ row: ScannedFood) {
        productID = row.productID
        name = row.name
        productJSON = row.productJSON
        lastViewedAt = row.lastViewedAt
        viewCount = row.viewCount
        isFavorite = row.isFavorite
        isUserAdded = row.isUserAdded
        photoData = row.photoData
        lastLoggedGrams = row.lastLoggedGrams
    }

    /// Puts the row back with its star, photo, view count and remembered portion.
    /// True when it is there afterwards.
    @discardableResult
    func restore(in context: ModelContext) -> Bool {
        let key = productID
        var descriptor = FetchDescriptor<ScannedFood>(predicate: #Predicate { $0.productID == key })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil {
            return true
        }
        guard let product = try? JSONDecoder().decode(FoodProduct.self, from: productJSON) else {
            return false
        }
        let row = ScannedFood(product: product, isUserAdded: isUserAdded, photoData: photoData, now: lastViewedAt)
        row.viewCount = viewCount
        row.isFavorite = isFavorite
        row.lastLoggedGrams = lastLoggedGrams
        context.insert(row)
        return (try? context.save()) != nil
    }
}

/// A pantry staple (salt, oil), taken before it is removed.
struct PantryStapleSnapshot {
    let id: UUID
    let canonicalName: String
    let displayName: String
    let status: StapleStatus
    let createdAt: Date

    init(_ staple: PantryStaple) {
        id = staple.id
        canonicalName = staple.canonicalName
        displayName = staple.displayName
        status = staple.status
        createdAt = staple.createdAt
    }

    @discardableResult
    func restore(in context: ModelContext) -> Bool {
        let id = id
        var descriptor = FetchDescriptor<PantryStaple>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil {
            return true
        }
        let staple = PantryStaple(id: id, canonicalName: canonicalName, displayName: displayName, status: status)
        staple.createdAt = createdAt
        context.insert(staple)
        return (try? context.save()) != nil
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
    func deleteGroceryItemWithUndo(_ item: GroceryListItem, present: KitchenUndo.Present = KitchenUndo.hostPresent) {
        let snapshot = GroceryItemSnapshot(item)
        let name = item.displayName
        deleteGroceryItem(item)
        guard groceryState.lastError == nil else {
            return
        }
        KitchenUndo.offer("\(name) removed.", present: present) { [self] in
            guard let context = groceryState.latest?.modelContext ?? pantryModelContext else {
                return
            }
            let back = snapshot.restore(in: context)
            redrawGroceryList()
            if snapshot.hadReminder, let back, let service = groceryService {
                Task { await service.restoreReminder(for: back) }
            }
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

    /// Adds a row the user typed, with a few seconds to take it off again.
    func addGroceryItemWithUndo(
        name: String, quantity: Double, unit: PantryUnit, present: KitchenUndo.Present = KitchenUndo.hostPresent
    ) {
        guard let item = addGroceryItem(name: name, quantity: quantity, unit: unit) else {
            return
        }
        let id = item.id
        KitchenUndo.offer("\(item.displayName) is on your list.", present: present) { [self] in
            guard let context = groceryState.latest?.modelContext ?? pantryModelContext,
                  let row = KitchenUndo.groceryItem(id: id, in: context)
            else {
                return
            }
            deleteGroceryItem(row)
        }
    }

    /// Adds pantry items the user typed (or scanned), with Undo for the whole lot. Undo puts a
    /// merged row back to its old quantity, archives a created one and takes the prices out of history.
    func addPantryItemsWithUndo(_ staged: [StagedPantryItem]) {
        guard !staged.isEmpty else {
            return
        }
        let before = KitchenUndo.pantryStates(of: (try? pantryService?.fetchAll()) ?? pantryState.items)
        let started = Date()
        for item in staged {
            addPantryItem(
                rawName: item.name,
                quantity: item.quantity,
                unit: item.unit,
                storageLocation: item.location,
                totalPaidUSD: item.totalPaidUSD,
                brand: item.brand
            )
        }
        let changes = KitchenUndo.pantryUndoStates(before: before, after: pantryState.items)
        guard let first = changes.first else {
            return
        }
        let name = pantryState.items.first { $0.id == first.id }?.displayName ?? staged[0].name
        let message = staged.count == 1 ? "\(name) is in your pantry." : "\(FuelWords.count(staged.count, "item")) added to your pantry."
        let ids = Set(changes.map(\.id))
        KitchenUndo.offer(message) { [self] in
            if let context = pantryModelContext {
                KitchenUndo.removePriceEntries(ofItems: ids, since: started, in: context)
            }
            restorePantry(changes)
        }
    }

    /// Removes a staple with a few seconds to put it back.
    func deleteStapleWithUndo(_ staple: PantryStaple) {
        let snapshot = PantryStapleSnapshot(staple)
        deleteStaple(staple)
        guard stapleState.loadError == nil else {
            return
        }
        KitchenUndo.offer("\(snapshot.displayName) removed.") { [self] in
            if let context = pantryModelContext, snapshot.restore(in: context) {
                reloadStaples()
            }
        }
    }

    /// Ticks a supplement taken (or not taken) and shows the toast that flips it back. The flip is
    /// the same toggle the check button uses, so stock and macros come back exactly.
    func toggleSupplementTakenWithUndo(supplementID: UUID?, name: String, modelContext: ModelContext) {
        KitchenUndo.toggleSupplementTaken(supplementID: supplementID, name: name, in: modelContext)
    }

    /// Ticks a row off (or back on) and returns the toast that takes it back. The caller shows
    /// it: the list posts it to the Fuel toast host, Store Mode (a full-screen cover, so the host
    /// is hidden under it) keeps its own. nil when the change could not be saved.
    func toggleGroceryItemWithUndo(_ item: GroceryListItem) -> ToastData? {
        let id = item.id
        let wasChecked = item.isChecked
        let name = item.displayName
        toggleGroceryItem(item)
        guard groceryState.lastError == nil else {
            return nil
        }
        let message = wasChecked ? "\(name) is back on your list." : "\(name) checked off."
        return ToastData(message: message, style: .info, actionTitle: "Undo") { [self] in
            // The row is a live model object, so the page follows the flag by itself.
            if let context = groceryState.latest?.modelContext ?? pantryModelContext {
                KitchenUndo.setGroceryChecked(id: id, to: wasChecked, in: context)
            }
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
    /// True when the row had an Apple Reminders entry, which the delete removes.
    let hadReminder: Bool

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
        hadReminder = item.reminderIdentifier != nil
        // The same rule `LocalGroceryListService.deleteItem` follows.
        if !item.isManual, !item.isBought, let list = item.list {
            addedToDismissed = !(list.dismissedFoods ?? []).contains(item.canonicalFoodName.lowercased())
        } else {
            addedToDismissed = false
        }
    }

    /// Puts the row back on its list. Nil when its list is gone. An item that
    /// is already back is returned as it is (a double tap on Undo does nothing twice).
    /// The Reminders entry is put back by the caller when `hadReminder` (see `GroceryListServiceProtocol.restoreReminder`).
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
