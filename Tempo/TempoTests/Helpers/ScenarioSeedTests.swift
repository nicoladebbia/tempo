//
// ScenarioSeedTests.swift
// Tempo
//
// `sim.sh qa --scenario` starting states and the local test-server hooks.
// A scenario that silently seeds nothing (a model init changed, a save path
// moved) would make every QA run on it meaningless, so each one is checked
// for the rows it promises.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ScenarioSeedTests: XCTestCase {
    private let onboardingKey = "tempo.onboarding.complete"
    private var savedOnboarding: Any?
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        savedOnboarding = UserDefaults.standard.object(forKey: onboardingKey)
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedOnboarding, forKey: onboardingKey)
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func count<T: PersistentModel>(_: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    func testFuelReadyCompletesTheFuelProfile() throws {
        ScenarioSeed.seed("fuel-ready", context: context)

        XCTAssertTrue(UserDefaults.standard.bool(forKey: onboardingKey))
        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<DietaryProfile>()).first)
        XCTAssertEqual(profile.currentWeightKg, 82)
        XCTAssertEqual(profile.primaryGoal, .leanGain)
        let daily = try XCTUnwrap(UserDailyPlanProfile.current(in: context))
        XCTAssertEqual(daily.weeklyRoutine?.typicalWakeMinutes, 7 * 60)
        XCTAssertEqual(daily.weeklyRoutine?.trainingDaysPerWeek, 4)
        XCTAssertEqual(count(PantryItem.self), 8)
        XCTAssertEqual(count(UserSettings.self), 1)
    }

    func testEatenBeforeUpdateHasEatenMealsWithoutUndoDetail() throws {
        ScenarioSeed.seed("eaten-before-update", context: context)

        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let eaten = meals.filter { $0.status == .eaten }
        XCTAssertEqual(eaten.count, 2)
        XCTAssertTrue(eaten.allSatisfy { $0.didDecrementPantry && $0.decrementDetailJSON == nil })
        let chicken = try XCTUnwrap(context.fetch(FetchDescriptor<PantryItem>()).first { $0.canonicalName == "chicken breast" })
        XCTAssertEqual(chicken.quantity, 1200 - 180)
    }

    func testGroceriesAndTrainingReuseTheirUITestSeeds() {
        ScenarioSeed.seed("groceries", context: context)
        XCTAssertGreaterThan(count(GroceryListItem.self), 0)

        ScenarioSeed.seed("training", context: context)
        XCTAssertEqual(count(TrainerProgram.self), 1)
    }

    func testEdgeSeedsExtremeValues() throws {
        ScenarioSeed.seed("edge", context: context)
        let items = try context.fetch(FetchDescriptor<PantryItem>())
        XCTAssertTrue(items.contains { $0.quantity == 0 })
        XCTAssertTrue(items.contains { $0.quantity == 99999 })
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlannedMeal>()).contains { $0.foods.isEmpty })
    }

    func testFreshAndUnknownSeedNothing() {
        UserDefaults.standard.set(false, forKey: onboardingKey)
        ScenarioSeed.seed("fresh", context: context)
        ScenarioSeed.seed("no-such-scenario", context: context)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: onboardingKey))
        XCTAssertEqual(count(PantryItem.self), 0)
        XCTAssertEqual(count(DietaryProfile.self), 0)
    }

    // MARK: - TestServer

    func testTestServerOnlyAcceptsLoopbackURLs() {
        XCTAssertEqual(TestServer.loopbackURL("http://127.0.0.1:58080")?.port, 58080)
        XCTAssertNotNil(TestServer.loopbackURL("http://localhost:58080"))
        XCTAssertNil(TestServer.loopbackURL("https://api.tempo.app"))
        XCTAssertNil(TestServer.loopbackURL("http://127.0.0.1.evil.com"))
        XCTAssertNil(TestServer.loopbackURL("off"))
        XCTAssertNil(TestServer.loopbackURL(nil))
    }

    func testTestServerReadsTheValueAfterAFlag() {
        let args = ["Tempo", "-tempoAPIBaseURL", "http://127.0.0.1:58080", "-tempoTestUserID"]
        XCTAssertEqual(TestServer.argument("-tempoAPIBaseURL", in: args), "http://127.0.0.1:58080")
        XCTAssertNil(TestServer.argument("-tempoTestUserID", in: args))
        XCTAssertNil(TestServer.argument("-missing", in: args))
    }
}
