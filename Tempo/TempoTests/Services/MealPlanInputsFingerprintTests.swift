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

    func testChangesWhenAMatchIsAddedOrTheCustomSplitChanges() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        context.insert(settings)
        try context.save()
        let before = MealPlanInputsFingerprint.current(in: context)

        context.insert(Match(kickoff: Date().addingTimeInterval(3 * 24 * 3600), isCompetitive: true))
        try context.save()
        let withMatch = MealPlanInputsFingerprint.current(in: context)
        XCTAssertNotEqual(before, withMatch, "a new match reshapes the training week")

        settings.customWeekdayPlan = [.push, .rest, .pull, .rest, .legs, .rest, .rest]
        try context.save()
        XCTAssertNotEqual(withMatch, MealPlanInputsFingerprint.current(in: context))
    }

    /// Fix #6 — in sequence mode, completing a session shifts which of this
    /// week's remaining days are training days even with nothing else about
    /// the program changed, so the cached plan must be flagged stale too.
    func testChangesWhenASequenceModeSessionIsCompleted() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let program = TrainerProgram(
            name: "PT", startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(
                    weekday: 1, title: nil, focus: "push",
                    exercises: [ProgramExercise(name: "Bench", sets: 3, repsLow: 5)]
                ),
            ])],
            isActive: true, sourceKind: "text", scheduleMode: .sequence
        )
        context.insert(program)
        try context.save()
        let before = MealPlanInputsFingerprint.current(in: context)

        let completed = WorkoutPlan(date: Date(), type: .push, status: .completed)
        completed.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(completed)
        try context.save()

        XCTAssertNotEqual(before, MealPlanInputsFingerprint.current(in: context), "the sequence cursor advanced")
    }

    /// A fixed-mode program's completions don't move anything (no cursor to
    /// advance) — the fingerprint should stay stable so a normal set logged
    /// during a workout doesn't spuriously mark the meal plan out of date.
    func testFixedModeCompletionDoesNotChangeTheFingerprint() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let program = TrainerProgram(
            name: "PT", startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(
                    weekday: 1, title: nil, focus: "push",
                    exercises: [ProgramExercise(name: "Bench", sets: 3, repsLow: 5)]
                ),
            ])],
            isActive: true, sourceKind: "text"
        )
        context.insert(program)
        try context.save()
        let before = MealPlanInputsFingerprint.current(in: context)

        let completed = WorkoutPlan(date: Date(), type: .push, status: .completed)
        completed.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(completed)
        try context.save()

        XCTAssertEqual(before, MealPlanInputsFingerprint.current(in: context))
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
