//
// MealPlanInputsFingerprintTests.swift
// Tempo
//
// Stale-plan detection: the fingerprint of plan-shaping inputs stamped on
// WeeklyMealPlan must be stable, order-independent, and change when a
// relevant setting changes — and the Nutrition VM must flag a mismatch.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class MealPlanInputsFingerprintTests: XCTestCase {
    private func inputs(
        split: String? = "ppl",
        football: Int? = 0,
        profile: DietaryProfile? = DietaryProfile()
    ) -> MealPlanInputsFingerprint.Inputs {
        MealPlanInputsFingerprint.Inputs(
            trainingSplit: split, footballDays: football, activeTrainerProgramIDs: [],
            profile: MealPlanInputsFingerprint.profileFields(profile)
        )
    }

    func testStableForSameInputs() {
        XCTAssertEqual(
            MealPlanInputsFingerprint.fingerprint(inputs()),
            MealPlanInputsFingerprint.fingerprint(inputs())
        )
        XCTAssertEqual(MealPlanInputsFingerprint.fingerprint(inputs()).count, 64, "SHA-256 hex")
    }

    func testChangesWithTrainingAndFootball() {
        let base = MealPlanInputsFingerprint.fingerprint(inputs())
        XCTAssertNotEqual(base, MealPlanInputsFingerprint.fingerprint(inputs(split: "upperLower")))
        XCTAssertNotEqual(base, MealPlanInputsFingerprint.fingerprint(inputs(football: 2)))
    }

    func testChangesWithDietProfileEdits() {
        let profile = DietaryProfile()
        let before = MealPlanInputsFingerprint.fingerprint(inputs(profile: profile))
        profile.isVegetarian = true
        XCTAssertNotEqual(before, MealPlanInputsFingerprint.fingerprint(inputs(profile: profile)))
    }

    func testListOrderAndCaseDoNotMatter() {
        let a = DietaryProfile(allergies: ["Peanut", "soy"])
        let b = DietaryProfile(allergies: ["SOY", "peanut"])
        XCTAssertEqual(
            MealPlanInputsFingerprint.profileFields(a),
            MealPlanInputsFingerprint.profileFields(b)
        )
        let id1 = UUID(), id2 = UUID()
        var x = inputs()
        var y = inputs()
        x.activeTrainerProgramIDs = [id1, id2]
        y.activeTrainerProgramIDs = [id2, id1]
        XCTAssertEqual(MealPlanInputsFingerprint.fingerprint(x), MealPlanInputsFingerprint.fingerprint(y))
    }

    // MARK: - VM freshness

    private var container: ModelContainer!

    private func makeContext() throws -> ModelContext {
        container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self,
            MealFeedback.self, PantryItem.self, SupplementIntakeLog.self, MealLog.self,
            MacroCarryover.self, WorkoutPlan.self, ActivitySession.self, TrainerProgram.self,
            UserSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return container.mainContext
    }

    func testLegacyPlanIsAdoptedThenFlaggedAfterProfileEdit() throws {
        let ctx = try makeContext()
        let profile = DietaryProfile()
        ctx.insert(profile)
        let today = Calendar.current.startOfDay(for: Date())
        let plan = try WeeklyMealPlan(
            startDate: XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today)),
            endDate: XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: today))
        )
        ctx.insert(plan)
        try ctx.save()

        let vm = NutritionTabViewModel()
        vm.loadToday(modelContext: ctx)
        XCTAssertNotNil(plan.inputsFingerprint, "A pre-fingerprint plan is stamped as current")
        XCTAssertFalse(vm.isPlanOutOfDate)

        profile.dislikedFoods = ["broccoli"]
        try ctx.save()
        vm.loadToday(modelContext: ctx)
        XCTAssertTrue(vm.isPlanOutOfDate, "Settings edit made the plan stale")
    }

    func testNoPlanIsNeverOutOfDate() throws {
        let ctx = try makeContext()
        ctx.insert(DietaryProfile())
        let vm = NutritionTabViewModel()
        vm.loadToday(modelContext: ctx)
        XCTAssertFalse(vm.isPlanOutOfDate)
    }
}
