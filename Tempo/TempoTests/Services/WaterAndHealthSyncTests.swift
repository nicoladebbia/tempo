//
// WaterAndHealthSyncTests.swift
// Tempo
//
// Round 2 lane W: water is saved (survives a new store instance), undo removes
// the row and the Health sample; eaten meals reconcile to Health (eat -> write,
// edit -> version bump, undo -> delete, denied -> retried later).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WaterAndHealthSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var healthKit: MockHealthKitService!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
        healthKit = MockHealthKitService()
        defaults = UserDefaults(suiteName: "WaterAndHealthSyncTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        healthKit = nil
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - Water

    func testWaterAddsPersistAndSumAcrossStoreInstances() {
        let store = WaterStore(context: context, healthKit: nil)
        store.add(ml: 250)
        store.add(ml: 250)
        let reopened = WaterStore(context: context, healthKit: nil)
        XCTAssertEqual(reopened.total(), 500)
        XCTAssertEqual(WaterStore.total(in: context), 500)
    }

    func testWaterRejectsOutOfRange() {
        let store = WaterStore(context: context, healthKit: nil)
        XCTAssertNil(store.add(ml: 0))
        XCTAssertNil(store.add(ml: WaterStore.maxEntryMl + 1))
        XCTAssertEqual(store.total(), 0)
    }

    func testWaterUndoRemovesLastAndPostsNotification() {
        let store = WaterStore(context: context, healthKit: nil)
        store.add(ml: 250, at: Date().addingTimeInterval(-60))
        store.add(ml: 500)
        let posted = expectation(forNotification: .tempoWaterLogged, object: nil)
        XCTAssertEqual(store.undoLast(), 500)
        wait(for: [posted], timeout: 1)
        XCTAssertEqual(store.total(), 250)
        XCTAssertNil(WaterStore(context: context, healthKit: nil).undoLast(on: Date().addingTimeInterval(-86400 * 3)))
    }

    func testWaterWritesAndDeletesHealthSample() async throws {
        let store = WaterStore(context: context, healthKit: healthKit)
        let log = try XCTUnwrap(store.add(ml: 330))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(healthKit.writtenWater.map(\.syncIdentifier), ["tempo-water-\(log.id.uuidString)"])
        XCTAssertEqual(healthKit.writtenWater.first?.ml, 330)
        store.undoLast()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(healthKit.deletedSyncIdentifiers, ["tempo-water-\(log.id.uuidString)"])
    }

    // MARK: - Meals -> Health

    private func makeSync() -> HealthNutritionSync {
        HealthNutritionSync(healthKit: healthKit, context: context, defaults: defaults, debounce: .milliseconds(10))
    }

    private func eatenMeal(_ name: String = "Lunch", kcal: Double = 600) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: Date(), mealName: name, scheduledTime: "00:01",
            totalCalories: kcal, totalProtein: 40, totalCarbs: 60, totalFat: 20, status: .eaten
        )
        context.insert(meal)
        try? context.save()
        return meal
    }

    func testEatenMealIsWrittenOnceAndNotRewritten() async throws {
        let meal = eatenMeal()
        let sync = makeSync()
        await sync.reconcile()
        await sync.reconcile()
        XCTAssertEqual(healthKit.writtenNutrition.count, 1)
        let sample = try XCTUnwrap(healthKit.writtenNutrition.first)
        XCTAssertEqual(sample.syncIdentifier, "tempo-meal-\(meal.id.uuidString)")
        XCTAssertEqual(sample.name, "Lunch")
        XCTAssertEqual(sample.calories, 600)
        XCTAssertEqual(sample.proteinGrams, 40)
    }

    func testPlannedMealIsNotWritten() async {
        context.insert(PlannedMeal(dayDate: Date(), totalCalories: 500, status: .planned))
        await makeSync().reconcile()
        XCTAssertTrue(healthKit.writtenNutrition.isEmpty)
    }

    func testEditBumpsVersion() async throws {
        let meal = eatenMeal()
        let sync = makeSync()
        await sync.reconcile()
        meal.totalCalories = 800
        await sync.reconcile()
        XCTAssertEqual(healthKit.writtenNutrition.count, 2)
        XCTAssertEqual(healthKit.writtenNutrition[1].calories, 800)
        XCTAssertGreaterThan(healthKit.writtenNutrition[1].syncVersion, healthKit.writtenNutrition[0].syncVersion)
        XCTAssertTrue(healthKit.deletedSyncIdentifiers.isEmpty)
    }

    func testUndoDeletesAndRestoreReadds() async {
        let meal = eatenMeal()
        let sync = makeSync()
        await sync.reconcile()
        meal.status = .planned
        await sync.reconcile()
        XCTAssertEqual(healthKit.deletedSyncIdentifiers, ["tempo-meal-\(meal.id.uuidString)"])
        meal.status = .eaten
        await sync.reconcile()
        XCTAssertEqual(healthKit.writtenNutrition.count, 2)
    }

    func testDeletedMealIsRemovedFromHealth() async {
        let meal = eatenMeal()
        let sync = makeSync()
        await sync.reconcile()
        context.delete(meal)
        try? context.save()
        await sync.reconcile()
        XCTAssertEqual(healthKit.deletedSyncIdentifiers.count, 1)
    }

    func testDeniedWriteIsRetriedAfterAccessGranted() async {
        _ = eatenMeal()
        let sync = makeSync()
        healthKit.nutritionWritesSucceed = false
        await sync.reconcile()
        XCTAssertTrue(healthKit.writtenNutrition.isEmpty)
        healthKit.nutritionWritesSucceed = true
        await sync.reconcile()
        XCTAssertEqual(healthKit.writtenNutrition.count, 1)
    }
}
