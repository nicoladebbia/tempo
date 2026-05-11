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

        if pantryService == nil {
            pantryService = LocalPantryService(modelContext: modelContext)
            services.pantry = pantryService
        }
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
    }

    func addPantryItem(rawName: String, quantity: Double, unit: PantryUnit, storageLocation: PantryStorageLocation) {
        guard let service = pantryService else {
            return
        }
        do {
            try service.mergeOrCreate(
                rawName: rawName,
                quantity: quantity,
                unit: unit,
                storageLocation: storageLocation,
                purchaseDate: Date(),
                purchaseSource: .manual,
                sourceReceiptLineItemID: nil
            )
            reloadPantry()
        } catch {
            pantryState.loadError = error.localizedDescription
        }
    }

    func archivePantryItem(_ item: PantryItem) {
        guard let service = pantryService else {
            return
        }
        try? service.archive(item)
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
    func refreshRecipeSuggestions(limit: Int = 8) {
        guard let recipeService else {
            return
        }
        let pantryNames = Set(pantryState.items.filter { $0.quantity > 0 }.map(\.canonicalName))
        let remainingCal = max(0, todayCalorieTarget - todayCaloriesConsumed)
        let remainingProtein = max(0, todayProteinTarget - todayProteinConsumed)
        let remainingCarbs = max(0, todayCarbsTarget - todayCarbsConsumed)
        let remainingFat = max(0, todayFatTarget - todayFatConsumed)

        let inputs = RecipeSuggestionInputs(
            pantryCanonicalNames: pantryNames,
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
        try? service.toggleChecked(item)
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

    private func phase7APIClient(from _: ServiceContainer) -> APIClient? {
        // ServiceContainer doesn't expose APIClient directly; LiveReceiptService
        // is constructed lazily by views that have access to one via @Environment.
        // We return nil here — receipts run through MockReceiptService until a
        // view wires the live path. The Mock writes to SwiftData identically.
        nil
    }
}

// MARK: - Storage hooks on the base class

extension NutritionTabViewModel {
    /// Backing store for the four Phase 7 state objects. Stored as associated
    /// objects via Storage keyed by ObjectIdentifier so the base class file
    /// stays untouched.
    private enum Phase7Storage {
        @MainActor
        static var pantryState: [ObjectIdentifier: NutritionPantryState] = [:]
        @MainActor
        static var receiptState: [ObjectIdentifier: NutritionReceiptState] = [:]
        @MainActor
        static var recipeState: [ObjectIdentifier: NutritionRecipeState] = [:]
        @MainActor
        static var groceryState: [ObjectIdentifier: NutritionGroceryState] = [:]
        @MainActor
        static var pantryService: [ObjectIdentifier: any PantryServiceProtocol] = [:]
        @MainActor
        static var receiptService: [ObjectIdentifier: any ReceiptServiceProtocol] = [:]
        @MainActor
        static var recipeService: [ObjectIdentifier: any RecipeServiceProtocol] = [:]
        @MainActor
        static var groceryService: [ObjectIdentifier: any GroceryListServiceProtocol] = [:]
        @MainActor
        static var intelligence: [ObjectIdentifier: NutritionIntelligenceService] = [:]
    }

    var pantryState: NutritionPantryState {
        let key = ObjectIdentifier(self)
        if let existing = Phase7Storage.pantryState[key] {
            return existing
        }
        let new = NutritionPantryState()
        Phase7Storage.pantryState[key] = new
        return new
    }

    var receiptState: NutritionReceiptState {
        let key = ObjectIdentifier(self)
        if let existing = Phase7Storage.receiptState[key] {
            return existing
        }
        let new = NutritionReceiptState()
        Phase7Storage.receiptState[key] = new
        return new
    }

    var recipeState: NutritionRecipeState {
        let key = ObjectIdentifier(self)
        if let existing = Phase7Storage.recipeState[key] {
            return existing
        }
        let new = NutritionRecipeState()
        Phase7Storage.recipeState[key] = new
        return new
    }

    var groceryState: NutritionGroceryState {
        let key = ObjectIdentifier(self)
        if let existing = Phase7Storage.groceryState[key] {
            return existing
        }
        let new = NutritionGroceryState()
        Phase7Storage.groceryState[key] = new
        return new
    }

    var pantryService: (any PantryServiceProtocol)? {
        get { Phase7Storage.pantryService[ObjectIdentifier(self)] }
        set { Phase7Storage.pantryService[ObjectIdentifier(self)] = newValue }
    }

    var receiptService: (any ReceiptServiceProtocol)? {
        get { Phase7Storage.receiptService[ObjectIdentifier(self)] }
        set { Phase7Storage.receiptService[ObjectIdentifier(self)] = newValue }
    }

    var recipeService: (any RecipeServiceProtocol)? {
        get { Phase7Storage.recipeService[ObjectIdentifier(self)] }
        set { Phase7Storage.recipeService[ObjectIdentifier(self)] = newValue }
    }

    var groceryService: (any GroceryListServiceProtocol)? {
        get { Phase7Storage.groceryService[ObjectIdentifier(self)] }
        set { Phase7Storage.groceryService[ObjectIdentifier(self)] = newValue }
    }

    var intelligence: NutritionIntelligenceService? {
        get { Phase7Storage.intelligence[ObjectIdentifier(self)] }
        set { Phase7Storage.intelligence[ObjectIdentifier(self)] = newValue }
    }
}
