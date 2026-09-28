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

    /// State carried across a regenerate for an item the aggregator WILL
    /// reproduce (matched by canonical name) — ticks and bought/reminder
    /// bookkeeping shouldn't reset just because the week's list was rebuilt.
    private struct PreservedItemState {
        let isChecked: Bool
        let isBought: Bool
        let boughtAt: Date?
        let reminderIdentifier: String?

        init(item: GroceryListItem) {
            isChecked = item.isChecked
            isBought = item.isBought
            boughtAt = item.boughtAt
            reminderIdentifier = item.reminderIdentifier
        }
    }

    /// A manually-added item, captured as plain data (not the SwiftData
    /// object — the old list it belongs to gets cascade-deleted) so it can
    /// be recreated verbatim on the new list. Manual items never come from
    /// `GroceryListGenerator`, so nothing else would reproduce them.
    private struct PreservedManualItem {
        let canonicalFoodName: String
        let displayName: String
        let quantity: Double
        let unit: PantryUnit
        let category: String
        let isChecked: Bool
        let isBought: Bool
        let boughtAt: Date?
        let reminderIdentifier: String?
        let estimatedPriceUSD: Double?
        let priceSource: GroceryPriceSource?
        let notes: String?

        init(item: GroceryListItem) {
            canonicalFoodName = item.canonicalFoodName
            displayName = item.displayName
            quantity = item.quantity
            unit = item.unit
            category = item.category
            isChecked = item.isChecked
            isBought = item.isBought
            boughtAt = item.boughtAt
            reminderIdentifier = item.reminderIdentifier
            estimatedPriceUSD = item.estimatedPriceUSD
            priceSource = item.priceSource
            notes = item.notes
        }

        func makeItem(list: GroceryList) -> GroceryListItem {
            GroceryListItem(
                list: list,
                canonicalFoodName: canonicalFoodName,
                displayName: displayName,
                quantity: quantity,
                unit: unit,
                category: category,
                isChecked: isChecked,
                isManual: true,
                isBought: isBought,
                boughtAt: boughtAt,
                reminderIdentifier: reminderIdentifier,
                estimatedPriceUSD: estimatedPriceUSD,
                priceSource: priceSource,
                notes: notes
            )
        }
    }

    /// `weekStartDate` MUST be the source plan's Monday (its `startDate`),
    /// not "today" — that's what makes regenerating mid-week REPLACE that
    /// week's list instead of spawning a second one (BUILD item 1a). Ticks
    /// and manually-added items from any list(s) already covering that week
    /// survive the replace (BUILD item 1b); lists more than
    /// `retentionWeeks` old are pruned on every generate.
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
            weekStartDate: weekStartDate
        ))

        let weekStart = Calendar.current.startOfDay(for: weekStartDate)
        let existingDescriptor = FetchDescriptor<GroceryList>(
            predicate: #Predicate<GroceryList> { list in
                list.weekStartDate == weekStart
            }
        )
        let existingLists = try modelContext.fetch(existingDescriptor)

        var preservedState: [String: PreservedItemState] = [:]
        var preservedManual: [PreservedManualItem] = []
        for old in existingLists {
            for item in old.items ?? [] {
                if item.isManual {
                    preservedManual.append(PreservedManualItem(item: item))
                } else {
                    preservedState[item.canonicalFoodName] = PreservedItemState(item: item)
                }
            }
        }

        // Nothing to shop for at all (no plan-derived items AND no manual
        // items to carry forward) — same "empty plan" error as before.
        guard !aggregated.isEmpty || !preservedManual.isEmpty else {
            throw GroceryListServiceError.noMealsToShop
        }

        for old in existingLists {
            modelContext.delete(old)
        }
        pruneOldLists(referenceDate: weekStartDate)

        let list = GroceryList(
            weekStartDate: weekStart,
            sourceMealPlanID: mealPlan.id
        )
        modelContext.insert(list)

        var items: [GroceryListItem] = aggregated.map { entry in
            let state = preservedState[entry.canonicalName]
            return GroceryListItem(
                list: list,
                canonicalFoodName: entry.canonicalName,
                displayName: entry.displayName,
                quantity: entry.quantity,
                unit: entry.unit,
                category: entry.category,
                isChecked: state?.isChecked ?? false,
                isBought: state?.isBought ?? false,
                boughtAt: state?.boughtAt,
                reminderIdentifier: state?.reminderIdentifier
            )
        }
        // A pantry "ran out" row the new plan now covers itself would show
        // twice — the plan row wins. User-typed manual items always stay.
        let planned = Set(aggregated.map(\.canonicalName))
        let carried = preservedManual.filter { manual in
            !(manual.category == PantryGroceryBridge.category && !manual.isBought && planned.contains(manual.canonicalFoodName))
        }
        items.append(contentsOf: carried.map { $0.makeItem(list: list) })
        list.items = items
        try modelContext.save()
        logger
            .info(
                "Grocery list generated: \(items.count) items (\(carried.count) preserved manual), week \(weekStart.ISO8601Format(), privacy: .public)"
            )
        return list
    }

    /// Deletes grocery lists whose week is more than `retentionWeeks` in the
    /// past relative to `referenceDate` — old shopping trips aren't useful
    /// to keep around forever. Runs on every `generate()` call.
    private func pruneOldLists(retentionWeeks: Int = 4, referenceDate: Date) {
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
        for list in old {
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let item = GroceryListItem(
            list: list,
            canonicalFoodName: trimmed.lowercased(),
            displayName: trimmed.isEmpty ? "Item" : trimmed,
            quantity: unit.wholeUnitQuantity(max(0, quantity)),
            unit: unit,
            category: category,
            isManual: true
        )
        modelContext.insert(item)
        try modelContext.save()
        return item
    }

    func deleteItem(_ item: GroceryListItem) throws {
        modelContext.delete(item)
        try modelContext.save()
    }

    @discardableResult
    func reapplyPantry(_ pantry: any PantryServiceProtocol) throws -> Int {
        guard let list = try fetchLatest(), let items = list.items else {
            return 0
        }
        let pantryItems = (try? pantry.fetchAll()) ?? []

        // Normalize pantry stock to grams per food name. PantryUnit.gramsApprox
        // handles all weight/volume conversions deterministically; for
        // container units (packs/cans/etc) it consults FoodMacroDatabase's
        // naturalPortions table so "1 pack of pasta" resolves to 500g.
        // Items whose unit can't be converted (e.g. .pieces of an obscure
        // food not in naturalPortions) contribute zero to the gram total —
        // we'd rather under-dedup than guess.
        //
        // PantryItem.canonicalName and GroceryListItem.canonicalFoodName
        // share the same lowercased/trimmed convention.
        var availableGrams: [String: Double] = [:]
        for p in pantryItems {
            guard let grams = p.unit.gramsApprox(quantity: p.quantity, foodName: p.canonicalName) else {
                continue
            }
            availableGrams[p.canonicalName, default: 0] += grams
        }

        var removed = 0
        for item in items where !item.isChecked {
            // Already-bought items are preserved — they're history of the
            // current shopping trip, not a re-evaluation target.
            guard let onHand = availableGrams[item.canonicalFoodName], onHand > 0 else {
                continue
            }
            guard let itemGrams = item.unit.gramsApprox(quantity: item.quantity, foodName: item.canonicalFoodName),
                  itemGrams > 0
            else {
                // Grocery item is in a unit we can't convert to grams (no
                // food-specific portion data). Skip — better to leave it
                // on the list than guess wrong and delete something the
                // user still needs to buy.
                continue
            }
            if onHand >= itemGrams {
                modelContext.delete(item)
                removed += 1
                availableGrams[item.canonicalFoodName] = onHand - itemGrams
            } else {
                // Partial coverage: shrink the grocery item proportionally
                // in its own unit so the user still buys the remainder.
                // Countable units (cans/packs/…) are re-rounded UP afterward
                // — a proportional shrink can otherwise leave "0.4 cans",
                // which isn't a purchasable quantity (BUILD item 1d).
                let coverage = onHand / itemGrams
                let shrunk = item.quantity * (1 - coverage)
                item.quantity = item.unit.wholeUnitQuantity(shrunk)
                availableGrams[item.canonicalFoodName] = 0
            }
        }
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
    static func reminderTitle(name: String, quantity: Double, unit: PantryUnit) -> String {
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
                reminder.title = Self.reminderTitle(name: item.displayName, quantity: item.quantity, unit: item.unit)
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
                    reminder.title = Self.reminderTitle(name: item.displayName, quantity: item.quantity, unit: item.unit)
                    reminder.notes = "\(title)\nCategory: \(item.category)"
                    reminder.isCompleted = item.isChecked
                    try? eventStore.save(reminder, commit: false)
                    item.reminderIdentifier = reminder.calendarItemIdentifier
                    continue
                }
                reminder.title = Self.reminderTitle(name: item.displayName, quantity: item.quantity, unit: item.unit)
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let item = GroceryListItem(
            list: list,
            canonicalFoodName: trimmed.lowercased(),
            displayName: trimmed.isEmpty ? "Item" : trimmed,
            quantity: unit.wholeUnitQuantity(max(0, quantity)),
            unit: unit,
            category: category,
            isManual: true
        )
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
