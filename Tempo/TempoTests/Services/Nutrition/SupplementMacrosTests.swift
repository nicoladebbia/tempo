//
// SupplementMacrosTests.swift
// Tempo
//
// Round 2 (Lane S): a ticked supplement dose counts its macros in today's
// totals; unticking removes exactly that entry; zero-macro supplements log
// nothing; a planned slot is never touched.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SupplementMacrosTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext {
        container.mainContext
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func whey() -> Supplement {
        let s = Supplement(name: "Whey Protein", kind: .protein, proteinGramsPerServing: 24, servingsRemaining: 20)
        s.caloriesPerServing = 120
        s.carbsGramsPerServing = 3
        s.fatGramsPerServing = 1.5
        ctx.insert(s)
        return s
    }

    private func eatenTotals() -> MealMacros {
        CanonicalMeals.totals(of: CanonicalMeals.eatenMeals(on: Date(), in: ctx))
    }

    func testTickAddsMacrosAndUntickRemovesThem() {
        let s = whey()
        XCTAssertEqual(eatenTotals(), .zero)
        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        XCTAssertEqual(eatenTotals(), MealMacros(calories: 120, protein: 24, carbs: 3, fat: 1.5))
        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        XCTAssertEqual(eatenTotals(), .zero)
        XCTAssertTrue(CanonicalMeals.meals(on: Date(), in: ctx).isEmpty, "Untick leaves no entry behind")
    }

    func testNotificationTakenPathCountsToo() {
        let s = whey()
        SupplementReminderScheduler.markTaken(names: [s.name], ids: [s.id.uuidString], modelContext: ctx)
        XCTAssertEqual(eatenTotals().protein, 24)
        XCTAssertEqual(eatenTotals().calories, 120)
        // Idempotent: a second "Taken" doesn't double count.
        SupplementReminderScheduler.markTaken(names: [s.name], ids: [s.id.uuidString], modelContext: ctx)
        XCTAssertEqual(eatenTotals().protein, 24)
    }

    func testZeroMacroSupplementCreatesNothing() {
        let creatine = Supplement(name: "Creatine Monohydrate", kind: .creatine, servingsRemaining: 30)
        ctx.insert(creatine)
        SupplementIntakeStore.toggle(supplementID: creatine.id, name: creatine.name, in: ctx)
        XCTAssertTrue(CanonicalMeals.meals(on: Date(), in: ctx).isEmpty)
        XCTAssertFalse(creatine.hasMacros)
    }

    func testDoseNeverReplacesAPlannedSlot() throws {
        let breakfast = PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "Breakfast", scheduledTime: "08:00",
            foods: [PlannedFood(name: "Oats", quantityGrams: 80, calories: 300, proteinG: 10, carbsG: 50, fatG: 6)],
            totalCalories: 300, totalProtein: 10, totalCarbs: 50, totalFat: 6, status: .planned
        )
        ctx.insert(breakfast)
        let s = whey()
        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        XCTAssertEqual(breakfast.status, .planned)
        XCTAssertEqual(breakfast.totalCalories, 300)
        XCTAssertEqual(eatenTotals().calories, 120)

        // A real snack log afterwards must not land in the supplement entry.
        let item = MealFoodItemInput(
            foodId: "x", name: "Apple", brand: nil, servings: 1, servingSize: 100, servingUnit: "g",
            calories: 52, proteinGrams: 0, carbsGrams: 14, fatGrams: 0, source: .manual
        )
        try EatenMealRecorder.record([item], type: .snack, eatenAt: Date(), source: .manual, modelContext: ctx)
        XCTAssertEqual(eatenTotals().calories, 172)
        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        XCTAssertEqual(eatenTotals().calories, 52, "Untick removes only the supplement entry")
    }

    func testBackfilledLookupMacrosFlowIntoShelfItem() {
        let dto = SupplementLookupDTO(
            upc: "1", brand: nil, name: "Gainer", kind: "protein", dosePerServing: nil, servingsPerContainer: 10,
            proteinGramsPerServing: 50, caloriesPerServing: 600, carbsGramsPerServing: 90, fatGramsPerServing: 6,
            certifications: [], source: "openfoodfacts"
        )
        let s = Supplement(lookup: dto)
        XCTAssertEqual(s.macrosPerServing, MealMacros(calories: 600, protein: 50, carbs: 90, fat: 6))
        let old = try? JSONDecoder().decode(
            SupplementLookupDTO.self,
            from: Data(#"{"upc":"1","name":"X","kind":"other","certifications":[],"source":"dsld"}"#.utf8)
        )
        XCTAssertNotNil(old, "Old backends omit the macro keys")
        XCTAssertNil(old?.caloriesPerServing)
    }

    func testCatalogPrefills() {
        let whey = SupplementQuickAddCatalog.items.first { $0.name == "Whey Protein" }
        XCTAssertEqual(whey?.calories, 120)
        XCTAssertEqual(whey?.proteinGrams, 24)
        let creatine = SupplementQuickAddCatalog.items.first { $0.name == "Creatine Monohydrate" }
        XCTAssertEqual(creatine?.calories, 0)
        XCTAssertEqual(SupplementQuickAddCatalog.items.first { $0.name == "Collagen" }?.proteinGrams, 9)
        XCTAssertNotNil(SupplementQuickAddCatalog.items.first { $0.name == "Mass Gainer" })
    }

    func testDeleteThenUndoRestoresTheSameEntrySoUntickStillRemovesIt() throws {
        let s = whey()
        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        let entry = try XCTUnwrap(CanonicalMeals.meals(on: Date(), in: ctx).first)
        let env = MealOutcomeService.Env(modelContext: ctx)
        let snapshot = try MealOutcomeService.deleteLog(entry, env: env)
        XCTAssertEqual(eatenTotals(), .zero)

        try MealOutcomeService.restore(snapshot, env: env)
        let restored = try XCTUnwrap(CanonicalMeals.meals(on: Date(), in: ctx).first)
        XCTAssertTrue(EatenMealRecorder.isSupplementDose(restored), "Comes back as the Supplements entry, not a snack")
        XCTAssertEqual(restored.id, snapshot.mealID)
        XCTAssertEqual(eatenTotals().protein, 24)

        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        XCTAssertEqual(eatenTotals(), .zero, "Unticking after the undo still takes the macros out")
    }
}
