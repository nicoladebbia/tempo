//
// PantryGroceryBridge.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

// MARK: - PantryGroceryBridge

/// The ONE pantry-side door into the grocery list. Pantry Smarts needs to
/// push a handful of things onto the shopping list — "I'm out of rice",
/// a depleted ingredient, a staple that ran low — without reaching into
/// `GroceryListGenerator` or `LocalGroceryListService` (owned by the
/// grocery-list lane in parallel). This file is deliberately the ONLY
/// pantry code that touches `GroceryList` / `GroceryListItem` directly.
@MainActor
enum PantryGroceryBridge {
    /// Category used for pantry-originated additions — keeps them visually
    /// grouped in the grocery list rather than scattered across produce/
    /// protein/etc. sections meant for plan-derived items.
    static let category = "pantry"

    /// Finds the current week's `GroceryList` (creating an empty one if
    /// none exists yet) and appends a `GroceryListItem` for
    /// `canonicalName` — or, if that food is already on the list, reuses
    /// that row (bumping our own pantry row's amount when the unit matches)
    /// instead of creating a duplicate.
    ///
    /// Used for: staple needs (low/out), "I'm out of X" voice edits, and
    /// pantry items that hit zero via decrement or manual edit.
    @discardableResult
    static func addToCurrentGroceryList(
        canonicalName: String,
        displayName: String,
        quantity: Double,
        unit: PantryUnit,
        modelContext: ModelContext
    ) throws -> GroceryListItem {
        let canonical = FoodCanonicalizer.canonicalize(canonicalName)
        let display = displayName.trimmingCharacters(in: .whitespaces)
        let list = try findOrCreateCurrentWeekList(modelContext: modelContext)

        let sameFood = (list.items ?? []).filter { $0.canonicalFoodName == canonical }
        // Already on the list and still to buy — in any unit. Plan items use
        // their own purchase unit (grams, packs…), so matching on unit here
        // would add a second row for the same food.
        if let open = sameFood.first(where: { !$0.isBought }) {
            // Only bump our own pantry rows; a plan row already covers the
            // week's need and stays the planner's (not manual), so a plan
            // regenerate doesn't duplicate it.
            if open.isManual, open.unitRaw == unit.rawValue {
                open.quantity += max(0, quantity)
                try modelContext.save()
            }
            return open
        }
        if let bought = sameFood.first {
            // Bought on an earlier trip and now needed again — back on the
            // list as a fresh item, not added to the old amount. A plan row
            // keeps its unit/amount (regenerate carries its un-bought state).
            bought.isBought = false
            bought.boughtAt = nil
            bought.isChecked = false
            if bought.isManual {
                bought.quantity = max(0, quantity)
                bought.unit = unit
            }
            try modelContext.save()
            return bought
        }

        let item = GroceryListItem(
            list: list,
            canonicalFoodName: canonical,
            displayName: display.isEmpty ? canonical : display,
            quantity: max(0, quantity),
            unit: unit,
            category: category
        )
        // Pantry-driven ("I'm out of rice", a staple running low) — the
        // regenerate keeps manual items, so these survive a plan rebuild.
        item.isManual = true
        modelContext.insert(item)
        if list.items == nil {
            list.items = []
        }
        list.items?.append(item)
        try modelContext.save()
        return item
    }

    /// The Monday (00:00, current calendar) of `date`'s week. Kept for
    /// callers/tests that want a stable "this calendar week" key — NOT used
    /// to look up the list a pantry add should land on (see
    /// `findOrCreateCurrentWeekList` below).
    static func currentWeekMonday(from date: Date = Date()) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay) // 1 = Sunday ... 7 = Saturday
        let daysSinceMonday = (weekday + 5) % 7 // Sun(1)->6, Mon(2)->0, Tue(3)->1, ...
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay) ?? startOfDay
    }

    /// Finds the list the Grocery tab is actually showing right now, so a
    /// pantry-originated add never lands on an orphaned list the UI never
    /// surfaces.
    ///
    /// `LocalGroceryListService.generate(weekStartDate:)` keys a list by
    /// whatever day the user tapped "Generate" (`Calendar.startOfDay(now)`
    /// at generation time — NOT necessarily a Monday), and
    /// `fetchLatest()`/the Grocery tab always show the list with the
    /// newest `weekStartDate`. Keying this lookup off `currentWeekMonday()`
    /// instead would almost always miss that list (any day but Monday) and
    /// silently create a second, older-dated list nobody sees. So this
    /// mirrors `fetchLatest()`'s own "most recent list" query exactly, and
    /// only falls back to creating a new one (dated today, same convention
    /// `generateGroceryList` uses) when no list exists at all yet.
    private static func findOrCreateCurrentWeekList(modelContext: ModelContext) throws -> GroceryList {
        var descriptor = FetchDescriptor<GroceryList>(
            sortBy: [SortDescriptor(\.weekStartDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        // Lists are keyed by the plan's Monday; a list from an earlier week
        // is stale, so start this week's (the plan regenerate for the same
        // Monday then merges into it, keeping these manual items).
        let thisMonday = currentWeekMonday()
        if let existing = try modelContext.fetch(descriptor).first, existing.weekStartDate >= thisMonday {
            return existing
        }
        let list = GroceryList(weekStartDate: thisMonday, sourceMealPlanID: nil)
        modelContext.insert(list)
        return list
    }
}
