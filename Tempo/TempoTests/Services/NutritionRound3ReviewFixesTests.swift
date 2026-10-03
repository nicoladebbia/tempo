//
// NutritionRound3ReviewFixesTests.swift
// Tempo
//
// Review fixes on the Round 3 branch: Fuel setup never invents body stats,
// staple filters singularize both sides, rename confidence, meal-time words,
// product re-save keeps identity, and an Undo-of-Undo re-deducts only what
// the log had really taken from the pantry.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class NutritionRound3ReviewFixesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        context.insert(UserSettings())
        try context.save()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private var profiles: [DietaryProfile] {
        (try? context.fetch(FetchDescriptor<DietaryProfile>())) ?? []
    }

    // MARK: - 1. No made-up body stats

    func testFoodOnlySaveWithoutBodyAndGoalCreatesNoProfile() {
        var draft = FuelSetupDraft()
        draft.allergies = ["Peanuts"]
        let stored = draft.save(sections: [.food], to: context)
        XCTAssertTrue(profiles.isEmpty)
        XCTAssertFalse(stored.contains(.food), "food stays in the draft until a profile can exist")
    }

    func testFullSaveWithMissingBodyKeepsProfileSectionsUnstored() {
        var draft = FuelSetupDraft()
        draft.allergies = ["Peanuts"]
        draft.weeklyBudgetUSD = 80
        let stored = draft.save(to: context)
        XCTAssertTrue(profiles.isEmpty)
        XCTAssertTrue(stored.contains(.shopping))
        XCTAssertFalse(stored.contains(.food))
        XCTAssertFalse(draft.isComplete, "plan generation still asks for the missing sections")
    }

    func testProfileIsCreatedFromRealAnswersWhenBodyAndGoalArePresent() throws {
        var draft = FuelSetupDraft()
        draft.weightKg = 90
        draft.heightCm = 190
        draft.age = 31
        draft.sex = .female
        draft.goal = .maintain
        draft.allergies = ["Peanuts"]
        let stored = draft.save(sections: [.food], to: context)
        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.currentWeightKg, 90)
        XCTAssertEqual(profile.age, 31)
        XCTAssertEqual(profile.allergies, ["Peanuts"])
        XCTAssertTrue(stored.isSuperset(of: [.you, .goal, .food]))
    }

    // MARK: - 3. Health never overwrites typed values

    func testHealthSkipsFieldsTheUserAlreadyEdited() {
        let saved = FuelSetupDraft()
        var draft = saved
        draft.weightKg = 70 // typed while Health was loading
        let locked = draft.apply(
            health: HealthBodyStats(weightKg: 82.4, heightCm: 181, age: 24),
            untouchedSince: saved
        )
        XCTAssertEqual(draft.weightKg, 70)
        XCTAssertEqual(draft.heightCm, 181)
        XCTAssertFalse(locked.contains(.weight))
        XCTAssertTrue(locked.contains(.height))
    }

    // MARK: - 4. Staple filter

    func testPluralAllergyHidesSingularStaples() {
        let filter = StapleDietFilter(avoidTerms: ["Tomatoes", "peppers"])
        let names = PantryStaple.suggestions(for: filter).map(\.canonicalName)
        XCTAssertFalse(names.contains("ketchup"))
        XCTAssertFalse(names.contains("black pepper"))
        XCTAssertFalse(names.contains("hot sauce"))
        XCTAssertTrue(names.contains("salt"))
    }

    func testDietFlagsHideMatchingStaples() {
        XCTAssertFalse(PantryStaple.suggestions(for: StapleDietFilter(halal: true)).map(\.canonicalName).contains("vanilla extract"))
        let lactose = PantryStaple.suggestions(for: StapleDietFilter(lactoseFree: true)).map(\.canonicalName)
        XCTAssertTrue(lactose.contains("salt"))
        XCTAssertTrue(StapleDietFilter(nutFree: true).allows((canonicalName: "peanut butter", displayName: "Peanut butter")) == false)
        XCTAssertFalse(StapleDietFilter(shellfishAllergy: true).allows((canonicalName: "oyster sauce", displayName: "Oyster sauce")))
    }

    func testSingularForms() {
        XCTAssertEqual(PantryStorageGuesser.singular("tomatoes"), "tomato")
        XCTAssertEqual(PantryStorageGuesser.singular("berries"), "berry")
        XCTAssertEqual(PantryStorageGuesser.singular("peppers"), "pepper")
        XCTAssertEqual(PantryStorageGuesser.singular("hummus"), "hummus")
        XCTAssertTrue(PantryStorageGuesser.containsKeyword("tomatoes", in: "tomato"))
    }

    // MARK: - 5. Receipt use-by override on a merged row

    func testUseByOverrideOnMergedRowNeverLengthensShelfLife() throws {
        let service = LiveReceiptService(modelContext: context, apiClient: APIClient())
        let pantry = LocalPantryService(modelContext: context)
        let soon = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let existing = try pantry.mergeOrCreate(
            rawName: "Chicken", quantity: 500, unit: .grams, storageLocation: .fridge,
            purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil, brand: ""
        )
        existing.useBy = soon
        let receipt = Receipt(store: "Aldi", purchaseDate: Date(), totalAmount: 5)
        context.insert(receipt)
        let line = ReceiptLineItem(
            receipt: receipt, rawText: "CHICKEN", canonicalFoodName: "chicken", displayName: "Chicken",
            quantity: 300, unit: .grams, totalPrice: 5, userConfirmed: true
        )
        context.insert(line)
        let later = Calendar.current.date(byAdding: .day, value: 20, to: Date())!
        try service.ingestConfirmedLines(
            of: receipt, into: pantry,
            overrides: [line.id: ReceiptIngestOverride(storage: .freezer, useBy: later)]
        )
        let useBy = try XCTUnwrap(existing.useBy)
        XCTAssertLessThanOrEqual(useBy, soon.addingTimeInterval(1))
        XCTAssertEqual(existing.storageLocation, .fridge)
    }

    // MARK: - 9. Rename confidence

    func testRenameToUnknownFoodStaysBelowQuestionThreshold() {
        let item = AnalyzedFoodItem(
            id: UUID(), name: "Mystery meat", estimatedPortion: "150g", calories: 300,
            protein: 30, carbs: 0, fat: 10, score: 0.95, servingMultiplier: 1
        ).renamed(to: "zzqx special")
        XCTAssertFalse(item.isVerified)
        XCTAssertTrue(item.needsQuestion)
    }

    // MARK: - 10. Meal words

    func testMealWordAfterForWinsOverDishName() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 21))!
        XCTAssertEqual(MealTimeHints.parse("breakfast burrito for dinner", now: now).mealType, .dinner)
        XCTAssertEqual(MealTimeHints.parse("had cereal as a snack", now: now).mealType, .snack)
        XCTAssertEqual(MealTimeHints.parse("breakfast burrito", now: now).mealType, .breakfast)
    }

    func testMidnightMeansTodaysMidnightNotTheFuture() throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 15))!
        let date = try XCTUnwrap(MealTimeHints.parse("pizza at 12am", now: now).date)
        XCTAssertEqual(Calendar.current.component(.hour, from: date), 0)
        XCTAssertLessThan(date, now)
    }

    // MARK: - 11. Product re-save keeps identity

    func testUserEditedReSaveKeepsIdSourceAndImage() {
        var base = FoodProduct(
            id: "5000000000001", barcode: "5000000000001", name: "Oat bar", source: .openFoodFacts,
            per100g: .init(kcal: 400, protein: 8, carbs: 60, fat: 12)
        )
        base.imageURL = URL(string: "https://example.com/a.jpg")
        let edited = FoodProduct.userEdited(
            from: base, barcode: nil, name: "Oat bar XL", brand: "",
            servingGrams: 40, isBeverage: false, per100g: base.per100g, allergens: [], ingredients: ""
        )
        XCTAssertEqual(edited.id, base.id)
        XCTAssertEqual(edited.barcode, "5000000000001")
        XCTAssertEqual(edited.source, .openFoodFacts)
        XCTAssertEqual(edited.imageURL, base.imageURL)
        XCTAssertEqual(edited.name, "Oat bar XL")
        XCTAssertEqual(edited.servingLabel, "40 g")
    }

    // MARK: - 12. Undo of undo re-deducts only what was deducted

    func testRestoringMixedLogDoesNotDeductTheAteOutPart() throws {
        let rice = PantryItem(rawName: "Rice", quantity: 1000, unit: .grams)
        let chicken = PantryItem(rawName: "Chicken", quantity: 1000, unit: .grams)
        context.insert(rice)
        context.insert(chicken)
        try context.save()
        let eatenAt = Date()
        func input(_ name: String) -> MealFoodItemInput {
            MealFoodItemInput(
                foodId: name, name: name, brand: nil, servings: 1, servingSize: 200, servingUnit: "g",
                calories: 300, proteinGrams: 20, carbsGrams: 30, fatGrams: 5, source: .manual
            )
        }
        // Ate out first (no pantry), then added a kitchen food to the same log.
        _ = try EatenMealRecorder.record([input("Rice")], type: .lunch, eatenAt: eatenAt, source: .manual, modelContext: context)
        let result = try EatenMealRecorder.record(
            [input("Chicken")], type: .lunch, eatenAt: eatenAt, source: .manual, origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(rice.quantity, 1000)
        let afterEat = chicken.quantity
        XCTAssertLessThan(afterEat, 1000)

        let env = MealOutcomeService.Env(modelContext: context)
        let snapshot = try MealOutcomeService.undo(result.meal, env: env)
        XCTAssertEqual(chicken.quantity, 1000, accuracy: 0.01)
        try MealOutcomeService.restore(snapshot, env: env)
        XCTAssertEqual(rice.quantity, 1000, "the ate-out food is never deducted")
        XCTAssertEqual(chicken.quantity, afterEat, accuracy: 0.01)
    }
}
