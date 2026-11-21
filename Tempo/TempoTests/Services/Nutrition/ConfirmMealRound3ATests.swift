//
// ConfirmMealRound3ATests.swift
// Tempo
//
// Nutrition round 3, lane A: the Confirm Meal sheet. Meal type follows the
// time, USDA-style names match pantry items, per-item kitchen / out origin
// (mixed meals), and the big-portion hint.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - Meal type follows the time

final class ConfirmMealMealTypeTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
    }

    private func food(_ id: String = "a") -> ParsedFoodItem {
        ParsedFoodItem(id: id, name: "eggs", quantityGrams: 100, calories: 150, proteinG: 12, carbsG: 1, fatG: 10, isVerified: false)
    }

    func testTwoPmDefaultsToLunchNotBreakfast() {
        let draft = MealReviewDraft(items: [food()], now: date(hour: 14))
        XCTAssertEqual(draft.mealType, .lunch)
    }

    func testParsedTimeDecidesTheMealWhenTextNamedNoMeal() {
        // Now is 14:00, the text said "at 8am": breakfast, from the time.
        let draft = MealReviewDraft(items: [food()], hintedDate: date(hour: 8), hintedType: nil, now: date(hour: 14))
        XCTAssertEqual(draft.mealType, .breakfast)
    }

    func testChangingTheTimeMovesTheMeal() {
        var draft = MealReviewDraft(items: [food()], now: date(hour: 14))
        draft.setEatenAt(date(hour: 20))
        XCTAssertEqual(draft.mealType, .dinner)
        draft.setEatenAt(date(hour: 7, minute: 30))
        XCTAssertEqual(draft.mealType, .breakfast)
    }

    func testUsersOwnMealPickSticksWhenTheTimeMoves() {
        var draft = MealReviewDraft(items: [food()], now: date(hour: 14))
        draft.setMealType(.snack)
        draft.setEatenAt(date(hour: 20))
        XCTAssertEqual(draft.mealType, .snack)
        XCTAssertTrue(draft.mealTypeWasPicked)
    }

    func testMealNamedInTheTextSticks() {
        var draft = MealReviewDraft(items: [food()], hintedType: .dinner, now: date(hour: 14))
        XCTAssertEqual(draft.mealType, .dinner)
        draft.setEatenAt(date(hour: 9))
        XCTAssertEqual(draft.mealType, .dinner)
    }

    func testParserMealNameMapping() {
        XCTAssertEqual(MealReviewRequest.mealType(fromHint: "lunch"), .lunch)
        XCTAssertNil(MealReviewRequest.mealType(fromHint: nil))
        XCTAssertNil(MealReviewRequest.mealType(fromHint: "brunch"))
    }
}

// MARK: - Name matching

final class PantryNameMatchingTests: XCTestCase {
    private func same(_ a: String, _ b: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(FoodCanonicalizer.matchKey(a), FoodCanonicalizer.matchKey(b), "\(a) vs \(b)", file: file, line: line)
    }

    private func different(_ a: String, _ b: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(FoodCanonicalizer.matchKey(a), FoodCanonicalizer.matchKey(b), "\(a) vs \(b)", file: file, line: line)
    }

    func testUSDAStyleEggs() {
        same("eggs, large, cooked", "Eggs")
        same("Egg, whole, hard-boiled", "eggs")
        same("Eggs", "egg")
        same("scrambled eggs", "Eggs")
    }

    func testUSDAStyleBread() {
        same("white bread, toasted", "White bread")
        same("bread, white, toasted", "White bread")
        same("Breads, white", "white bread")
        different("whole wheat bread", "white bread")
    }

    func testPluralsBothWays() {
        same("tomatoes", "Tomato")
        same("Tomato", "tomatoes, raw")
        same("blueberries", "blueberry")
        same("Potatoes, baked", "potato")
        same("almonds", "almond")
    }

    func testBrandAndCookingWordsDrop() {
        same("Kirkland chicken breast, grilled", "Chicken breast")
        same("Great Value rice, cooked", "rice")
    }

    func testDifferentFoodsStayDifferent() {
        different("chicken fried rice", "rice")
        different("egg noodles", "eggs")
        different("rice cakes", "rice")
        different("peanut butter", "butter")
    }
}

// MARK: - Pantry preview with realistic names

@MainActor
final class PantryPreviewRealisticNamesTests: XCTestCase {
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
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func stock(_ name: String, quantity: Double, unit: PantryUnit) {
        context.insert(PantryItem(rawName: name, quantity: quantity, unit: unit))
        try? context.save()
    }

    private func food(_ name: String, grams: Double) -> PlannedFood {
        PlannedFood(name: name, quantityGrams: grams, calories: 100, proteinG: 5, carbsG: 10, fatG: 3)
    }

    func testUSDANamedEggsAndBreadMatchPantryRows() {
        stock("Eggs", quantity: 12, unit: .pieces)
        stock("White bread", quantity: 16, unit: .pieces)
        let lines = PantryDecrementService.preview(
            foods: [food("eggs, large, cooked", grams: 100), food("bread, white, toasted", grams: 60)],
            modelContext: context
        )
        XCTAssertEqual(lines.map { $0.displayName.lowercased() }, ["eggs", "white bread"])
    }

    func testDecrementUsesTheSameMatchAndCreditsExactly() throws {
        stock("Eggs", quantity: 12, unit: .pieces)
        let foods = [food("eggs, large, cooked", grams: 100)]
        let results = PantryDecrementService.decrement(foods: foods, label: "t", modelContext: context)
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<PantryItem>()).first)
        XCTAssertEqual(row.quantity, 10, accuracy: 0.001)
        PantryDecrementService.creditExact(details: results.flatMap(\.details), modelContext: context)
        XCTAssertEqual(row.quantity, 12, accuracy: 0.001)
    }

    func testPerFoodPreviewIsAlignedWithTheInput() {
        stock("Eggs", quantity: 12, unit: .pieces)
        let perFood = PantryDecrementService.previewByFood(
            foods: [food("chicken breast", grams: 15), food("eggs, large, cooked", grams: 100), food("unicorn", grams: 50)],
            modelContext: context
        )
        XCTAssertEqual(perFood.count, 3)
        XCTAssertTrue(perFood[0].isEmpty)
        XCTAssertEqual(perFood[1].map(\.displayName), ["Eggs"])
        XCTAssertTrue(perFood[2].isEmpty)
    }

    func testUnrelatedFoodDoesNotMatch() {
        stock("Rice", quantity: 500, unit: .grams)
        XCTAssertTrue(PantryDecrementService.preview(foods: [food("chicken fried rice", grams: 300)], modelContext: context).isEmpty)
    }
}

// MARK: - Per-item origin

final class ConfirmMealOriginDraftTests: XCTestCase {
    private func food(_ id: String, _ name: String = "x", kcal: Double = 200) -> ParsedFoodItem {
        ParsedFoodItem(id: id, name: name, quantityGrams: 100, calories: kcal, proteinG: 5, carbsG: 20, fatG: 5, isVerified: false)
    }

    func testTopChoiceSetsEveryRow() {
        var draft = MealReviewDraft(items: [food("a"), food("b")])
        draft.setOrigin(.out)
        XCTAssertEqual(draft.origin, .out)
        XCTAssertEqual(draft.items.map(\.origin), [.out, .out])
        draft.setOrigin(.kitchen)
        XCTAssertEqual(draft.origin, .kitchen)
        XCTAssertEqual(draft.items.map(\.origin), [.kitchen, .kitchen])
    }

    func testOneRowFromHomeOnAnAteOutMealIsMixed() {
        var draft = MealReviewDraft(items: [food("rice"), food("soy")])
        draft.setOrigin(.out)
        draft.setOrigin(.kitchen, for: "soy")
        XCTAssertEqual(draft.origin, .mixed)
        XCTAssertEqual(draft.origin(for: "rice"), .out)
        XCTAssertEqual(draft.origin(for: "soy"), .kitchen)
        XCTAssertEqual(draft.items.first { $0.id == "soy" }?.origin, .kitchen)
    }

    func testRemovingTheOddRowMakesTheMealUniformAgain() {
        var draft = MealReviewDraft(items: [food("rice"), food("soy")])
        draft.setOrigin(.out)
        draft.setOrigin(.kitchen, for: "soy")
        draft.remove("soy")
        XCTAssertEqual(draft.origin, .out)
    }

    func testTopChoiceAfterMixedOverwritesEveryRow() {
        var draft = MealReviewDraft(items: [food("rice"), food("soy")])
        draft.setOrigin(.out)
        draft.setOrigin(.kitchen, for: "soy")
        draft.setOrigin(.kitchen)
        XCTAssertEqual(draft.origin, .kitchen)
    }

    func testRowToggleSticksAgainstALateLocationFix() {
        var draft = MealReviewDraft(items: [food("a"), food("b")])
        draft.setOrigin(.kitchen, for: "a")
        draft.applySuggestedOrigin(.out)
        XCTAssertEqual(draft.origin(for: "a"), .kitchen)
        XCTAssertFalse(draft.originWasAutoSet)
    }

    func testMixedIsNotAChoiceAndNotRemembered() {
        var draft = MealReviewDraft(items: [food("a")])
        draft.setOrigin(.mixed)
        XCTAssertEqual(draft.origin, .kitchen)
        let defaults = UserDefaults(suiteName: "ConfirmMealOrigin-\(UUID().uuidString)")!
        let store = HomeLocationStore(defaults: defaults)
        store.lastOrigin = .out
        store.lastOrigin = .mixed
        XCTAssertEqual(store.lastOrigin, .out)
    }

    func testCombinedOrigin() {
        XCTAssertNil(MealOrigin.combined([]))
        XCTAssertEqual(MealOrigin.combined([.kitchen, .kitchen]), .kitchen)
        XCTAssertEqual(MealOrigin.combined([.out]), .out)
        XCTAssertEqual(MealOrigin.combined([.out, .kitchen]), .mixed)
    }

    func testMergedOrigin() {
        XCTAssertEqual(EatenMealRecorder.mergedOrigin(existing: nil, new: .out), .out)
        XCTAssertEqual(EatenMealRecorder.mergedOrigin(existing: .kitchen, new: nil), .kitchen)
        XCTAssertEqual(EatenMealRecorder.mergedOrigin(existing: .kitchen, new: .kitchen), .kitchen)
        XCTAssertEqual(EatenMealRecorder.mergedOrigin(existing: .out, new: .kitchen), .mixed)
    }

    func testBigPortionHint() {
        XCTAssertTrue(food("a", kcal: 1300).isBigPortion)
        XCTAssertFalse(food("a", kcal: 800).isBigPortion)
        XCTAssertFalse(food("a", kcal: 1100).isBigPortion)
        // Halving the plate clears the hint.
        XCTAssertFalse(food("a", kcal: 1300).scaled(by: 0.5).isBigPortion)
    }

    func testScalingKeepsOrigin() {
        var item = food("a")
        item.origin = .kitchen
        XCTAssertEqual(item.scaled(by: 2).origin, .kitchen)
    }
}

// MARK: - Mixed meal: recorder, undo, restore

@MainActor
final class ConfirmMealMixedRecorderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        context.insert(PantryItem(rawName: "Chicken breast", quantity: 200, unit: .grams))
        context.insert(PantryItem(rawName: "Eggs", quantity: 12, unit: .pieces))
        try context.save()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func quantity(_ name: String) -> Double? {
        let key = FoodCanonicalizer.matchKey(name)
        return ((try? context.fetch(FetchDescriptor<PantryItem>())) ?? [])
            .first { FoodCanonicalizer.matchKey($0.canonicalName) == key }?.quantity
    }

    private func input(_ name: String, grams: Double, origin: MealOrigin?) -> MealFoodItemInput {
        MealFoodItemInput(
            foodId: UUID().uuidString, name: name, brand: nil, servings: 1, servingSize: grams, servingUnit: "g",
            calories: 300, proteinGrams: 10, carbsGrams: 40, fatGrams: 5, source: .manual, origin: origin
        )
    }

    private func logRiceWithHomeSoy() throws -> EatenMealRecorder.Result {
        try EatenMealRecorder.record(
            [input("chicken fried rice", grams: 400, origin: .out), input("chicken breast", grams: 15, origin: .kitchen)],
            type: .lunch, eatenAt: Date(), source: .manual, origin: .mixed, modelContext: context
        )
    }

    func testOnlyTheKitchenTickedFoodComesOffThePantry() throws {
        let result = try logRiceWithHomeSoy()
        XCTAssertEqual(try XCTUnwrap(quantity("Chicken breast")), 185, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(quantity("Eggs")), 12, accuracy: 0.001)
        XCTAssertEqual(result.meal.origin, .mixed)
        XCTAssertEqual(result.meal.originRaw, "mixed")
        XCTAssertEqual(result.meal.decrementDetail.count, 1)
        XCTAssertEqual(result.meal.foods.map(\.origin), [.out, .kitchen])
        XCTAssertEqual(result.logged.calories, 600, "totals ignore origin")
    }

    func testAteOutMealWithNoTickedFoodTouchesNothing() throws {
        let result = try EatenMealRecorder.record(
            [input("chicken breast", grams: 15, origin: .out)],
            type: .dinner, eatenAt: Date(), source: .manual, origin: .out, modelContext: context
        )
        XCTAssertEqual(try XCTUnwrap(quantity("Chicken breast")), 200, accuracy: 0.001)
        XCTAssertFalse(result.meal.didDecrementPantry)
    }

    func testUndoCreditsExactlyAndRestoreDeductsOnlyTheKitchenPart() throws {
        let result = try logRiceWithHomeSoy()
        let env = MealOutcomeService.Env(modelContext: context)
        let snapshot = try MealOutcomeService.undo(result.meal, env: env)
        XCTAssertEqual(try XCTUnwrap(quantity("Chicken breast")), 200, accuracy: 0.001)

        try MealOutcomeService.restore(snapshot, env: env)
        XCTAssertEqual(try XCTUnwrap(quantity("Chicken breast")), 185, accuracy: 0.001)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first)
        XCTAssertEqual(restored.origin, .mixed)
        XCTAssertEqual(restored.foods.map(\.origin), [.out, .kitchen])
    }

    func testMergingAKitchenFoodIntoAnOutMealMakesItMixed() throws {
        _ = try EatenMealRecorder.record(
            [input("chicken fried rice", grams: 400, origin: .out)],
            type: .lunch, eatenAt: Date(), source: .manual, origin: .out, modelContext: context
        )
        let merged = try EatenMealRecorder.record(
            [input("chicken breast", grams: 15, origin: .kitchen)],
            type: .lunch, eatenAt: Date(), source: .manual, resolution: .add, origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(merged.meal.origin, .mixed)
        XCTAssertEqual(try XCTUnwrap(quantity("Chicken breast")), 185, accuracy: 0.001)
    }

    func testCoachSeesAnyEatenOutItem() throws {
        let result = try logRiceWithHomeSoy()
        XCTAssertTrue(CoachMealSnapshot(meal: result.meal).ateOut)
        let kitchenOnly = try EatenMealRecorder.record(
            [input("Eggs", grams: 100, origin: .kitchen)],
            type: .dinner, eatenAt: Date(), source: .manual, origin: .kitchen, modelContext: context
        )
        XCTAssertFalse(CoachMealSnapshot(meal: kitchenOnly.meal).ateOut)
    }

    func testCommitterToastNamesOnlyKitchenItems() throws {
        let items: [ParsedFoodItem] = {
            var rice = ParsedFoodItem(id: "r", name: "chicken fried rice", quantityGrams: 400, calories: 800, proteinG: 30, carbsG: 100, fatG: 25, isVerified: false)
            rice.origin = .out
            var soy = ParsedFoodItem(id: "s", name: "chicken breast", quantityGrams: 15, calories: 10, proteinG: 1, carbsG: 1, fatG: 0, isVerified: false)
            soy.origin = .kitchen
            return [rice, soy]
        }()
        let outcome = MealReviewCommitter.commit(
            items, type: .lunch, eatenAt: Date(), origin: .mixed, resolution: .add, modelContext: context, notifications: nil
        )
        guard case let .logged(toast) = outcome else {
            return XCTFail("expected logged")
        }
        XCTAssertTrue(toast.message.lowercased().contains("chicken breast"), toast.message)
        XCTAssertFalse(toast.message.lowercased().contains("fried rice"))
    }
}
