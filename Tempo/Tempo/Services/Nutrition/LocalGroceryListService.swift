//
// LocalGroceryListService.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import EventKit
import Foundation
import os
import SwiftData

// MARK: - LocalGroceryListService

@MainActor
@Observable
final class LocalGroceryListService: GroceryListServiceProtocol {
    private let modelContext: ModelContext
    private let logger = Logger.nutrition
    private let eventStore = EKEventStore()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Generate

    /// Clock for "from today on" and tests.
    var now: () -> Date = { Date() }

    /// `weekStartDate` MUST be the source plan's Monday (its `startDate`),
    /// not "today" — that's what makes regenerating mid-week REPLACE that
    /// week's list instead of spawning a second one (BUILD item 1a).
    ///
    /// The existing list is UPDATED IN PLACE (same `GroceryList.id`, same
    /// item ids for foods that are still needed): `GroceryShare` is keyed by
    /// list id and the shopper's page by item id, so deleting and recreating
    /// the list orphaned the live share link and lost shopper ticks. Ticks,
    /// bought history and manual items survive; lines the plan no longer
    /// needs (eaten/skipped meals, pantry now covers it) are removed along
    /// with their Apple Reminders entry. Lists more than `retentionWeeks`
    /// old are pruned on every generate.
    @discardableResult
    func generate(
        from mealPlan: WeeklyMealPlan,
        pantry: any PantryServiceProtocol,
        weekStartDate: Date
    ) throws -> GroceryList {
        let pantryItems = try pantry.fetchAll()
        let aggregated = GroceryListGenerator.generate(from: .init(
            mealPlan: mealPlan,
            pantry: pantryItems,
            weekStartDate: weekStartDate,
            onOrAfter: now()
        ))

        let weekStart = Calendar.current.startOfDay(for: weekStartDate)
        let existingDescriptor = FetchDescriptor<GroceryList>(
            predicate: #Predicate<GroceryList> { list in
                list.weekStartDate == weekStart
            }
        )
        var existingLists = try modelContext.fetch(existingDescriptor)
        // Keep the list that has a live share (else the oldest) as THE list.
        existingLists.sort { lhs, rhs in
            let l = hasShare(lhs), r = hasShare(rhs)
            if l != r { return l }
            return lhs.generatedAt < rhs.generatedAt
        }

        let hasManual = existingLists.contains { ($0.items ?? []).contains { $0.isManual && !$0.isBought } }
        // Nothing to shop for at all (no plan-derived items AND no manual
        // items to carry forward) — same "empty plan" error as before.
        guard !aggregated.isEmpty || hasManual else {
            throw GroceryListServiceError.noMealsToShop
        }

        let list: GroceryList
        if let primary = existingLists.first {
            list = primary
            // Fold any duplicate list for the same week into the primary.
            for extra in existingLists.dropFirst() {
                for item in extra.items ?? [] {
                    item.list = primary
                    primary.items = (primary.items ?? []) + [item]
                }
                extra.items = []
                modelContext.delete(extra)
            }
        } else {
            list = GroceryList(weekStartDate: weekStart, sourceMealPlanID: mealPlan.id)
            modelContext.insert(list)
            list.items = []
        }
        list.sourceMealPlanID = mealPlan.id
        list.generatedAt = now()
        list.dismissedFoods = nil
        pruneOldLists(referenceDate: weekStartDate, keeping: list.id)

        var items = list.items ?? []
        let planned = Set(aggregated.map(\.canonicalName))

        // Active (not yet bought) plan rows by food. Bought rows stay as the
        // trip's record; a food that's still short after buying gets a fresh row.
        var activeByFood: [String: GroceryListItem] = [:]
        for item in items where !item.isManual && !item.isBought {
            if activeByFood[item.canonicalFoodName] != nil {
                // Duplicate plan row for the same food — drop the extra.
                removeItem(item, from: &items)
            } else {
                activeByFood[item.canonicalFoodName] = item
            }
        }
        // A pantry "ran out" row the new plan now covers itself would show
        // twice — the plan row wins. User-typed manual items always stay.
        for item in items where item.isManual && !item.isBought && planned.contains(item.canonicalFoodName)
            && (item.isPantryRestock || (item.notes == nil && item.category == PantryGroceryBridge.category))
        {
            removeItem(item, from: &items)
        }

        for entry in aggregated {
            if let existing = activeByFood[entry.canonicalName] {
                apply(entry, to: existing)
                activeByFood[entry.canonicalName] = nil
            } else {
                let item = GroceryListItem(
                    list: list,
                    canonicalFoodName: entry.canonicalName,
                    displayName: entry.displayName,
                    quantity: entry.quantity,
                    unit: entry.unit,
                    category: entry.category
                )
                modelContext.insert(item)
                items.append(item)
            }
        }
        // Whatever is left was needed before but not any more.
        for (_, stale) in activeByFood {
            removeItem(stale, from: &items)
        }

        list.items = items
        try modelContext.save()
        logger
            .info(
                "Grocery list generated: \(items.count) items, week \(weekStart.ISO8601Format(), privacy: .public)"
            )
        return list
    }

    private func hasShare(_ list: GroceryList) -> Bool {
        let listID = list.id
        let descriptor = FetchDescriptor<GroceryShare>(predicate: #Predicate { $0.listID == listID })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Overwrites a plan row's amount/label from a freshly computed entry.
    /// Price estimates are per line, so they scale with the quantity (or are
    /// cleared for the next refresh when the unit changed).
    private func apply(_ entry: GroceryListGenerator.Aggregated, to item: GroceryListItem) {
        let oldQuantity = item.quantity
        let sameUnit = item.unitRaw == entry.unit.rawValue
        item.displayName = entry.displayName
        item.quantity = entry.quantity
        item.unit = entry.unit
        item.category = entry.category
        if abs(oldQuantity - entry.quantity) > 0.0001 || !sameUnit {
            if sameUnit, oldQuantity > 0, let price = item.estimatedPriceUSD {
                item.estimatedPriceUSD = price * entry.quantity / oldQuantity
            } else {
                item.estimatedPriceUSD = nil
                item.priceSourceRaw = nil
            }
        }
    }

    /// Deletes a row and its Apple Reminders entry (a deleted row used to
    /// leave an orphan reminder in "Tempo Groceries" forever).
    private func removeItem(_ item: GroceryListItem, from items: inout [GroceryListItem]) {
        removeReminder(for: item)
        items.removeAll { $0.id == item.id }
        modelContext.delete(item)
    }

    private func removeReminder(for item: GroceryListItem) {
        guard let identifier = item.reminderIdentifier else {
            return
        }
        if let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder {
            try? eventStore.remove(reminder, commit: true)
        }
        item.reminderIdentifier = nil
    }

    /// Deletes grocery lists whose week is more than `retentionWeeks` in the
    /// past relative to `referenceDate` — old shopping trips aren't useful
    /// to keep around forever. Runs on every `generate()` call.
    private func pruneOldLists(retentionWeeks: Int = 4, referenceDate: Date, keeping keepID: UUID? = nil) {
        guard let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -retentionWeeks, to: referenceDate) else {
            return
        }
        let cutoffDay = Calendar.current.startOfDay(for: cutoff)
        let descriptor = FetchDescriptor<GroceryList>(
            predicate: #Predicate<GroceryList> { $0.weekStartDate < cutoffDay }
        )
        guard let old = try? modelContext.fetch(descriptor) else {
            return
        }
        for list in old where list.id != keepID {
            for item in list.items ?? [] {
                removeReminder(for: item)
            }
            modelContext.delete(list)
        }
    }

    // MARK: - Fetch

    func fetchLatest() throws -> GroceryList? {
        var descriptor = FetchDescriptor<GroceryList>(
            sortBy: [SortDescriptor(\.weekStartDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchAll() throws -> [GroceryList] {
        let descriptor = FetchDescriptor<GroceryList>(
            sortBy: [SortDescriptor(\.weekStartDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Mutations

    func toggleChecked(_ item: GroceryListItem) throws {
        item.isChecked.toggle()
        try modelContext.save()
    }

    func addItem(
        name: String,
        quantity: Double,
        unit: PantryUnit,
        category: String = "pantry"
    ) throws -> GroceryListItem {
        // Attach to the latest list. Without an active list there's nowhere
        // to put the item — caller should generate a plan first.
        guard let list = try fetchLatest() else {
            throw GroceryListServiceError.noMealsToShop
        }
        let item = Self.makeManualItem(list: list, name: name, quantity: quantity, unit: unit, category: category)
        modelContext.insert(item)
        try modelContext.save()
        return item
    }

    func deleteItem(_ item: GroceryListItem) throws {
        removeReminder(for: item)
        // Remember a deleted plan row so a pantry sync doesn't bring it back.
        if !item.isManual, !item.isBought, let list = item.list {
            let food = item.canonicalFoodName.lowercased()
            if !(list.dismissedFoods ?? []).contains(food) {
                list.dismissedFoods = (list.dismissedFoods ?? []) + [food]
            }
        }
        modelContext.delete(item)
        try modelContext.save()
    }

    /// Builds a user-typed item: canonicalised name (so it matches pantry/plan
    /// rows and Done Shopping files it under the real food) and an aisle
    /// derived from the food unless the caller picked a specific one.
    static func makeManualItem(
        list: GroceryList,
        name: String,
        quantity: Double,
        unit: PantryUnit,
        category: String
    ) -> GroceryListItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = FoodCanonicalizer.canonicalize(trimmed)
        let key = canonical.isEmpty ? trimmed.lowercased() : canonical
        let display = FoodCanonicalizer.displayName(trimmed)
        let resolvedCategory = category == "pantry" ? GroceryListGenerator.category(for: key) : category
        return GroceryListItem(
            list: list,
            canonicalFoodName: key,
            displayName: trimmed.isEmpty ? "Item" : (display.isEmpty ? trimmed : display),
            quantity: unit.wholeUnitQuantity(max(0, quantity)),
            unit: unit,
            category: resolvedCategory,
            isManual: true
        )
    }

    /// Re-nets the active list against the CURRENT pantry (call after any
    /// pantry change). Pantry is never subtracted twice: instead of shrinking
    /// the already-netted list quantities again, each plan row's amount is
    /// recomputed from the source plan's gross need (still-planned meals from
    /// today) minus the pantry, with the same purchase-unit rounding the
    /// generator uses — so 500 g needed / 300 g on hand stays "200 g" no
    /// matter how often it syncs, and a pantry change that grows the need
    /// grows the row back.
    ///
    /// Touches only un-ticked, un-bought plan rows, and re-adds a food whose
    /// need came back. User-typed manual items are left alone; pantry-restock rows ("out of rice") are dropped once
    /// that food is back in stock. Removed rows lose their Reminders entry.
    /// Returns the number of rows removed.
    @discardableResult
    func reapplyPantry(_ pantry: any PantryServiceProtocol) throws -> Int {
        guard let list = try fetchLatest(), let items = list.items else {
            return 0
        }
        let pantryItems = (try? pantry.fetchAll()) ?? []

        var net: [String: GroceryListGenerator.Aggregated]?
        if let planID = list.sourceMealPlanID {
            var descriptor = FetchDescriptor<WeeklyMealPlan>(predicate: #Predicate { $0.id == planID })
            descriptor.fetchLimit = 1
            // An archived (replaced) plan's meals aren't the shopping need
            // any more — leave its rows as generated.
            if let plan = try modelContext.fetch(descriptor).first, plan.isActive {
                let entries = GroceryListGenerator.generate(from: .init(
                    mealPlan: plan, pantry: pantryItems, weekStartDate: list.weekStartDate, onOrAfter: now()
                ))
                net = Dictionary(entries.map { ($0.canonicalName, $0) }, uniquingKeysWith: { first, _ in first })
            }
        }

        let inStock = Set(pantryItems.filter { !$0.isArchived && $0.isInStock }.map { $0.canonicalName.lowercased() })
        var remaining = items
        var removed = 0
        for item in items where !item.isChecked && !item.isBought {
            if item.isManual {
                if item.isPantryRestock, inStock.contains(item.canonicalFoodName.lowercased()) {
                    removeItem(item, from: &remaining)
                    removed += 1
                }
                continue
            }
            // Without the source plan we can't tell the gross need — leave
            // the row as generated rather than guess (under-dedup is safe).
            guard let net else {
                continue
            }
            if let entry = net[item.canonicalFoodName] {
                apply(entry, to: item)
            } else {
                removeItem(item, from: &remaining)
                removed += 1
            }
        }
        // A pantry drop (used up, emptied, archived) can bring a need back
        // that an earlier sync removed — add those rows again, the same way
        // `generate` creates them. Anything still on the list (ticked, typed
        // by the user) already covers its food.
        if let net {
            // A 1-pack "ran out" row must not block the plan's bigger need:
            // as in `generate`, the plan row replaces an open restock row
            // (unless the user dismissed that food from the list).
            let dismissed = Set((list.dismissedFoods ?? []).map { $0.lowercased() })
            for item in remaining where item.isPantryRestock && !item.isChecked && !item.isBought {
                let key = item.canonicalFoodName.lowercased()
                if !dismissed.contains(key), net.keys.contains(where: { $0.lowercased() == key }) {
                    removeItem(item, from: &remaining)
                    removed += 1
                }
            }
            let onList = Set(remaining.filter { !$0.isBought }.map { $0.canonicalFoodName.lowercased() })
                .union((list.dismissedFoods ?? []).map { $0.lowercased() })
            for entry in net.values.sorted(by: { $0.canonicalName < $1.canonicalName })
                where !onList.contains(entry.canonicalName.lowercased())
            {
                let item = GroceryListItem(
                    list: list,
                    canonicalFoodName: entry.canonicalName,
                    displayName: entry.displayName,
                    quantity: entry.quantity,
                    unit: entry.unit,
                    category: entry.category
                )
                modelContext.insert(item)
                remaining.append(item)
            }
        }
        list.items = remaining
        try modelContext.save()
        return removed
    }

    func delete(_ list: GroceryList) throws {
        modelContext.delete(list)
        try modelContext.save()
    }

    // MARK: - Done shopping → bought

    func markBought(_ items: [GroceryListItem], boughtAt: Date) throws {
        for item in items {
            item.isBought = true
            item.boughtAt = boughtAt
            // A bought item is done shopping regardless of whether it was
            // ever explicitly ticked (e.g. added straight from the review
            // sheet's "add anything else you bought" path in a future lane).
            item.isChecked = true
        }
        try modelContext.save()
    }

    // MARK: - Reminders export

    /// "Oats — 1.5kg". Same quantity formatting as GroceryListView: whole
    /// numbers stay whole, fractions keep one decimal. `Int(quantity)` used to
    /// truncate 1.5 kg to "1kg" and 0.5 lb to "0lb".
    ///
    /// `embedsQuantity`: pass `item.displayNameEmbedsQuantity` so a user-typed
    /// "7 up soda" keeps its amount. nil falls back to the name-only pattern.
    static func reminderTitle(name: String, quantity: Double, unit: PantryUnit, embedsQuantity: Bool? = nil) -> String {
        // "3 medium carrots" already carries its amount — don't append
        // "— 3pcs" after it.
        if embedsQuantity ?? (name.range(of: #"^\d+(?:[.,]\d+)?\s+\S"#, options: .regularExpression) != nil) {
            return name
        }
        let formatted = quantity == quantity.rounded() ? "\(Int(quantity))" : String(format: "%.1f", quantity)
        return "\(name) — \(formatted)\(unit.displayName)"
    }

    /// Name of the dedicated Reminders list Tempo owns, found-or-created on
    /// export so repeat exports never spawn a second one. Keeping grocery
    /// reminders out of the user's default/inbox list is also what makes
    /// per-item identifier reuse meaningful — the same list every time.
    static let remindersListName = "Tempo Groceries"

    /// Finds (or creates) the "Tempo Groceries" EKCalendar. A dedicated list
    /// — not the user's default Reminders list — so Tempo's items don't mix
    /// into whatever else they track, and so export/update/remove always
    /// targets the SAME list.
    private func tempoGroceriesCalendar() throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == Self.remindersListName }) {
            return existing
        }
        guard let source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
            ?? eventStore.sources.first
        else {
            throw GroceryListServiceError.remindersExportFailed("No Reminders account available.")
        }
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = Self.remindersListName
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// Exports (or re-syncs) `list` to the "Tempo Groceries" Reminders list.
    /// Per BUILD item 1c, this must not duplicate on repeat export: each
    /// item's EKReminder identifier is stored on the item
    /// (`reminderIdentifier`) and reused — `GroceryReminderPlanner` decides
    /// create vs. update vs. remove per item, this method executes that plan
    /// against EventKit. Checked/bought items are marked completed; bought
    /// items that already had a reminder are removed (done shopping = off
    /// the Reminders list too).
    func exportToReminders(_ list: GroceryList) async throws {
        let granted: Bool = if #available(iOS 17.0, *) {
            await (try? eventStore.requestFullAccessToReminders()) ?? false
        } else {
            await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }
        }
        guard granted else {
            throw GroceryListServiceError.remindersAccessDenied
        }

        let calendar = try tempoGroceriesCalendar()
        let title = "Tempo Grocery — \(list.weekStartDate.formatted(date: .abbreviated, time: .omitted))"
        let items = list.orderedItems
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let actions = GroceryReminderPlanner.plan(items: items)

        for action in actions {
            switch action {
            case let .create(itemID):
                guard let item = itemsByID[itemID] else {
                    continue
                }
                let reminder = EKReminder(eventStore: eventStore)
                reminder.calendar = calendar
                reminder.title = Self.reminderTitle(name: item.displayName, quantity: item.quantity, unit: item.unit, embedsQuantity: item.displayNameEmbedsQuantity)
                reminder.notes = "\(title)\nCategory: \(item.category)"
                reminder.isCompleted = item.isChecked
                do {
                    try eventStore.save(reminder, commit: false)
                } catch {
                    throw GroceryListServiceError.remindersExportFailed(error.localizedDescription)
                }
                item.reminderIdentifier = reminder.calendarItemIdentifier

            case let .update(itemID, reminderIdentifier):
                guard let item = itemsByID[itemID] else {
                    continue
                }
                guard let reminder = eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder else {
                    // Identifier is stale (e.g. the user deleted it in
                    // Reminders directly) — recreate so export stays reliable.
                    let reminder = EKReminder(eventStore: eventStore)
                    reminder.calendar = calendar
                    reminder.title = Self.reminderTitle(name: item.displayName, quantity: item.quantity, unit: item.unit, embedsQuantity: item.displayNameEmbedsQuantity)
                    reminder.notes = "\(title)\nCategory: \(item.category)"
                    reminder.isCompleted = item.isChecked
                    try? eventStore.save(reminder, commit: false)
                    item.reminderIdentifier = reminder.calendarItemIdentifier
                    continue
                }
                reminder.title = Self.reminderTitle(name: item.displayName, quantity: item.quantity, unit: item.unit, embedsQuantity: item.displayNameEmbedsQuantity)
                reminder.isCompleted = item.isChecked
                try? eventStore.save(reminder, commit: false)

            case let .remove(itemID, reminderIdentifier):
                guard let item = itemsByID[itemID] else {
                    continue
                }
                if let reminder = eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder {
                    try? eventStore.remove(reminder, commit: false)
                }
                item.reminderIdentifier = nil
            }
        }

        do {
            try eventStore.commit()
        } catch {
            throw GroceryListServiceError.remindersExportFailed(error.localizedDescription)
        }

        list.exportedToReminders = true
        list.exportedAt = Date()
        try modelContext.save()
        logger.info("Grocery list exported to Reminders: \(items.count) items")
    }
}

// MARK: - MockGroceryListService

@MainActor
@Observable
final class MockGroceryListService: GroceryListServiceProtocol {
    private(set) var lists: [GroceryList] = []
    var simulatedRemindersError: Error?

    init() {}

    @discardableResult
    func generate(
        from mealPlan: WeeklyMealPlan,
        pantry: any PantryServiceProtocol,
        weekStartDate: Date
    ) throws -> GroceryList {
        let pantryItems = try pantry.fetchAll()
        let aggregated = GroceryListGenerator.generate(from: .init(
            mealPlan: mealPlan, pantry: pantryItems, weekStartDate: weekStartDate
        ))
        guard !aggregated.isEmpty else {
            throw GroceryListServiceError.noMealsToShop
        }
        let list = GroceryList(weekStartDate: weekStartDate, sourceMealPlanID: mealPlan.id)
        list.items = aggregated.map { entry in
            GroceryListItem(
                list: list,
                canonicalFoodName: entry.canonicalName,
                displayName: entry.displayName,
                quantity: entry.quantity,
                unit: entry.unit,
                category: entry.category
            )
        }
        lists.insert(list, at: 0)
        return list
    }

    func fetchLatest() throws -> GroceryList? {
        lists.first
    }

    func fetchAll() throws -> [GroceryList] {
        lists
    }

    func toggleChecked(_ item: GroceryListItem) throws {
        item.isChecked.toggle()
    }

    func addItem(
        name: String,
        quantity: Double,
        unit: PantryUnit,
        category: String = "pantry"
    ) throws -> GroceryListItem {
        guard let list = lists.first else {
            throw GroceryListServiceError.noMealsToShop
        }
        let item = LocalGroceryListService.makeManualItem(list: list, name: name, quantity: quantity, unit: unit, category: category)
        if list.items == nil {
            list.items = []
        }
        list.items?.append(item)
        return item
    }

    func deleteItem(_ item: GroceryListItem) throws {
        for list in lists {
            list.items?.removeAll { $0.id == item.id }
        }
    }

    @discardableResult
    func reapplyPantry(_ pantry: any PantryServiceProtocol) throws -> Int {
        // Mock pantry isn't wired; treat as a no-op so tests stay stable.
        0
    }

    func exportToReminders(_ list: GroceryList) async throws {
        if let err = simulatedRemindersError {
            throw err
        }
        list.exportedToReminders = true
        list.exportedAt = Date()
    }

    func delete(_ list: GroceryList) throws {
        lists.removeAll { $0.id == list.id }
    }

    func markBought(_ items: [GroceryListItem], boughtAt: Date) throws {
        for item in items {
            item.isBought = true
            item.boughtAt = boughtAt
            item.isChecked = true
        }
    }
}
