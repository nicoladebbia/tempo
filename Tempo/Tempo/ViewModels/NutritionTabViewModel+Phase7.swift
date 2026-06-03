//
// NutritionTabViewModel+Phase7.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - NutritionPantryState

@MainActor
@Observable
final class NutritionPantryState {
    /// All non-archived pantry items, sorted by recent activity.
    var items: [PantryItem] = []
    /// Items expiring within 3 days (computed at load time).
    var expiringSoon: [PantryItem] = []
    var loadError: String?
    /// True while a load is in flight.
    var isLoading: Bool = false
    /// Most-recent locked-in total price (USD) per canonical food name, for
    /// the per-item "last paid" label. Built in reloadPantry from
    /// PantryPriceEntry — keyed by food so it survives item churn.
    var latestPriceByFood: [String: Double] = [:]
}

// MARK: - NutritionReceiptState

@MainActor
@Observable
final class NutritionReceiptState {
    var receipts: [Receipt] = []
    var loadError: String?
    var isLoading: Bool = false
}

// MARK: - NutritionRecipeState

@MainActor
@Observable
final class NutritionRecipeState {
    var allRecipes: [Recipe] = []
    var suggestions: [RecipeSuggestion] = []
    var lastSuggestionAt: Date?
    var loadError: String?
    var isLoading: Bool = false
}

// MARK: - NutritionGroceryState

@MainActor
@Observable
final class NutritionGroceryState {
    var latest: GroceryList?
    var isGenerating: Bool = false
    var isExporting: Bool = false
    var lastError: String?
}

// MARK: - ViewModel extension

extension NutritionTabViewModel {
    /// Attach the Phase 2–6 services and trigger initial loads. Idempotent —
    /// safe to call from `task` on the view body.
    func attachPhase7Services(
        modelContext: ModelContext,
        services: ServiceContainer
    ) {
        let logger = Logger.nutrition

        // Capture the context for price-history inserts (addPantryItem). Set
        // before the idempotency guard so it's always current even on the
        // sibling re-mount that bails below.
        pantryModelContext = modelContext

        // Idempotent: three sibling Nutrition sub-views (Pantry, GroceryList,
        // RecipeSuggestions) each call this from their `.task`. Once the
        // services are wired and the initial reloads have run, bail — otherwise
        // the four reload*() calls below re-hit SwiftData on every sibling
        // mount (and the log line double-fires). `pantryService` is the first
        // thing set unconditionally below, so it doubles as the
        // "already attached" sentinel.
        guard pantryService == nil else { return }

        pantryService = LocalPantryService(modelContext: modelContext)
        services.pantry = pantryService
        if receiptService == nil, let api = phase7APIClient(from: services) {
            receiptService = LiveReceiptService(modelContext: modelContext, apiClient: api)
            services.receipts = receiptService
        }
        if recipeService == nil {
            recipeService = LocalRecipeService(modelContext: modelContext)
            services.recipes = recipeService
        }
        if groceryService == nil {
            groceryService = LocalGroceryListService(modelContext: modelContext)
            services.groceryList = groceryService
        }
        if intelligence == nil {
            intelligence = services.nutritionIntelligence
        }

        logger.info("Phase 7 services attached to NutritionTabViewModel")

        reloadPantry()
        reloadReceipts()
        reloadRecipes()
        reloadGrocery()
    }

    // MARK: - Pantry

    func reloadPantry() {
        guard let service = pantryService else {
            return
        }
        pantryState.isLoading = true
        defer { pantryState.isLoading = false }
        do {
            let items = try service.fetchAll()
            pantryState.items = items
            pantryState.expiringSoon = items.filter(\.isExpiringSoon)
            pantryState.loadError = nil
        } catch {
            pantryState.loadError = error.localizedDescription
        }

        // Build the latest-price-per-food map for the per-item "last paid"
        // label. Keyed by canonical food name (not item) so it survives churn.
        if let context = pantryModelContext {
            let descriptor = FetchDescriptor<PantryPriceEntry>(
                sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)]
            )
            if let entries = try? context.fetch(descriptor) {
                var latest: [String: Double] = [:]
                // Descending by date → first seen per food is the most recent.
                for entry in entries where latest[entry.canonicalFoodName] == nil {
                    latest[entry.canonicalFoodName] = entry.totalPaidUSD
                }
                pantryState.latestPriceByFood = latest
            }
        }
    }

    func addPantryItem(
        rawName: String,
        quantity: Double,
        unit: PantryUnit,
        storageLocation: PantryStorageLocation,
        totalPaidUSD: Double? = nil,
        brand: String = ""
    ) {
        guard let service = pantryService else {
            return
        }
        do {
            let now = Date()
            let item = try service.mergeOrCreate(
                rawName: rawName,
                quantity: quantity,
                unit: unit,
                storageLocation: storageLocation,
                purchaseDate: now,
                purchaseSource: .manual,
                sourceReceiptLineItemID: nil,
                brand: brand
            )
            // Lock the price into history when supplied. One INSERT per
            // purchase keyed by the canonical food name (not the item), so the
            // time series survives this item being consumed/archived. Uses the
            // merged item's canonicalName so manual + scan history share a key.
            if let totalPaidUSD, totalPaidUSD > 0, let context = pantryModelContext {
                let entry = PantryPriceEntry(
                    canonicalFoodName: item.canonicalName,
                    displayName: item.displayName,
                    purchaseDate: now,
                    totalPaidUSD: totalPaidUSD,
                    quantity: quantity,
                    unit: unit,
                    source: .manual,
                    sourcePantryItemID: item.id
                )
                context.insert(entry)
                try? context.save()
            }
            reloadPantry()
            // The pantry just grew → re-deduct it from the active grocery list
            // so anything you've now got drops off "to buy". No-op when there's
            // no active list. Preserves already-checked items (see reapplyPantry).
            reapplyPantryToGrocery()
        } catch {
            pantryState.loadError = error.localizedDescription
        }
    }

    /// SET a pantry item's quantity (voice stock-take). Mirrors addPantryItem
    /// but routes through `setOrCreate` (REPLACE, not increment) and carries no
    /// price history — a stock statement ("I have 750 g") is not a purchase.
    func setPantryItem(
        rawName: String,
        quantity: Double,
        unit: PantryUnit,
        storageLocation: PantryStorageLocation,
        brand: String = ""
    ) {
        guard let service = pantryService else {
            return
        }
        do {
            _ = try service.setOrCreate(
                rawName: rawName,
                quantity: quantity,
                unit: unit,
                storageLocation: storageLocation,
                purchaseDate: Date(),
                purchaseSource: .manual,
                brand: brand
            )
            reloadPantry()
            // Stock-take updated the pantry → shrink the active grocery list.
            reapplyPantryToGrocery()
        } catch {
            pantryState.loadError = error.localizedDescription
        }
    }

    func archivePantryItem(_ item: PantryItem) {
        guard let service = pantryService else {
            return
        }
        do {
            try service.archive(item)
            // Don't clear loadError here — archive ≠ fetch; if a prior load
            // failed, hiding that during a successful archive masks the
            // root cause. reloadPantry() below will overwrite either way.
        } catch {
            // Surface via the load error channel since it's the existing
            // user-visible field; renaming the field is a follow-up.
            pantryState.loadError = "Couldn't archive item: \(error.localizedDescription)"
        }
        reloadPantry()
    }

    // MARK: - Receipts

    func reloadReceipts() {
        guard let service = receiptService else {
            return
        }
        receiptState.isLoading = true
        defer { receiptState.isLoading = false }
        do {
            receiptState.receipts = try service.fetchAll()
            receiptState.loadError = nil
        } catch {
            receiptState.loadError = error.localizedDescription
        }
    }

    // MARK: - Recipes

    func reloadRecipes() {
        guard let service = recipeService else {
            return
        }
        recipeState.isLoading = true
        defer { recipeState.isLoading = false }
        do {
            recipeState.allRecipes = try service.fetchAll()
            recipeState.loadError = nil
        } catch {
            recipeState.loadError = error.localizedDescription
        }
    }

    /// Rank recipes against the current pantry + today's remaining macros.
    /// Includes expiry-urgency weighting (FIFO) so soon-to-expire items surface first.
    func refreshRecipeSuggestions(limit: Int = 8) {
        guard let recipeService else {
            return
        }
        let activePantry = pantryState.items.filter { $0.quantity > 0 }
        let pantryNames = Set(activePantry.map(\.canonicalName))
        var expiryByName: [String: Int] = [:]
        for item in activePantry {
            guard let days = item.daysUntilUseBy, days >= 0 else { continue }
            // Keep the soonest expiry per canonical name if duplicates exist.
            if let existing = expiryByName[item.canonicalName], existing <= days {
                continue
            }
            expiryByName[item.canonicalName] = days
        }
        let remainingCal = max(0, todayCalorieTarget - todayCaloriesConsumed)
        let remainingProtein = max(0, todayProteinTarget - todayProteinConsumed)
        let remainingCarbs = max(0, todayCarbsTarget - todayCarbsConsumed)
        let remainingFat = max(0, todayFatTarget - todayFatConsumed)

        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: pantryNames,
            pantryExpiryByName: expiryByName,
            remainingCalories: remainingCal,
            remainingProtein: remainingProtein,
            remainingCarbs: remainingCarbs,
            remainingFat: remainingFat
        )

        do {
            recipeState.suggestions = try recipeService.suggest(inputs: inputs, limit: limit)
            recipeState.lastSuggestionAt = Date()
            recipeState.loadError = nil
        } catch {
            recipeState.loadError = error.localizedDescription
        }
    }

    // MARK: - Grocery

    func reloadGrocery() {
        guard let service = groceryService else {
            return
        }
        do {
            groceryState.latest = try service.fetchLatest()
            groceryState.lastError = nil
        } catch {
            groceryState.lastError = error.localizedDescription
        }
    }

    /// Generate this week's grocery list from the active meal plan + current pantry.
    func generateGroceryList() {
        guard let groceryService, let pantryService else {
            return
        }
        guard let plan = weeklyPlan else {
            groceryState.lastError = "Generate a meal plan first."
            return
        }
        groceryState.isGenerating = true
        defer { groceryState.isGenerating = false }
        do {
            let weekStart = Calendar.current.startOfDay(for: Date())
            let list = try groceryService.generate(
                from: plan,
                pantry: pantryService,
                weekStartDate: weekStart
            )
            groceryState.latest = list
            groceryState.lastError = nil
        } catch {
            groceryState.lastError = error.localizedDescription
        }
    }

    func toggleGroceryItem(_ item: GroceryListItem) {
        guard let service = groceryService else {
            return
        }
        do {
            try service.toggleChecked(item)
            groceryState.lastError = nil
        } catch {
            groceryState.lastError = error.localizedDescription
        }
    }

    /// User-added "oh, also" item. Refreshes the latest list so the UI
    /// reflects the new row immediately.
    func addGroceryItem(name: String, quantity: Double, unit: PantryUnit) {
        guard let service = groceryService else { return }
        do {
            _ = try service.addItem(name: name, quantity: quantity, unit: unit, category: "pantry")
            groceryState.latest = try service.fetchLatest()
            groceryState.lastError = nil
        } catch {
            groceryState.lastError = error.localizedDescription
        }
    }

    /// Swipe-to-delete from the list. Refreshes latest after the remove.
    func deleteGroceryItem(_ item: GroceryListItem) {
        guard let service = groceryService else { return }
        do {
            try service.deleteItem(item)
            groceryState.latest = try service.fetchLatest()
            groceryState.lastError = nil
        } catch {
            groceryState.lastError = error.localizedDescription
        }
    }

    /// Re-run pantry deduction on the active grocery list. Call after the
    /// user has updated the pantry mid-week (added items they just bought
    /// without going through the list) so the list shrinks accordingly.
    /// Returns the count of items removed for surfacing to the user.
    @discardableResult
    func reapplyPantryToGrocery() -> Int {
        guard let service = groceryService, let pantryService else { return 0 }
        do {
            let removed = try service.reapplyPantry(pantryService)
            groceryState.latest = try service.fetchLatest()
            groceryState.lastError = nil
            return removed
        } catch {
            groceryState.lastError = error.localizedDescription
            return 0
        }
    }

    func exportGroceryListToReminders() async {
        guard let groceryService, let list = groceryState.latest else {
            groceryState.lastError = "No grocery list to export."
            return
        }
        groceryState.isExporting = true
        defer { groceryState.isExporting = false }
        do {
            try await groceryService.exportToReminders(list)
            groceryState.lastError = nil
        } catch {
            groceryState.lastError = error.localizedDescription
        }
    }

    // MARK: - Intelligence shortcut

    /// Drill-sergeant explanation of today's macro adjustment, surfaced on the
    /// Today/Coach tabs. Returns nil when there's no adjustment to explain.
    func explainTodayAdjustment(adjustment: AdjustedNutritionTargets) async -> String? {
        guard let intelligence else {
            return nil
        }
        let zone: RecoveryZone? = recoveryZone.flatMap {
            switch $0 {
            case "green": .green
            case "yellow": .yellow
            case "red": .red
            default: nil
            }
        }
        let isTrainingDay = !todayMeals.isEmpty
        return await intelligence.explainAdjustment(
            for: adjustment,
            recoveryZone: zone,
            isTrainingDay: isTrainingDay
        )
    }

    // MARK: - APIClient helper

    private func phase7APIClient(from services: ServiceContainer) -> APIClient? {
        // ServiceContainer exposes a configured, auth-attaching APIClient.
        // Returning it here lets attachPhase7Services build the real
        // LiveReceiptService (vision OCR → structuring → pantry) instead
        // of leaving receiptService nil, which made the Pantry Scan button
        // show "Scan unavailable — open the Pantry tab first" forever.
        services.apiClient
    }
}

// Storage hooks removed: Phase 7 state/services are now stored directly on
// the base class so they share the ViewModel's lifetime. The previous
// `ObjectIdentifier`-keyed static dictionaries leaked every instance forever.
