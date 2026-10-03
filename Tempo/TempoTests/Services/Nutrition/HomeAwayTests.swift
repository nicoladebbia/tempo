//
// HomeAwayTests.swift
// Tempo
//
// Home / away: the pure decider, the review draft's origin, the recorder's
// pantry deduction (kitchen vs out), exact undo / restore, the dry-run
// preview, and the device-only home store.
//

import CoreLocation
import SwiftData
@testable import Tempo
import XCTest

// MARK: - Decider

final class HomeAwayDeciderTests: XCTestCase {
    private let home = HomeLocation(latitude: 25.7617, longitude: -80.1918, label: nil, setAt: Date())

    private func fix(metresNorth: Double, accuracy: Double = 20) -> CLLocation {
        // 1 degree of latitude is about 111,195 m.
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: home.latitude + metresNorth / 111_195, longitude: home.longitude),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 0, timestamp: Date()
        )
    }

    func testInsideRadiusIsHome() {
        XCTAssertEqual(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 40), home: home), true)
    }

    func testFarAwayIsAway() {
        XCTAssertEqual(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 2000), home: home), false)
    }

    func testNoFixOrNoHomeIsUnknown() {
        XCTAssertNil(HomeAwayDecider.isAtHome(fix: nil, home: home))
        XCTAssertNil(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 10), home: nil))
    }

    func testPoorAccuracyIsUnknown() {
        XCTAssertNil(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 10, accuracy: 800), home: home))
        XCTAssertNil(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 10, accuracy: -1), home: home))
    }

    func testAccuracyWidensTheRadiusUpToTheCap() {
        // 200 m out: outside 150 m with a sharp fix, inside with a 100 m-wide one.
        XCTAssertEqual(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 200, accuracy: 10), home: home), false)
        XCTAssertEqual(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 200, accuracy: 100), home: home), true)
        // The allowance is capped at 100 m: 300 m out stays away even at 400 m accuracy.
        XCTAssertEqual(HomeAwayDecider.isAtHome(fix: fix(metresNorth: 300, accuracy: 400), home: home), false)
    }

    func testDefaultOrigin() {
        XCTAssertEqual(HomeAwayDecider.defaultOrigin(atHome: true, remembered: .out), .kitchen)
        XCTAssertEqual(HomeAwayDecider.defaultOrigin(atHome: false, remembered: .kitchen), .out)
        XCTAssertEqual(HomeAwayDecider.defaultOrigin(atHome: nil, remembered: .out), .out)
        XCTAssertEqual(HomeAwayDecider.defaultOrigin(atHome: nil, remembered: nil), .kitchen)
    }
}

// MARK: - Store + fake provider + draft

@MainActor
final class HomeAwayStoreAndDraftTests: XCTestCase {
    private final class FakeFixProvider: LocationFixProviding {
        var fix: CLLocation?
        var requested = 0
        func fixIfAuthorized(timeout _: TimeInterval) async -> CLLocation? { fix }
        func requestPermission() async -> Bool { requested += 1; return true }
    }

    func testStoreRoundTripsHomeAndLastOriginOnDevice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "homeaway.\(UUID().uuidString)"))
        let store = HomeLocationStore(defaults: defaults)
        XCTAssertNil(store.home)
        store.setHome(latitude: 1, longitude: 2, label: "Flat")
        XCTAssertEqual(store.home?.label, "Flat")
        store.lastOrigin = .out
        XCTAssertEqual(HomeLocationStore(defaults: defaults).lastOrigin, .out)
        store.clearHome()
        XCTAssertNil(store.home)
    }

    func testFakeProviderFeedsTheDecider() async {
        let provider = FakeFixProvider()
        let home = HomeLocation(latitude: 10, longitude: 10, label: nil, setAt: Date())
        provider.fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 10),
            altitude: 0, horizontalAccuracy: 15, verticalAccuracy: 0, timestamp: Date()
        )
        let fix = await provider.fixIfAuthorized(timeout: 3)
        XCTAssertEqual(HomeAwayDecider.isAtHome(fix: fix, home: home), true)
        provider.fix = nil
        let none = await provider.fixIfAuthorized(timeout: 3)
        XCTAssertNil(HomeAwayDecider.isAtHome(fix: none, home: home))
    }

    private func draft() -> MealReviewDraft {
        MealReviewDraft(items: [])
    }

    func testAutoOriginThenManualOverrideSticks() {
        var draft = draft()
        XCTAssertTrue(draft.originWasAutoSet)
        draft.applySuggestedOrigin(.out)
        XCTAssertEqual(draft.origin, .out)
        XCTAssertTrue(draft.originWasAutoSet)
        draft.setOrigin(.kitchen)
        XCTAssertFalse(draft.originWasAutoSet)
        // A late location fix says "out": the manual choice stays.
        draft.applySuggestedOrigin(.out)
        XCTAssertEqual(draft.origin, .kitchen)
    }
}

// MARK: - Recorder

@MainActor
final class HomeAwayRecorderTests: XCTestCase {
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

    private func stock(_ name: String, grams: Double) {
        context.insert(PantryItem(
            canonicalName: FoodCanonicalizer.canonicalize(name).lowercased(),
            displayName: name, quantity: grams, unit: .grams, storageLocation: .pantry
        ))
        try? context.save()
    }

    private func pantryGrams(_ name: String) -> Double? {
        let canonical = FoodCanonicalizer.canonicalize(name).lowercased()
        return ((try? context.fetch(FetchDescriptor<PantryItem>())) ?? [])
            .first { $0.canonicalName.lowercased() == canonical }?.quantity
    }

    private func input(_ name: String, grams: Double = 100) -> MealFoodItemInput {
        MealFoodItemInput(
            foodId: UUID().uuidString, name: name, brand: nil, servings: 1, servingSize: grams, servingUnit: "g",
            calories: 300, proteinGrams: 10, carbsGrams: 40, fatGrams: 5, source: .manual
        )
    }

    private func allMeals() -> [PlannedMeal] {
        (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
    }

    private func slot(_ type: MealType) -> PlannedMeal {
        let plan = WeeklyMealPlan(
            startDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        )
        context.insert(plan)
        let meal = PlannedMeal(
            dayDate: Date(), mealNumber: type.sortOrder + 1, mealName: type.displayName, scheduledTime: "12:00",
            foods: [PlannedFood(name: "Planned dish", quantityGrams: 300, calories: 500, proteinG: 40, carbsG: 60, fatG: 20)],
            totalCalories: 500, totalProtein: 40, totalCarbs: 60, totalFat: 20, status: .planned, mealPlan: plan
        )
        context.insert(meal)
        return meal
    }

    func testKitchenUnplannedLogDeductsAndRecordsOrigin() throws {
        stock("Rolled oats", grams: 500)
        let result = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(pantryGrams("Rolled oats"), 400)
        XCTAssertTrue(result.meal.didDecrementPantry)
        XCTAssertEqual(result.meal.origin, .kitchen)
        XCTAssertEqual(result.logged.calories, 300, "totals are unchanged by origin")
    }

    func testOutAndUnknownDoNotDeduct() throws {
        stock("Rolled oats", grams: 500)
        let out = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .out, modelContext: context
        )
        XCTAssertEqual(out.meal.origin, .out)
        XCTAssertFalse(out.meal.didDecrementPantry)
        _ = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .dinner, eatenAt: Date(), source: .manual, modelContext: context
        )
        XCTAssertEqual(pantryGrams("Rolled oats"), 500)
    }

    func testKitchenPlanSlotLogDeductsTheLoggedFoods() throws {
        stock("Rolled oats", grams: 500)
        let planned = slot(.lunch)
        let result = try EatenMealRecorder.record(
            [input("Rolled oats", grams: 150)], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(result.meal.id, planned.id)
        XCTAssertEqual(pantryGrams("Rolled oats"), 350)
        XCTAssertEqual(planned.origin, .kitchen)
    }

    func testAddMergeDeductsOnlyNewFoodsAndAppendsDetail() throws {
        stock("Rolled oats", grams: 500)
        let first = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .kitchen, modelContext: context
        )
        let merged = try EatenMealRecorder.record(
            [input("Rolled oats", grams: 50)], type: .lunch, eatenAt: Date(), source: .manual,
            resolution: .add, origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(merged.meal.id, first.meal.id)
        XCTAssertEqual(pantryGrams("Rolled oats"), 350)
        XCTAssertEqual(merged.meal.decrementDetail.count, 2)
    }

    func testEditMergeDoesNotDeduct() throws {
        stock("Rolled oats", grams: 500)
        _ = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .kitchen, modelContext: context
        )
        _ = try EatenMealRecorder.record(
            [input("Rolled oats", grams: 200)], type: .lunch, eatenAt: Date(), source: .manual,
            resolution: .edit, origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(pantryGrams("Rolled oats"), 400)
    }

    func testEditMergeOfAnOutLogNeverBecomesKitchen() throws {
        stock("Rolled oats", grams: 500)
        _ = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual, origin: .out, modelContext: context
        )
        let edited = try EatenMealRecorder.record(
            [input("Rolled oats", grams: 200)], type: .lunch, eatenAt: Date(), source: .manual,
            resolution: .edit, origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(edited.meal.origin, .out)
        XCTAssertEqual(pantryGrams("Rolled oats"), 500)
    }

    func testUndoGivesBackExactlyAndRestoreDeductsAgain() throws {
        stock("Rolled oats", grams: 500)
        let result = try EatenMealRecorder.record(
            [input("Rolled oats", grams: 120)], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .kitchen, modelContext: context
        )
        XCTAssertEqual(pantryGrams("Rolled oats"), 380)
        let env = MealOutcomeService.Env(modelContext: context)
        let snapshot = try MealOutcomeService.undo(result.meal, env: env)
        XCTAssertEqual(pantryGrams("Rolled oats"), 500)
        XCTAssertTrue(allMeals().isEmpty)

        try MealOutcomeService.restore(snapshot, env: env)
        XCTAssertEqual(pantryGrams("Rolled oats"), 380)
        XCTAssertEqual(allMeals().first?.origin, .kitchen)
    }

    func testUndoOfOutLogLeavesPantryAlone() throws {
        stock("Rolled oats", grams: 500)
        let result = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .out, modelContext: context
        )
        let env = MealOutcomeService.Env(modelContext: context)
        let snapshot = try MealOutcomeService.undo(result.meal, env: env)
        try MealOutcomeService.restore(snapshot, env: env)
        XCTAssertEqual(pantryGrams("Rolled oats"), 500)
        XCTAssertEqual(allMeals().first?.origin, .out)
    }

    func testPlanSlotUndoClearsOriginAndCreditsBack() throws {
        stock("Rolled oats", grams: 500)
        let planned = slot(.lunch)
        let result = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual,
            origin: .kitchen, modelContext: context
        )
        let env = MealOutcomeService.Env(modelContext: context)
        let snapshot = try MealOutcomeService.undo(result.meal, env: env)
        XCTAssertEqual(pantryGrams("Rolled oats"), 500)
        XCTAssertNil(planned.origin)
        try MealOutcomeService.restore(snapshot, env: env)
        XCTAssertEqual(pantryGrams("Rolled oats"), 400)
        XCTAssertEqual(planned.origin, .kitchen)
    }

    func testPreviewMutatesNothingAndMatchesTheRealDeduction() throws {
        stock("Rolled oats", grams: 500)
        let foods = [PlannedFood(name: "Rolled oats", quantityGrams: 100, calories: 0, proteinG: 0, carbsG: 0, fatG: 0)]
        let lines = PantryDecrementService.preview(foods: foods, modelContext: context)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(pantryGrams("Rolled oats"), 500)
        XCTAssertFalse(context.hasChanges)
        PantryDecrementService.decrement(foods: foods, label: "t", modelContext: context)
        XCTAssertEqual(pantryGrams("Rolled oats"), 400)
        XCTAssertTrue(PantryDecrementService.preview(foods: [PlannedFood(name: "Unicorn steak", quantityGrams: 50, calories: 0, proteinG: 0, carbsG: 0, fatG: 0)], modelContext: context).isEmpty)
    }

    func testCoachSnapshotFlagsAteOut() throws {
        let out = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .lunch, eatenAt: Date(), source: .manual, origin: .out, modelContext: context
        )
        XCTAssertTrue(CoachMealSnapshot(meal: out.meal).ateOut)
        let unknown = try EatenMealRecorder.record(
            [input("Rolled oats")], type: .dinner, eatenAt: Date(), source: .manual, modelContext: context
        )
        XCTAssertFalse(CoachMealSnapshot(meal: unknown.meal).ateOut)
    }
}
