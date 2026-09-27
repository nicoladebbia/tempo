//
// NutritionTabViewModel+GroceryAdvanced.swift
// Tempo
//
// "Advanced groceries" Lane A: store mode + aisle-order learning, bought →
// pantry (Done Shopping), and cost/budget. Kept in its own extension file
// (rather than growing NutritionTabViewModel+Phase7.swift) since Lane B
// (pantry expiry/receipts) and Lane C (share/Instacart) are working in that
// same area in parallel worktrees — smaller diff surface, fewer merge
// conflicts.
//

import Foundation
import os
import SwiftData

// MARK: - NutritionGroceryStoreModeState

@MainActor
@Observable
final class NutritionGroceryStoreModeState {
    /// Distinct categories, in the order the user first ticked an item in
    /// each, for the CURRENT Store Mode session. Committed into
    /// UserSettings' learned ordering when the session ends (Done Shopping,
    /// or leaving Store Mode).
    var sessionTickOrder: [String] = []

    /// Cheaper-swap suggestions from the last `fetchCheaperSwaps()` call.
    var cheaperSwaps: [String] = []
    var isFetchingSwaps = false
    var swapsError: String?

    /// Weekly spend vs. budget for the last ~8 weeks.
    var weeklySpend: [GroceryWeeklySpend] = []
}

// MARK: - ViewModel extension

extension NutritionTabViewModel {
    // MARK: - Store selection

    /// The active store chain, read/written straight through to
    /// UserSettings so it persists across launches and drives both aisle
    /// ordering and price-history matching.
    var groceryActiveStore: GroceryStore {
        get { loadUserSettingsForGrocery()?.groceryActiveStore ?? .generic }
        set {
            guard let settings = loadUserSettingsForGrocery() else {
                return
            }
            settings.groceryActiveStore = newValue
            try? pantryModelContext?.save()
            // A different store can change which price-history entries
            // count as "same store" — re-resolve so the total isn't stale.
            refreshGroceryPrices()
        }
    }

    /// Aisle order for the categories actually present on `list`, blending
    /// the active store's authored default with anything learned from past
    /// trips (see GroceryStoreLayout).
    func resolvedGroceryCategoryOrder(for list: GroceryList) -> [String] {
        let present = Array(Set(list.activeItems.map(\.category)))
        let store = groceryActiveStore
        let learning = loadUserSettingsForGrocery()?.groceryCategoryLearning[store.rawValue]
            ?? GroceryStoreLayout.CategoryRankLearning()
        return GroceryStoreLayout.resolvedOrder(store: store, presentCategories: present, learning: learning)
    }

    // MARK: - Store Mode learning session

    /// Called the FIRST time an item in `category` is ticked during a Store
    /// Mode session. No-ops for a category already recorded this session
    /// (only the first tick per category counts toward the trip's order).
    func recordGroceryCategoryTick(_ category: String) {
        guard !groceryStoreModeState.sessionTickOrder.contains(category) else {
            return
        }
        groceryStoreModeState.sessionTickOrder.append(category)
    }

    /// Folds the current session's tick order into the store's persisted
    /// learning and resets the session. Call when Store Mode ends (Done
    /// Shopping tapped, or the sheet is dismissed).
    func commitGroceryStoreModeSession() {
        defer { groceryStoreModeState.sessionTickOrder = [] }
        guard !groceryStoreModeState.sessionTickOrder.isEmpty,
              let settings = loadUserSettingsForGrocery()
        else {
            return
        }
        let store = settings.groceryActiveStore
        var perStore = settings.groceryCategoryLearning
        var learning = perStore[store.rawValue] ?? GroceryStoreLayout.CategoryRankLearning()
        GroceryStoreLayout.recordTripOrder(groceryStoreModeState.sessionTickOrder, into: &learning)
        perStore[store.rawValue] = learning
        settings.groceryCategoryLearning = perStore
        try? pantryModelContext?.save()
    }

    // MARK: - Pricing

    /// Resolves a price for every active item on the current list: paid
    /// history first, then the local AI-estimate cache, then ONE batched AI
    /// call for whatever's still unpriced. Runs fully async and NEVER blocks
    /// list display — items simply show no price (or a stale/paid one) until
    /// this completes. Safe to call repeatedly (e.g. after generate, after
    /// changing store); each call only pays for names still unresolved.
    func refreshGroceryPrices() {
        guard let groceryService, let context = pantryModelContext else {
            return
        }
        guard let list = try? groceryService.fetchLatest() else {
            return
        }
        let store = groceryActiveStore
        let history = (try? context.fetch(FetchDescriptor<PantryPriceEntry>())) ?? []

        var unresolvedNames: Set<String> = []
        var cache = GroceryPriceCache.load()

        for item in list.activeItems {
            if let paid = GroceryPriceEstimator.resolveFromHistory(
                canonicalName: item.canonicalFoodName,
                quantity: item.quantity,
                unit: item.unit,
                store: store,
                history: history
            ) {
                item.estimatedPriceUSD = paid.usd
                item.priceSource = paid.source
                continue
            }
            if let cached = cache.price(store: store, canonicalName: item.canonicalFoodName) {
                item.estimatedPriceUSD = cached
                item.priceSource = .estimate
                continue
            }
            unresolvedNames.insert(item.canonicalFoodName)
        }
        try? context.save()

        guard !unresolvedNames.isEmpty, let aiService = groceryPriceAIService else {
            return
        }
        let namesToFetch = Array(unresolvedNames)
        Task {
            do {
                let estimates = try await aiService.estimatePrices(names: namesToFetch, store: store)
                guard !estimates.isEmpty else {
                    return
                }
                for (name, usd) in estimates {
                    cache.set(store: store, canonicalName: name, usd: usd)
                }
                cache.save()
                guard let refreshedList = try? groceryService.fetchLatest() else {
                    return
                }
                for item in refreshedList.activeItems {
                    guard let usd = estimates[item.canonicalFoodName] else {
                        continue
                    }
                    item.estimatedPriceUSD = usd
                    item.priceSource = .estimate
                }
                try? context.save()
                Logger.nutrition.info("[Diag.Grocery] AI-priced \(estimates.count) items at \(store.rawValue, privacy: .public)")
            } catch {
                Logger.nutrition.warning("[Diag.Grocery] price estimate failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Weekly budget cap, or nil if the user hasn't set one.
    var groceryBudgetCapUSD: Int? {
        loadUserSettingsForGrocery()?.groceryBudgetCapUSD
    }

    /// `true` when the active list's estimated total exceeds the budget cap.
    /// `false` when there's no cap or no active list — "over budget" only
    /// means something once both exist.
    func groceryIsOverBudget() -> Bool {
        guard let cap = groceryBudgetCapUSD, let list = groceryState.latest else {
            return false
        }
        return list.estimatedTotalUSD > Double(cap)
    }

    /// Fetches a short list of cheaper-swap suggestions for the active list.
    /// No-ops (clearing suggestions) if the list isn't over budget.
    func fetchCheaperSwaps() async {
        guard let list = groceryState.latest, let aiService = groceryPriceAIService,
              let cap = groceryBudgetCapUSD, list.estimatedTotalUSD > Double(cap)
        else {
            groceryStoreModeState.cheaperSwaps = []
            return
        }
        groceryStoreModeState.isFetchingSwaps = true
        defer { groceryStoreModeState.isFetchingSwaps = false }
        do {
            let names = list.activeItems.map(\.displayName)
            let overBy = list.estimatedTotalUSD - Double(cap)
            groceryStoreModeState.cheaperSwaps = try await aiService.suggestCheaperSwaps(
                items: names, overBy: overBy, store: groceryActiveStore
            )
            groceryStoreModeState.swapsError = nil
        } catch {
            groceryStoreModeState.swapsError = error.localizedDescription
        }
    }

    // MARK: - Weekly spend history

    /// Loads the last 8 weeks' actual spend (PantryPriceEntry + Receipt)
    /// vs. the budget cap into `groceryStoreModeState.weeklySpend`.
    func loadGroceryWeeklySpendHistory() {
        guard let context = pantryModelContext else {
            return
        }
        let entries = (try? context.fetch(FetchDescriptor<PantryPriceEntry>())) ?? []
        let receipts = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
        groceryStoreModeState.weeklySpend = GroceryWeeklySpendCalculator.compute(
            priceEntries: entries,
            receipts: receipts,
            weeks: 8,
            budgetCapUSD: groceryBudgetCapUSD
        )
    }

    // MARK: - Done shopping → pantry

    /// One confirmed row from the Done-Shopping review sheet: the user can
    /// edit quantity/unit/storage before it's written to the pantry, and
    /// optionally record what they paid.
    struct GroceryBoughtConfirmation {
        let item: GroceryListItem
        var quantity: Double
        var unit: PantryUnit
        var storageLocation: PantryStorageLocation
        var totalPaidUSD: Double?
    }

    /// "Add to pantry" from the Done-Shopping sheet (BUILD item 3): adds each
    /// confirmed item to the pantry via the existing service (so Lane B's
    /// expiry estimation on the add path runs same as any other add), writes
    /// a PantryPriceEntry when a price was given, and marks the grocery item
    /// bought (kept as a record, not deleted).
    func confirmGroceryBought(_ confirmations: [GroceryBoughtConfirmation]) {
        guard let pantryService, let groceryService, let context = pantryModelContext else {
            return
        }
        let now = Date()
        let store = groceryActiveStore
        var boughtItems: [GroceryListItem] = []

        for confirmation in confirmations {
            do {
                // NOTE: use the item's CANONICAL name, not its friendly
                // grocery-list `displayName` ("2 fillets salmon", "1 kg bag
                // rice") — that string embeds a purchase-unit label that
                // `FoodCanonicalizer.canonicalize` has no way to strip back
                // off, so it would land in the pantry under a bogus
                // canonical name and never merge with (or get subtracted
                // against) the real "salmon" / "rice" entries.
                let pantryItem = try pantryService.mergeOrCreate(
                    rawName: confirmation.item.canonicalFoodName,
                    quantity: confirmation.quantity,
                    unit: confirmation.unit,
                    storageLocation: confirmation.storageLocation,
                    purchaseDate: now,
                    purchaseSource: .groceryConfirm,
                    sourceReceiptLineItemID: nil,
                    brand: ""
                )
                if let paid = confirmation.totalPaidUSD, paid > 0 {
                    let entry = PantryPriceEntry(
                        canonicalFoodName: pantryItem.canonicalName,
                        displayName: pantryItem.displayName,
                        purchaseDate: now,
                        totalPaidUSD: paid,
                        quantity: confirmation.quantity,
                        unit: confirmation.unit,
                        source: .groceryConfirm,
                        store: store == .generic ? nil : store.displayName
                    )
                    context.insert(entry)
                }
                boughtItems.append(confirmation.item)
            } catch {
                Logger.nutrition.error("[Diag.Grocery] done-shopping pantry add failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        try? context.save()
        try? groceryService.markBought(boughtItems, boughtAt: now)
        commitGroceryStoreModeSession()
        reloadPantry()
        reloadGrocery()
    }

    // MARK: - Private

    private func loadUserSettingsForGrocery() -> UserSettings? {
        guard let context = pantryModelContext else {
            return nil
        }
        if let existing = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first {
            return existing
        }
        // Defensive fallback — Nutrition is normally only reachable after
        // onboarding creates the single UserSettings row, but grocery Store
        // Mode / picker shouldn't hard-fail if that row is somehow missing.
        let created = UserSettings()
        context.insert(created)
        try? context.save()
        return created
    }
}
