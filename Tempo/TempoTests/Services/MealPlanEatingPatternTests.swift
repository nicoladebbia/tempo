//
// MealPlanEatingPatternTests.swift
// Tempo
//
// Meal-plan personalization that used to be hardcoded or ignored:
//   - clear-skin / low-dairy prompt layer → opt-in toggle + one-time migration
//   - onboarding eating window / breakfastSkipped / postWorkoutMandatory →
//     seeded into the wizard and honored by the planner (prompt + enforcer)
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class MealPlanEatingPatternTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "MealPlanEatingPatternTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    private let restrictions = MealPlanPrompts.DietaryRestrictions(
        isLactoseFree: false, noCoffee: false, isGlutenFree: false,
        isVegetarian: false, isVegan: false, isHalal: false,
        isNutFree: false, isShellFishAllergy: false,
        allergies: [], dislikedFoods: []
    )

    // MARK: - Clear-skin toggle: prompt gating

    func testFunctionalBlock_defaultOmitsClearSkinLayer() {
        let block = MealPlanPrompts.functionalNutritionBlock()
        XCTAssertFalse(block.uppercased().contains("MINIMIZE DAIRY"))
        XCTAssertFalse(block.lowercased().contains("clear skin"))
        XCTAssertFalse(block.lowercased().contains("acne"))
        XCTAssertFalse(block.uppercased().contains("NO ADDED SUGARS"))
        // The general layer still ships to everyone.
        XCTAssertTrue(block.uppercased().contains("VARIETY IS MANDATORY"))
        XCTAssertTrue(block.lowercased().contains("fat-soluble"))
    }

    func testFunctionalBlock_optInAddsClearSkinLayer() {
        let block = MealPlanPrompts.functionalNutritionBlock(clearSkinFocus: true)
        XCTAssertTrue(block.uppercased().contains("MINIMIZE DAIRY"))
        XCTAssertTrue(block.uppercased().contains("LOW GLYCEMIC LOAD"))
        XCTAssertTrue(block.contains("</functional_nutrition>"))
    }

    func testPantryBlock_mentionsClearSkinOnlyWhenOptedIn() {
        let stock = ["honey — 1 jars [Pantry]"]
        XCTAssertFalse(MealPlanPrompts.pantryStockBlock(stock).lowercased().contains("clear-skin"))
        XCTAssertTrue(MealPlanPrompts.pantryStockBlock(stock, clearSkinFocus: true).lowercased().contains("clear-skin"))
    }

    func testWeeklyPlanPrompt_threadsToggleThrough() {
        let (_, off) = MealPlanPrompts.weeklyPlanPrompt(targets: [:], restrictions: restrictions, preferences: "")
        let (_, on) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: "", clearSkinFocus: true
        )
        XCTAssertFalse(off.uppercased().contains("MINIMIZE DAIRY"))
        XCTAssertTrue(on.uppercased().contains("MINIMIZE DAIRY"))
    }

    // MARK: - Clear-skin toggle: migration

    func testMigration_newUser_defaultsOff() {
        ClearSkinFocusSetting.migrateIfNeeded(hasExistingProfile: false, hasExistingPlan: false, defaults: defaults)
        XCTAssertFalse(ClearSkinFocusSetting.isEnabled(defaults: defaults))
        XCTAssertNotNil(defaults.object(forKey: ClearSkinFocusSetting.key), "Decision is recorded once")
    }

    func testMigration_newUserFirstGenerate_profileButNoPlan_staysOff() {
        // A brand-new user creates a profile then generates: no plan exists yet.
        ClearSkinFocusSetting.migrateIfNeeded(hasExistingProfile: true, hasExistingPlan: false, defaults: defaults)
        XCTAssertFalse(ClearSkinFocusSetting.isEnabled(defaults: defaults))
    }

    func testMigration_existingInstall_turnsOn() {
        ClearSkinFocusSetting.migrateIfNeeded(hasExistingProfile: true, hasExistingPlan: true, defaults: defaults)
        XCTAssertTrue(ClearSkinFocusSetting.isEnabled(defaults: defaults))
    }

    func testMigration_runsOnlyOnce_userChoiceWins() {
        ClearSkinFocusSetting.setEnabled(false, defaults: defaults)
        ClearSkinFocusSetting.migrateIfNeeded(hasExistingProfile: true, hasExistingPlan: true, defaults: defaults)
        XCTAssertFalse(ClearSkinFocusSetting.isEnabled(defaults: defaults), "An explicit OFF is never flipped back")
    }

    func testResolve_readsStore() throws {
        let container = try ModelContainer(
            for: DietaryProfile.self, WeeklyMealPlan.self, PlannedMeal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(DietaryProfile())
        context.insert(WeeklyMealPlan(startDate: Date(), endDate: Date()))
        try context.save()

        XCTAssertTrue(ClearSkinFocusSetting.resolve(modelContext: context, defaults: defaults))
    }

    // MARK: - Onboarding → intake

    private func dailyPlan(start: Int, end: Int, skipBreakfast: Bool = false, postWorkout: Bool = false) -> UserDailyPlanProfile {
        UserDailyPlanProfile(
            eatingWindowPreset: .custom,
            eatingWindowStartMinutes: start,
            eatingWindowEndMinutes: end,
            breakfastSkipped: skipBreakfast,
            postWorkoutMandatory: postWorkout
        )
    }

    func testSeeded_noWizardWindow_usesOnboardingWindow() {
        let intake = MealPlanIntake.seeded(
            settings: UserSettings(),
            dailyPlan: dailyPlan(start: 12 * 60, end: 20 * 60, skipBreakfast: true, postWorkout: true)
        )
        XCTAssertEqual(intake.eatingWindow, EatingWindow(firstMealHour: 12, lastMealHour: 20))
        XCTAssertTrue(intake.breakfastSkipped)
        XCTAssertTrue(intake.postWorkoutMandatory)
    }

    func testSeeded_wizardWindowOverridesOnboarding() {
        let settings = UserSettings()
        settings.mealIntakeFirstMealHour = 9
        settings.mealIntakeLastMealHour = 21
        let intake = MealPlanIntake.seeded(settings: settings, dailyPlan: dailyPlan(start: 12 * 60, end: 20 * 60, skipBreakfast: true))
        XCTAssertEqual(intake.eatingWindow, EatingWindow(firstMealHour: 9, lastMealHour: 21), "Wizard can still override")
        XCTAssertTrue(intake.breakfastSkipped, "Onboarding-only flags always carry over")
    }

    func testSeeded_noProfile_isPersistedOrDefault() {
        XCTAssertEqual(MealPlanIntake.seeded(settings: nil, dailyPlan: nil), .default)
    }

    func testOnboardingWindow_roundsInward() {
        let window = MealPlanIntake.eatingWindow(fromOnboarding: dailyPlan(start: 11 * 60 + 30, end: 19 * 60 + 45))
        XCTAssertEqual(window, EatingWindow(firstMealHour: 12, lastMealHour: 19), "Start rounds up, end rounds down")
    }

    func testOnboardingWindow_invalidIsIgnored() {
        XCTAssertNil(MealPlanIntake.eatingWindow(fromOnboarding: dailyPlan(start: 20 * 60, end: 8 * 60)))
        let intake = MealPlanIntake.default.applyingOnboarding(dailyPlan(start: 20 * 60, end: 8 * 60), settings: nil)
        XCTAssertEqual(intake.eatingWindow, .default)
    }

    // MARK: - Wizard pre-fill

    func testWizardSeed_prefillsBeforeUserMoves() {
        let coordinator = WizardCoordinator(
            snapshot: WizardLaunchSnapshot(pantry: PantrySnapshot(itemCount: 20, mostRecentUpdate: Date()), whoop: nil),
            onComplete: { _ in }, onCancel: {}
        )
        var seeded = MealPlanIntake.default
        seeded.eatingWindow = EatingWindow(firstMealHour: 12, lastMealHour: 20)
        coordinator.seed(seeded)
        XCTAssertEqual(coordinator.intake.eatingWindow.firstMealHour, 12)
    }

    func testWizardSeed_ignoredOnceUserAdvanced() {
        let coordinator = WizardCoordinator(
            snapshot: WizardLaunchSnapshot(pantry: PantrySnapshot(itemCount: 20, mostRecentUpdate: Date()), whoop: nil),
            onComplete: { _ in }, onCancel: {}
        )
        coordinator.advance()
        var seeded = MealPlanIntake.default
        seeded.cookableDaysThisWeek = 1
        coordinator.seed(seeded)
        XCTAssertEqual(coordinator.intake.cookableDaysThisWeek, MealPlanIntake.default.cookableDaysThisWeek)
    }

    func testEatingWindowPickerRange_includesSeededValue() {
        XCTAssertEqual(EatingWindowStepView.range(4 ... 14, including: 16), 4 ... 16)
        XCTAssertEqual(EatingWindowStepView.range(16 ... 23, including: 15), 15 ... 23)
        XCTAssertEqual(EatingWindowStepView.range(4 ... 14, including: 9), 4 ... 14)
    }

    // MARK: - Planner prompt

    func testPrompt_breakfastSkippedAndPostWorkout() {
        var intake = MealPlanIntake.default
        intake.breakfastSkipped = true
        intake.postWorkoutMandatory = true
        let (_, prompt) = MealPlanPrompts.weeklyPlanPrompt(
            targets: [:], restrictions: restrictions, preferences: "", intake: intake
        )
        XCTAssertTrue(prompt.contains("do NOT emit mealNumber 1"))
        XCTAssertTrue(prompt.contains("POST-TRAINING MEAL REQUIRED"))
        XCTAssertTrue(prompt.contains("SKIPS BREAKFAST"))
    }

    func testPrompt_defaultIntakeHasNoPatternOverrides() {
        XCTAssertEqual(MealPlanPrompts.eatingPatternDirective(.default), "")
        XCTAssertEqual(MealPlanPrompts.eatingPatternDirective(nil), "")
    }

    func testEatingWindowPrompt_overridesPerMealWindows() {
        XCTAssertTrue(EatingWindow(firstMealHour: 12, lastMealHour: 20).formattedForPrompt.contains("OVERRIDE"))
    }

    // MARK: - Deterministic enforcement

    func testEnforcer_dropsBreakfastAndClampsTimes() {
        let slots: [MealPlanScheduleEnforcer.Slot] = [
            .init(mealNumber: 1, scheduledTime: "08:00"),
            .init(mealNumber: 2, scheduledTime: "11:00"),
            .init(mealNumber: 4, scheduledTime: "16:00"),
            .init(mealNumber: 3, scheduledTime: "21:30"),
        ]
        let kept = MealPlanScheduleEnforcer.enforce(
            slots, window: EatingWindow(firstMealHour: 12, lastMealHour: 20), breakfastSkipped: true
        )
        XCTAssertEqual(kept.map(\.index), [1, 2, 3])
        XCTAssertEqual(kept.map(\.scheduledTime), ["12:00", "16:00", "20:00"])
    }

    func testEnforcer_keepsBreakfastWhenNotSkipped() {
        let kept = MealPlanScheduleEnforcer.enforce(
            [.init(mealNumber: 1, scheduledTime: "07:30")],
            window: EatingWindow(firstMealHour: 7, lastMealHour: 21), breakfastSkipped: false
        )
        XCTAssertEqual(kept.first?.scheduledTime, "07:30")
    }

    func testEnforcer_neverEmptiesADay() {
        let kept = MealPlanScheduleEnforcer.enforce(
            [.init(mealNumber: 1, scheduledTime: "13:00")],
            window: EatingWindow(firstMealHour: 12, lastMealHour: 20), breakfastSkipped: true
        )
        XCTAssertEqual(kept.count, 1, "A breakfast-only day keeps its meal rather than losing all food")
    }

    func testWindowClamp_malformedPassesThrough() {
        XCTAssertEqual(EatingWindow(firstMealHour: 12, lastMealHour: 20).clamp("noon"), "noon")
    }

    // MARK: - Observed meal times honor the window

    func testObservedTimes_clampedToWindow_andBreakfastOmitted() throws {
        let container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, UserSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = MealPlanGeneratorService(apiClient: APIClient())
        let result = service.observedMealTimes(
            modelContext: container.mainContext,
            wakeMinutesOverride: 7 * 60,
            eatingWindow: EatingWindow(firstMealHour: 12, lastMealHour: 19),
            breakfastSkipped: true
        )
        XCTAssertNil(result?[1], "No breakfast anchor for breakfast-skippers")
        XCTAssertEqual(result?[2], "12:00", "Lunch wake+5h = 12:00 sits on the window start")
        XCTAssertEqual(result?[3], "17:00", "Dinner wake+10h = 17:00")
        XCTAssertEqual(result?[4], "14:00", "Snack wake+7h = 14:00")

        let late = service.observedMealTimes(
            modelContext: container.mainContext,
            wakeMinutesOverride: 11 * 60,
            eatingWindow: EatingWindow(firstMealHour: 12, lastMealHour: 19)
        )
        XCTAssertEqual(late?[3], "19:00", "Dinner 20:30 cap → clamped to the 19:00 window end")
    }

    // MARK: - Receipt qty parsing

    func testReceiptQuantityParser_acceptsCommaAndDot() {
        XCTAssertEqual(ReceiptQuantityParser.parse("1,5"), 1.5)
        XCTAssertEqual(ReceiptQuantityParser.parse("1.5"), 1.5)
        XCTAssertEqual(ReceiptQuantityParser.parse(" 2 "), 2)
    }

    func testReceiptQuantityParser_rejectsGarbage() {
        XCTAssertNil(ReceiptQuantityParser.parse(""))
        XCTAssertNil(ReceiptQuantityParser.parse("abc"))
        XCTAssertNil(ReceiptQuantityParser.parse("-1"))
    }

    func testReceiptQuantityParser_format() {
        XCTAssertEqual(ReceiptQuantityParser.format(2), "2")
        XCTAssertEqual(ReceiptQuantityParser.format(0.25), "0.25")
        XCTAssertEqual(ReceiptQuantityParser.format(1.5), "1.5")
        XCTAssertEqual(ReceiptQuantityParser.format(2.995), "3", "Never a dangling decimal point")
    }

    // MARK: - Reminders export formatting

    func testReminderTitle_keepsFractions() {
        XCTAssertEqual(LocalGroceryListService.reminderTitle(name: "Oats", quantity: 1.5, unit: .kilograms), "Oats — 1.5kg")
        XCTAssertEqual(LocalGroceryListService.reminderTitle(name: "Rice", quantity: 0.5, unit: .pounds), "Rice — 0.5lb")
        XCTAssertEqual(LocalGroceryListService.reminderTitle(name: "Eggs", quantity: 12, unit: .pieces), "Eggs — 12pcs")
    }
}
