//
// NutritionTabViewModelPhase7Tests.swift
// Tempo
//
// Covers the Phase 7 ViewModel extension: pantry/recipe/grocery state loads,
// refresh, and the merge-into-pantry path through the receipt service.
// Uses MockPantryService + MockReceiptService + MockGroceryListService —
// no SwiftData, no network.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class NutritionTabViewModelPhase7Tests: XCTestCase {
    private var viewModel: NutritionTabViewModel!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PantryItem.self, Receipt.self, ReceiptLineItem.self,
            Recipe.self, RecipeIngredient.self, RecipeStep.self,
            GroceryList.self, GroceryListItem.self,
            PlannedMeal.self, WeeklyMealPlan.self,
            configurations: config
        )
        viewModel = NutritionTabViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Pantry state

    func testReloadPantry_emptyByDefault() {
        let pantry = MockPantryService()
        viewModel.pantryService = pantry
        viewModel.reloadPantry()
        XCTAssertEqual(viewModel.pantryState.items.count, 0)
    }

    func testReloadPantry_surfacesItems() throws {
        let pantry = MockPantryService()
        viewModel.pantryService = pantry
        try pantry.add(PantryItem(
            canonicalName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams,
            storageLocation: .fridge
        ))
        viewModel.reloadPantry()
        XCTAssertEqual(viewModel.pantryState.items.count, 1)
        XCTAssertEqual(viewModel.pantryState.items.first?.canonicalName, "chicken breast")
    }

    func testAddPantryItem_canonicalizesAndPersists() {
        let pantry = MockPantryService()
        viewModel.pantryService = pantry
        viewModel.addPantryItem(
            rawName: "Frozen Blueberries",
            quantity: 300,
            unit: .grams,
            storageLocation: .freezer
        )
        XCTAssertEqual(viewModel.pantryState.items.count, 1)
        XCTAssertEqual(viewModel.pantryState.items.first?.canonicalName, "berries")
    }

    func testReloadPantry_flagsExpiringSoon() throws {
        let pantry = MockPantryService()
        viewModel.pantryService = pantry
        let item = PantryItem(
            canonicalName: "milk",
            displayName: "Milk",
            quantity: 1,
            unit: .liters,
            useBy: Date().addingTimeInterval(2 * 86_400)
        )
        try pantry.add(item)
        viewModel.reloadPantry()
        XCTAssertEqual(viewModel.pantryState.expiringSoon.count, 1)
    }

    // MARK: - Recipe state

    func testReloadRecipes_emptyByDefault() {
        let svc = MockRecipeService()
        viewModel.recipeService = svc
        viewModel.reloadRecipes()
        XCTAssertEqual(viewModel.recipeState.allRecipes.count, 0)
    }

    func testRefreshSuggestions_rankedByPantryCoverage() throws {
        let svc = MockRecipeService()
        let chicken = Recipe(name: "Chicken Bowl")
        chicken.ingredients = [
            RecipeIngredient(recipe: chicken, orderIndex: 0, canonicalFoodName: "chicken breast", displayName: "Chicken Breast", quantityGrams: 200),
            RecipeIngredient(recipe: chicken, orderIndex: 1, canonicalFoodName: "rice", displayName: "Rice", quantityGrams: 100),
        ]
        let salmon = Recipe(name: "Salmon Plate")
        salmon.ingredients = [
            RecipeIngredient(recipe: salmon, orderIndex: 0, canonicalFoodName: "salmon", displayName: "Salmon", quantityGrams: 200),
            RecipeIngredient(recipe: salmon, orderIndex: 1, canonicalFoodName: "avocado", displayName: "Avocado", quantityGrams: 80),
        ]
        try svc.add(chicken)
        try svc.add(salmon)
        viewModel.recipeService = svc

        // Seed pantry directly into ViewModel state (no service round-trip needed).
        viewModel.pantryState.items = [
            PantryItem(canonicalName: "chicken breast", displayName: "Chicken Breast", quantity: 400, unit: .grams),
            PantryItem(canonicalName: "rice", displayName: "Rice", quantity: 500, unit: .grams),
        ]
        viewModel.refreshRecipeSuggestions(limit: 5)
        XCTAssertEqual(viewModel.recipeState.suggestions.first?.recipeName, "Chicken Bowl")
    }

    // MARK: - Grocery state

    func testReloadGrocery_emptyByDefault() {
        let svc = MockGroceryListService()
        viewModel.groceryService = svc
        viewModel.reloadGrocery()
        XCTAssertNil(viewModel.groceryState.latest)
    }

    func testGenerateGroceryList_withoutPlan_failsCleanly() {
        let pantry = MockPantryService()
        let svc = MockGroceryListService()
        viewModel.pantryService = pantry
        viewModel.groceryService = svc
        viewModel.generateGroceryList()
        XCTAssertNotNil(viewModel.groceryState.lastError)
    }

    func testToggleGroceryItem_flips() throws {
        let svc = MockGroceryListService()
        viewModel.groceryService = svc
        let list = GroceryList(weekStartDate: Date())
        let item = GroceryListItem(
            list: list,
            canonicalFoodName: "chicken breast",
            displayName: "Chicken Breast",
            quantity: 400,
            unit: .grams
        )
        list.items = [item]
        viewModel.groceryState.latest = list

        XCTAssertFalse(item.isChecked)
        viewModel.toggleGroceryItem(item)
        XCTAssertTrue(item.isChecked)
    }
}
