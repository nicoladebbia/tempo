//
// MealPlanIntakePersistenceTests.swift
// Tempo
//
// The persisted-intake round-trip that lets every regenerate reuse the user's
// saved preferences instead of falling back to .default (the measured Phase 1
// bug: only the wizard passed a real intake; the other 4 generate paths got
// defaults). persist(to:) writes the fields onto UserSettings;
// loadPersisted(from:) reads them back. The AI Meals settings page (Phase 5)
// reimplements the same mapping in its save/load, so this contract guards both.
//
// Pure mapper test — UserSettings is a SwiftData @Model, but persist/loadPersisted
// only touch its stored properties, so it round-trips without a ModelContainer.
//

@testable import Tempo
import XCTest

@MainActor
final class MealPlanIntakePersistenceTests: XCTestCase {

    // MARK: - Round-trip

    func testPersistThenLoadRoundTripsEveryField() {
        let original = MealPlanIntake(
            cookableDaysThisWeek: 5,
            leftoverTolerance: .twoToThreeDayBatches,
            eatingWindow: EatingWindow(firstMealHour: 7, lastMealHour: 21),
            groceryIntent: nil,
            recoveryAdjusted: true,
            temporaryExclusions: ["broccoli", "tofu"],
            trainingSchedule: nil
        )

        let settings = UserSettings()
        original.persist(to: settings)
        let restored = MealPlanIntake.loadPersisted(from: settings)

        XCTAssertEqual(restored.cookableDaysThisWeek, 5)
        XCTAssertEqual(restored.leftoverTolerance, .twoToThreeDayBatches)
        XCTAssertEqual(restored.eatingWindow.firstMealHour, 7)
        XCTAssertEqual(restored.eatingWindow.lastMealHour, 21)
        XCTAssertTrue(restored.recoveryAdjusted)
        XCTAssertEqual(restored.temporaryExclusions, ["broccoli", "tofu"])
    }

    func testPersistWritesExclusionsAsCommaSeparated() {
        let intake = MealPlanIntake(
            cookableDaysThisWeek: 3,
            leftoverTolerance: .freshDaily,
            eatingWindow: .default,
            groceryIntent: nil,
            recoveryAdjusted: false,
            temporaryExclusions: ["broccoli", "tofu"],
            trainingSchedule: nil
        )
        let settings = UserSettings()
        intake.persist(to: settings)
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "broccoli, tofu")
    }

    // MARK: - Fallbacks (the nil-default path)

    func testLoadFromEmptySettingsFallsBackToDefaults() {
        let restored = MealPlanIntake.loadPersisted(from: UserSettings())
        XCTAssertEqual(restored.cookableDaysThisWeek, MealPlanIntake.default.cookableDaysThisWeek)
        XCTAssertEqual(restored.leftoverTolerance, MealPlanIntake.default.leftoverTolerance)
        XCTAssertEqual(restored.eatingWindow.firstMealHour, EatingWindow.default.firstMealHour)
        XCTAssertEqual(restored.eatingWindow.lastMealHour, EatingWindow.default.lastMealHour)
        XCTAssertFalse(restored.recoveryAdjusted)
        XCTAssertTrue(restored.temporaryExclusions.isEmpty)
    }

    func testLoadRejectsInvalidEatingWindow() {
        // last <= first is invalid → falls back to the default window, not the
        // garbage values, so a corrupt persist can't produce an empty window.
        let settings = UserSettings()
        settings.mealIntakeFirstMealHour = 20
        settings.mealIntakeLastMealHour = 8
        let restored = MealPlanIntake.loadPersisted(from: settings)
        XCTAssertEqual(restored.eatingWindow, .default)
    }
}
