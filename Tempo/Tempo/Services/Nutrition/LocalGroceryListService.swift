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

        guard !aggregated.isEmpty else {
            throw GroceryListServiceError.noMealsToShop
        }

        // Replace any existing list for the same week.
        let weekStart = Calendar.current.startOfDay(for: weekStartDate)
        let existingDescriptor = FetchDescriptor<GroceryList>(
            predicate: #Predicate<GroceryList> { list in
                list.weekStartDate == weekStart
            }
        )
        let existing = try modelContext.fetch(existingDescriptor)
        for old in existing {
            modelContext.delete(old)
        }

        let list = GroceryList(
            weekStartDate: weekStart,
            sourceMealPlanID: mealPlan.id
        )
        modelContext.insert(list)
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
        try modelContext.save()
        logger.info("Grocery list generated: \(aggregated.count) items, week \(weekStart.ISO8601Format(), privacy: .public)")
        return list
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
            quantity: max(0, quantity),
            unit: unit,
            category: category
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
        // Build a map of canonical name → total available quantity in pantry
        // (in the item's own unit; cross-unit math lives in PantryUnit
        // canonicalization, which we don't reach into here).
        var available: [String: Double] = [:]
        for p in pantryItems {
            // PantryItem.canonicalName matches GroceryListItem.canonicalFoodName
            // — both are lowercased+trimmed by their respective writers.
            available[p.canonicalName, default: 0] += p.quantity
        }
        var removed = 0
        for item in items where !item.isChecked {
            // Already-bought items are preserved — they're history of the
            // current shopping trip, not a re-evaluation target.
            guard let onHand = available[item.canonicalFoodName], onHand > 0 else { continue }
            if onHand >= item.quantity {
                modelContext.delete(item)
                removed += 1
                available[item.canonicalFoodName] = onHand - item.quantity
            } else {
                item.quantity -= onHand
                available[item.canonicalFoodName] = 0
            }
        }
        try modelContext.save()
        return removed
    }

    func delete(_ list: GroceryList) throws {
        modelContext.delete(list)
        try modelContext.save()
    }

    // MARK: - Reminders export

    func exportToReminders(_ list: GroceryList) async throws {
        // Request access. iOS 17+ uses requestFullAccessToReminders.
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

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw GroceryListServiceError.remindersExportFailed("No default Reminders list configured.")
        }

        let title = "Tempo Grocery — \(list.weekStartDate.formatted(date: .abbreviated, time: .omitted))"

        // Parent reminder serves as a container — child items are flat in the
        // user's default list with the parent title as a prefix for grouping.
        for item in list.orderedItems where !item.isChecked {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.title = "\(item.displayName) — \(Int(item.quantity))\(item.unit.displayName)"
            reminder.notes = "\(title)\nCategory: \(item.category)"
            do {
                try eventStore.save(reminder, commit: false)
            } catch {
                throw GroceryListServiceError.remindersExportFailed(error.localizedDescription)
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
        logger.info("Grocery list exported to Reminders: \(list.itemCount) items")
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
            quantity: max(0, quantity),
            unit: unit,
            category: category
        )
        if list.items == nil { list.items = [] }
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
        return 0
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
}
