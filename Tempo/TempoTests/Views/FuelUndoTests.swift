//
// FuelUndoTests.swift
// Tempo
//
// Undo for the Fuel logs and deletes added in the guidance pass. Each test does the action, then
// what the Undo toast does, and checks the data is back exactly. Also pins that every explainer
// is complete and that the tick/pantry/list Undo paths are idempotent.
//

import Combine
import SwiftData
@testable import Tempo
import XCTest

// MARK: - FuelUndoTests

@MainActor
final class FuelUndoTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        toastWatch = nil
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: Helpers

    private func food(_ name: String, kcal: Double) -> MealFoodItemInput {
        MealFoodItemInput(
            foodId: UUID().uuidString, name: name, brand: nil, servings: 1,
            servingSize: 100, servingUnit: "g", calories: kcal,
            proteinGrams: 10, carbsGrams: 20, fatGrams: 5, source: .manual
        )
    }

    private var env: MealOutcomeService.Env {
        MealOutcomeService.Env(modelContext: context, notifications: nil)
    }

    // MARK: Remove one food from a log

    func testRemovingOneFoodIsUndoneAtTheSamePlaceWithItsTotalsAndLogLine() throws {
        let result = try EatenMealRecorder.record(
            [food("Chicken", kcal: 300), food("Rice", kcal: 200), food("Broccoli", kcal: 50)],
            type: .lunch, eatenAt: Date(), source: .manual, modelContext: context
        )
        let meal = result.meal
        let namesBefore = meal.foods.map(\.name)
        let removed = meal.foods[1]
        XCTAssertEqual(meal.totalCalories, 550)

        try MealOutcomeService.removeFood(at: 1, from: meal, env: env)
        XCTAssertEqual(meal.foods.map(\.name), ["Chicken", "Broccoli"])
        XCTAssertEqual(meal.totalCalories, 350)

        try MealOutcomeService.restoreFood(removed, at: 1, to: meal, env: env)
        XCTAssertEqual(meal.foods.map(\.name), namesBefore)
        XCTAssertEqual(meal.totalCalories, 550)
        XCTAssertEqual(meal.foods[1].quantityGrams, removed.quantityGrams)

        let logID = try XCTUnwrap(meal.linkedMealLogID)
        let log = try XCTUnwrap(context.fetch(FetchDescriptor<MealLog>(predicate: #Predicate { $0.id == logID })).first)
        XCTAssertEqual(Set(log.items.map(\.name)), ["Chicken", "Rice", "Broccoli"])
        XCTAssertEqual(log.totalCalories, 550)
    }

    func testRestoringAFoodPastTheEndAppendsInsteadOfCrashing() throws {
        let result = try EatenMealRecorder.record(
            [food("Chicken", kcal: 300), food("Rice", kcal: 200)],
            type: .lunch, eatenAt: Date(), source: .manual, modelContext: context
        )
        let extra = PlannedFood(name: "Soup", quantityGrams: 100, calories: 80, proteinG: 3, carbsG: 10, fatG: 2)
        try MealOutcomeService.restoreFood(extra, at: 9, to: result.meal, env: env)
        XCTAssertEqual(result.meal.foods.last?.name, "Soup")
        XCTAssertEqual(result.meal.foods.count, 3)
    }

    // MARK: Saved meals

    func testDeletedSavedMealComesBackWithItsStarFoodsAndUseCount() throws {
        let preset = MealPreset(
            name: "Usual breakfast", foodItems: [food("Oats", kcal: 150)],
            totalCalories: 150, totalProtein: 10, totalCarbs: 20, totalFat: 5,
            mealType: .breakfast, useCount: 7, lastUsedAt: Date(timeIntervalSince1970: 1000), isPinned: true
        )
        context.insert(preset)
        try context.save()
        let id = preset.id
        let snapshot = MealPresetSnapshot(preset)

        try MealOutcomeService.deletePreset(preset, modelContext: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealPreset>()), 0)

        XCTAssertTrue(snapshot.restore(in: context))
        let back = try XCTUnwrap(context.fetch(FetchDescriptor<MealPreset>()).first)
        XCTAssertEqual(back.id, id)
        XCTAssertEqual(back.name, "Usual breakfast")
        XCTAssertTrue(back.isPinned)
        XCTAssertEqual(back.useCount, 7)
        XCTAssertEqual(back.totalCalories, 150)
        XCTAssertEqual(back.mealType, .breakfast)
        XCTAssertEqual(back.foodItems.map(\.name), ["Oats"])

        XCTAssertTrue(snapshot.restore(in: context), "a second tap on Undo is harmless")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealPreset>()), 1)
    }

    // MARK: Food check history

    func testRemovedFoodCheckRowComesBackWithStarPhotoAndPortion() throws {
        let product = FoodProduct(
            id: "5000000000009", barcode: "5000000000009", name: "Oat Bar", brand: "Acme", source: .openFoodFacts,
            quantityLabel: "40 g", per100g: FoodProduct.Nutrients(kcal: 400), nutriScoreGrade: "b"
        )
        let row = ScannedFood(product: product, isUserAdded: true, photoData: Data([1, 2, 3]))
        row.isFavorite = true
        row.viewCount = 4
        row.lastLoggedGrams = 45
        context.insert(row)
        try context.save()
        let snapshot = ScannedFoodSnapshot(row)

        context.delete(row)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScannedFood>()), 0)

        XCTAssertTrue(snapshot.restore(in: context))
        let back = try XCTUnwrap(context.fetch(FetchDescriptor<ScannedFood>()).first)
        XCTAssertEqual(back.productID, "5000000000009")
        XCTAssertTrue(back.isFavorite)
        XCTAssertTrue(back.isUserAdded)
        XCTAssertEqual(back.viewCount, 4)
        XCTAssertEqual(back.lastLoggedGrams, 45)
        XCTAssertEqual(back.photoData, Data([1, 2, 3]))
        XCTAssertEqual(back.product?.name, "Oat Bar")
    }

    // MARK: Staples

    func testRemovedStapleComesBackWithItsStatus() throws {
        let staple = PantryStaple(canonicalName: "olive oil", displayName: "Olive oil", status: .runningLow)
        context.insert(staple)
        try context.save()
        let snapshot = PantryStapleSnapshot(staple)

        try LocalStapleService(modelContext: context).delete(staple)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PantryStaple>()), 0)

        XCTAssertTrue(snapshot.restore(in: context))
        let back = try XCTUnwrap(context.fetch(FetchDescriptor<PantryStaple>()).first)
        XCTAssertEqual(back.id, staple.id)
        XCTAssertEqual(back.status, .runningLow)
        XCTAssertEqual(back.displayName, "Olive oil")
    }

    // MARK: Pantry adds

    func testAddingANewPantryRowIsUndoneByArchivingIt() throws {
        let service = LocalPantryService(modelContext: context)
        let before = try KitchenUndo.pantryStates(of: service.fetchAll())

        let item = try service.mergeOrCreate(
            rawName: "rice", quantity: 2, unit: .packs, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        let undo = try KitchenUndo.pantryUndoStates(before: before, after: service.fetchAll())
        XCTAssertEqual(undo.map(\.id), [item.id])

        KitchenUndo.restorePantry(undo, in: context)
        XCTAssertTrue(item.isArchived)
        XCTAssertTrue(try service.fetchAll().isEmpty)
    }

    func testAddingToAnExistingPantryRowIsUndoneByPuttingTheQuantityBack() throws {
        let service = LocalPantryService(modelContext: context)
        let existing = try service.mergeOrCreate(
            rawName: "rice", quantity: 2, unit: .packs, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        let before = try KitchenUndo.pantryStates(of: service.fetchAll())

        try service.mergeOrCreate(
            rawName: "rice", quantity: 1, unit: .packs, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        XCTAssertEqual(existing.quantity, 3)
        let undo = try KitchenUndo.pantryUndoStates(before: before, after: service.fetchAll())
        XCTAssertEqual(undo.count, 1)

        KitchenUndo.restorePantry(undo, in: context)
        XCTAssertEqual(existing.quantity, 2)
        XCTAssertFalse(existing.isArchived)
    }

    func testRowsThatDidNotChangeAreNotPartOfThePantryUndo() throws {
        let service = LocalPantryService(modelContext: context)
        try service.mergeOrCreate(
            rawName: "oats", quantity: 1, unit: .packs, storageLocation: .pantry,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
        let before = try KitchenUndo.pantryStates(of: service.fetchAll())
        XCTAssertTrue(try KitchenUndo.pantryUndoStates(before: before, after: service.fetchAll()).isEmpty)
    }

    func testUndoingAPantryAddTakesItsPriceOutOfHistory() throws {
        let started = Date().addingTimeInterval(-1)
        let mine = UUID()
        let other = UUID()
        context.insert(PantryPriceEntry(
            canonicalFoodName: "rice", displayName: "Rice", purchaseDate: Date(),
            totalPaidUSD: 4, quantity: 1, unit: .packs, source: .manual, sourcePantryItemID: mine
        ))
        context.insert(PantryPriceEntry(
            canonicalFoodName: "oats", displayName: "Oats", purchaseDate: Date(),
            totalPaidUSD: 3, quantity: 1, unit: .packs, source: .manual, sourcePantryItemID: other
        ))
        context.insert(PantryPriceEntry(
            canonicalFoodName: "rice", displayName: "Rice", purchaseDate: started.addingTimeInterval(-86400),
            totalPaidUSD: 5, quantity: 1, unit: .packs, source: .manual, sourcePantryItemID: mine
        ))
        try context.save()

        XCTAssertEqual(KitchenUndo.removePriceEntries(ofItems: [mine], since: started, in: context), 1)
        let left = try context.fetch(FetchDescriptor<PantryPriceEntry>())
        XCTAssertEqual(left.count, 2, "another item's price and an older price stay")
        XCTAssertTrue(left.contains { $0.sourcePantryItemID == other })
    }

    // MARK: Grocery ticks

    func testTickingAGroceryRowIsUndoneAndUndoingTwiceChangesNothing() throws {
        let item = GroceryListItem(canonicalFoodName: "milk", displayName: "Milk", quantity: 1, unit: .packs, category: "dairy")
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        item.list = list
        context.insert(item)
        try context.save()

        item.isChecked = true
        XCTAssertTrue(KitchenUndo.setGroceryChecked(id: item.id, to: false, in: context))
        XCTAssertFalse(item.isChecked)
        XCTAssertTrue(KitchenUndo.setGroceryChecked(id: item.id, to: false, in: context))
        XCTAssertFalse(item.isChecked)

        // Un-ticking is undone the same way.
        XCTAssertTrue(KitchenUndo.setGroceryChecked(id: item.id, to: true, in: context))
        XCTAssertTrue(item.isChecked)
        XCTAssertFalse(KitchenUndo.setGroceryChecked(id: UUID(), to: true, in: context), "a row that is gone says so")
    }

    func testAnAddedGroceryRowIsTakenOffAgain() throws {
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        try context.save()
        let service = LocalGroceryListService(modelContext: context)
        let added = try service.addItem(name: "Bananas", quantity: 6, unit: .pieces, category: "pantry")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GroceryListItem>()), 1)

        XCTAssertTrue(FoodProductActions.removeFromList(itemID: added.id, modelContext: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GroceryListItem>()), 0)
        XCTAssertFalse(FoodProductActions.removeFromList(itemID: added.id, modelContext: context))
    }

    // MARK: Supplements

    private var toastsPosted: [ToastData] = []
    private var toastWatch: AnyCancellable?

    /// Collects the toasts Fuel posts (the Undo toast comes this way).
    private func captureToasts() {
        toastsPosted = []
        toastWatch = NotificationCenter.default.publisher(for: .tempoMealLogToast).sink { [weak self] note in
            if let toast = FuelLogToast.toast(from: note) {
                self?.toastsPosted.append(toast)
            }
        }
    }

    func testTickingASupplementIsUndoneWithItsStock() throws {
        let supplement = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30)
        context.insert(supplement)
        try context.save()
        captureToasts()

        let taken = KitchenUndo.toggleSupplementTaken(supplementID: supplement.id, name: "Creatine", in: context)
        XCTAssertTrue(taken)
        XCTAssertEqual(supplement.servingsRemaining, 29)
        XCTAssertTrue(SupplementIntakeStore.takenIDs(on: Date(), in: context).contains(supplement.id))

        let toast = try XCTUnwrap(toastsPosted.last)
        XCTAssertEqual(toast.actionTitle, "Undo")
        toast.action?()
        XCTAssertEqual(supplement.servingsRemaining, 30)
        XCTAssertFalse(SupplementIntakeStore.takenIDs(on: Date(), in: context).contains(supplement.id))

        // A second tap on the same Undo (or a change made elsewhere) must not tick it back on.
        toast.action?()
        XCTAssertEqual(supplement.servingsRemaining, 30)
        XCTAssertFalse(SupplementIntakeStore.takenIDs(on: Date(), in: context).contains(supplement.id))
    }

    func testUntickingASupplementIsUndoneToTakenAgain() throws {
        let supplement = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30)
        context.insert(supplement)
        try context.save()
        SupplementIntakeStore.toggle(supplementID: supplement.id, name: "Creatine", in: context)
        XCTAssertEqual(supplement.servingsRemaining, 29)
        captureToasts()

        XCTAssertFalse(KitchenUndo.toggleSupplementTaken(supplementID: supplement.id, name: "Creatine", in: context))
        XCTAssertEqual(supplement.servingsRemaining, 30)

        try XCTUnwrap(toastsPosted.last).action?()
        XCTAssertEqual(supplement.servingsRemaining, 29)
        XCTAssertTrue(SupplementIntakeStore.takenIDs(on: Date(), in: context).contains(supplement.id))
    }

    // MARK: Explainers

    func testEveryFuelExplainerIsCompleteAndHasAUniqueId() {
        let all = Explainer.allFuel
        XCTAssertGreaterThanOrEqual(all.count, 25)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "ids must be unique")
        for explainer in all {
            XCTAssertTrue(explainer.id.hasPrefix("fuel-"), explainer.id)
            XCTAssertFalse(String(localized: explainer.title).isEmpty, explainer.id)
            XCTAssertFalse(String(localized: explainer.what).isEmpty, explainer.id)
            XCTAssertFalse(String(localized: explainer.how).isEmpty, explainer.id)
            XCTAssertFalse(String(localized: explainer.action).isEmpty, explainer.id)
        }
    }

    // MARK: Fuel setup goal

    func testEveryOnboardingGoalMapsToAFoodGoal() {
        XCTAssertEqual(DietaryGoal(primary: .buildMuscle), .leanGain)
        XCTAssertEqual(DietaryGoal(primary: .loseFat), .cut)
        XCTAssertEqual(DietaryGoal(primary: .performance), .maintain)
        XCTAssertEqual(DietaryGoal(primary: .stayHealthy), .maintain)
        XCTAssertEqual(DietaryGoal(primary: .allAround), .maintain)
    }

    func testFirstFuelSetupStartsTheGoalFromOnboarding() throws {
        let settings = UserSettings()
        settings.primaryGoal = .loseFat
        context.insert(settings)
        try context.save()
        XCTAssertEqual(FuelSetupDraft.load(from: context).goal, .cut)
    }

    func testFirstFuelSetupWithoutAnOnboardingGoalStaysBlank() throws {
        context.insert(UserSettings())
        try context.save()
        XCTAssertNil(FuelSetupDraft.load(from: context).goal)
    }
}

// MARK: - FoodCatalogForTests
