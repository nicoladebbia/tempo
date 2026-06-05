//
// MealPlanIntakePersistenceTests.swift
// Tempo
//
// The persist/reuse mapper between MealPlanIntake and UserSettings — the core
// of Phase 1. Bug it fixes: 4 of 5 generate paths passed no intake → bare
// .default, so a "Regenerate Plan" tap ignored the user's cooking prefs. Now
// those paths load the persisted intake. The mapper is pure (no AI), so it's
// genuinely verifiable.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class MealPlanIntakePersistenceTests: XCTestCase {

    // Hold the container for the test's lifetime — if it's a local in the
    // helper it deallocs and SwiftData resets the context, killing the
    // returned model ("model instance was destroyed by ModelContext.reset").
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: UserSettings.self, UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func settings() -> UserSettings {
        let s = UserSettings()
        container.mainContext.insert(s)
        return s
    }

    func testLoadPersisted_allUnset_equalsDefaultsPerField() throws {
        let s = settings()
        let intake = MealPlanIntake.loadPersisted(from: s)
        XCTAssertEqual(intake.cookableDaysThisWeek, MealPlanIntake.default.cookableDaysThisWeek)
        XCTAssertEqual(intake.leftoverTolerance, MealPlanIntake.default.leftoverTolerance)
        XCTAssertEqual(intake.eatingWindow, EatingWindow.default)
        XCTAssertEqual(intake.recoveryAdjusted, false)
        XCTAssertTrue(intake.temporaryExclusions.isEmpty)
    }

    func testPersistThenLoad_roundTrips() throws {
        let s = settings()
        let original = MealPlanIntake(
            cookableDaysThisWeek: 2,
            leftoverTolerance: .fullWeekPrep,
            eatingWindow: EatingWindow(firstMealHour: 7, lastMealHour: 22),
            groceryIntent: nil,
            recoveryAdjusted: true,
            temporaryExclusions: ["salmon", "broccoli"],
            trainingSchedule: nil
        )
        original.persist(to: s)
        let loaded = MealPlanIntake.loadPersisted(from: s)

        XCTAssertEqual(loaded.cookableDaysThisWeek, 2)
        XCTAssertEqual(loaded.leftoverTolerance, .fullWeekPrep)
        XCTAssertEqual(loaded.eatingWindow.firstMealHour, 7)
        XCTAssertEqual(loaded.eatingWindow.lastMealHour, 22)
        XCTAssertTrue(loaded.recoveryAdjusted)
        XCTAssertEqual(Set(loaded.temporaryExclusions), ["salmon", "broccoli"])
    }

    func testExclusionsPersist_notClearedAcrossLoads() throws {
        // Nicola's decision: exclusions persist (managed from the settings
        // page), they do NOT auto-reset each week.
        let s = settings()
        var intake = MealPlanIntake.default
        intake.temporaryExclusions = ["dairy"]
        intake.persist(to: s)
        XCTAssertEqual(MealPlanIntake.loadPersisted(from: s).temporaryExclusions, ["dairy"])
        // A second load (a later week's regen) still sees them.
        XCTAssertEqual(MealPlanIntake.loadPersisted(from: s).temporaryExclusions, ["dairy"])
    }

    func testInvalidEatingWindow_fallsBackToDefault() throws {
        let s = settings()
        // Last <= first is invalid; loadPersisted must fall back, not emit a
        // broken window the prompt would choke on.
        s.mealIntakeFirstMealHour = 20
        s.mealIntakeLastMealHour = 8
        XCTAssertEqual(MealPlanIntake.loadPersisted(from: s).eatingWindow, EatingWindow.default)
    }
}
