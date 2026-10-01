//
// PlanTrustFixesTests.swift
// Tempo
//
// Round 1 "trust the numbers", plan side: setup changes ask instead of
// rebuilding, Pro / AI-consent errors say so, the wizard's this-week answers
// expire with the week, the eating window has one source of truth, recipe
// calls survive a 429, and protein is solved on the on-device fallback.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PlanTrustFixesTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: NutritionTabViewModel.dismissedUpdateKey)
    }

    override func tearDown() async throws {
        container = nil
        UserDefaults.standard.removeObject(forKey: NutritionTabViewModel.dismissedUpdateKey)
        try await super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return container.mainContext
    }

    // MARK: - 3. Banner instead of auto-regenerate

    func testSetupChangeShowsBannerAndNeverRebuilds() throws {
        let ctx = try makeContext()
        let profile = DietaryProfile()
        ctx.insert(profile)
        let today = Calendar.current.startOfDay(for: Date())
        let plan = try WeeklyMealPlan(
            startDate: XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today)),
            endDate: XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: today))
        )
        ctx.insert(plan)
        let meal = PlannedMeal(dayDate: today, mealNumber: 1, mealName: "Breakfast", totalCalories: 500, mealPlan: plan)
        ctx.insert(meal)
        try ctx.save()
        let vm = NutritionTabViewModel()
        vm.loadToday(modelContext: ctx)
        XCTAssertFalse(vm.showPlanUpdateBanner)

        profile.dislikedFoods = ["broccoli"]
        try ctx.save()
        vm.checkPlanFreshness(modelContext: ctx)

        XCTAssertTrue(vm.isPlanOutOfDate)
        XCTAssertTrue(vm.showPlanUpdateBanner, "Setup changed → ask")
        XCTAssertFalse(vm.isGeneratingPlan, "…and never rebuild behind the user's back")
        XCTAssertEqual(plan.meals?.map(\.id), [meal.id], "The plan itself is untouched")
    }

    func testNotNowHidesBannerUntilInputsChangeAgain() throws {
        let ctx = try makeContext()
        let profile = DietaryProfile()
        ctx.insert(profile)
        let today = Calendar.current.startOfDay(for: Date())
        let plan = WeeklyMealPlan(startDate: today, endDate: today.addingTimeInterval(6 * 86400))
        ctx.insert(plan)
        try ctx.save()
        let vm = NutritionTabViewModel()
        vm.loadToday(modelContext: ctx)

        profile.dislikedFoods = ["broccoli"]
        try ctx.save()
        vm.checkPlanFreshness(modelContext: ctx)
        XCTAssertTrue(vm.showPlanUpdateBanner)

        vm.dismissPlanUpdateBanner()
        XCTAssertFalse(vm.showPlanUpdateBanner)
        vm.checkPlanFreshness(modelContext: ctx)
        XCTAssertFalse(vm.showPlanUpdateBanner, "Still the same change → stays hidden")
        XCTAssertTrue(vm.isPlanOutOfDate, "The plan IS still out of date (Plan tab header says so)")

        profile.dislikedFoods = ["broccoli", "tofu"]
        try ctx.save()
        vm.checkPlanFreshness(modelContext: ctx)
        XCTAssertTrue(vm.showPlanUpdateBanner, "A new change brings it back")
    }

    // MARK: - 4. Pro / consent errors

    func testBlockerMapsEntitlementAndConsentErrors() {
        XCTAssertEqual(PlanGenerationBlocker(APIError.subscriptionRequired), .proRequired)
        XCTAssertEqual(PlanGenerationBlocker(APIError.aiConsentRequired), .aiConsentRequired)
        XCTAssertEqual(
            PlanGenerationBlocker(MealPlanGeneratorError.generationFailed(APIError.subscriptionRequired)),
            .proRequired
        )
        XCTAssertEqual(
            PlanGenerationBlocker(WeeklyPlanService.BuildError.server("subscription_required")),
            .proRequired
        )
        XCTAssertEqual(
            PlanGenerationBlocker(WeeklyPlanService.BuildError.server("ai_consent_required")),
            .aiConsentRequired
        )
        XCTAssertNil(PlanGenerationBlocker(APIError.serverError(statusCode: 500)))
        XCTAssertNil(PlanGenerationBlocker(WeeklyPlanService.BuildError.server("ai_failed")))
        XCTAssertNil(PlanGenerationBlocker(WeeklyPlanService.BuildError.timedOut))
    }

    func testErrorDescriptionsNoLongerSayGenericFailure() {
        let pro = MealPlanGeneratorError.generationFailed(APIError.subscriptionRequired)
        XCTAssertEqual(pro.errorDescription, "Weekly plans are a Tempo Pro feature.")
        let consent = MealPlanGeneratorError.generationFailed(APIError.aiConsentRequired)
        XCTAssertEqual(consent.errorDescription, "Turn on AI features to build your plan.")
        XCTAssertEqual(
            PlanGenerationBlocker.message(for: WeeklyPlanService.BuildError.server("subscription_required")),
            "Weekly plans are a Tempo Pro feature."
        )
        XCTAssertEqual(WeeklyCheckInView.message(for: APIError.subscriptionRequired), PlanGenerationBlocker.proRequired.message)
    }

    // MARK: - 5. Temporary answers

    private func intake(cook: Int, exclusions: [String], recovery: Bool) -> MealPlanIntake {
        MealPlanIntake(
            cookableDaysThisWeek: cook, leftoverTolerance: .freshDaily,
            eatingWindow: EatingWindow(firstMealHour: 9, lastMealHour: 21),
            groceryIntent: nil, recoveryAdjusted: recovery,
            temporaryExclusions: exclusions, trainingSchedule: nil
        )
    }

    func testWizardAnswersApplyThisWeekOnlyAndNeverOverwriteSavedPrefs() {
        let settings = UserSettings()
        settings.mealIntakeCookableDays = 5
        settings.mealIntakeExclusionsRaw = "shellfish"
        let now = Date()

        intake(cook: 2, exclusions: ["fish"], recovery: true).persist(to: settings, now: now)

        XCTAssertEqual(settings.mealIntakeCookableDays, 5, "Saved pref untouched")
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "shellfish", "Saved pref untouched")
        XCTAssertFalse(settings.mealIntakeRecoveryAdjusted)
        let thisWeek = MealPlanIntake.loadPersisted(from: settings, now: now)
        XCTAssertEqual(thisWeek.cookableDaysThisWeek, 2)
        XCTAssertEqual(thisWeek.temporaryExclusions, ["fish"])
        XCTAssertTrue(thisWeek.recoveryAdjusted)
        // Mid-week rebuilds keep them.
        let sameWeek = Calendar.current.isDate(
            WeeklyPlanService.currentWeekStart(for: now),
            inSameDayAs: WeeklyPlanService.currentWeekStart(for: now.addingTimeInterval(3600))
        )
        XCTAssertTrue(sameWeek)
        XCTAssertEqual(MealPlanIntake.loadPersisted(from: settings, now: now.addingTimeInterval(3600)).cookableDaysThisWeek, 2)
        // Next week they're gone and the saved prefs are back.
        let nextWeek = MealPlanIntake.loadPersisted(from: settings, now: now.addingTimeInterval(8 * 86400))
        XCTAssertEqual(nextWeek.cookableDaysThisWeek, 5)
        XCTAssertEqual(nextWeek.temporaryExclusions, ["shellfish"])
        XCTAssertFalse(nextWeek.recoveryAdjusted)
        // Durable answers did stick.
        XCTAssertEqual(nextWeek.leftoverTolerance, .freshDaily)
        XCTAssertEqual(nextWeek.eatingWindow, EatingWindow(firstMealHour: 9, lastMealHour: 21))
    }

    // MARK: - 6. One eating window

    func testSavingTheWindowWritesThroughToOnboardingProfile() {
        let settings = UserSettings()
        let daily = UserDailyPlanProfile(eatingWindowStartMinutes: 8 * 60, eatingWindowEndMinutes: 20 * 60)

        MealPlanIntake.saveEatingWindow(EatingWindow(firstMealHour: 10, lastMealHour: 22), settings: settings, dailyPlan: daily)

        XCTAssertEqual(settings.mealIntakeFirstMealHour, 10)
        XCTAssertEqual(settings.mealIntakeLastMealHour, 22)
        XCTAssertEqual(daily.eatingWindowStartMinutes, 600)
        XCTAssertEqual(daily.eatingWindowEndMinutes, 22 * 60)
        // Planner and editor now agree.
        let planner = MealPlanIntake.seeded(settings: settings, dailyPlan: daily).eatingWindow
        XCTAssertEqual(planner, EatingWindow(firstMealHour: 10, lastMealHour: 22))
        XCTAssertEqual(MealPlanIntake.eatingWindow(fromOnboarding: daily), planner)
    }

    func testUnchangedWindowKeepsMinutePrecision() {
        let settings = UserSettings()
        let daily = UserDailyPlanProfile(eatingWindowStartMinutes: 11 * 60 + 30, eatingWindowEndMinutes: 19 * 60 + 45)
        // 11:30–19:45 rounds (up / down) to 12–19.
        MealPlanIntake.saveEatingWindow(EatingWindow(firstMealHour: 12, lastMealHour: 19), settings: settings, dailyPlan: daily)
        XCTAssertEqual(daily.eatingWindowStartMinutes, 11 * 60 + 30)
        XCTAssertEqual(daily.eatingWindowEndMinutes, 19 * 60 + 45)
    }

    func testWizardPersistWritesWindowThroughToo() {
        let settings = UserSettings()
        let daily = UserDailyPlanProfile()
        intake(cook: 3, exclusions: [], recovery: false).persist(to: settings, dailyPlan: daily)
        XCTAssertEqual(daily.eatingWindowStartMinutes, 9 * 60)
        XCTAssertEqual(daily.eatingWindowEndMinutes, 21 * 60)
    }

    // MARK: - 7. Recipe backoff

    func testRateLimitedRecipesRetryWithBackoffThenGiveUp() {
        let limited = APIError.rateLimited(retryAfter: nil)
        XCTAssertEqual(MealPlanGeneratorService.recipeRetryDelay(after: limited, attempt: 0), 4)
        XCTAssertEqual(MealPlanGeneratorService.recipeRetryDelay(after: limited, attempt: 1), 8)
        XCTAssertEqual(MealPlanGeneratorService.recipeRetryDelay(after: APIError.rateLimited(retryAfter: 20), attempt: 0), 20)
        XCTAssertNil(MealPlanGeneratorService.recipeRetryDelay(after: limited, attempt: MealPlanGeneratorService.recipeMaxRetries))
        XCTAssertNil(MealPlanGeneratorService.recipeRetryDelay(after: APIError.serverError(statusCode: 500), attempt: 0))
        XCTAssertNil(MealPlanGeneratorService.recipeRetryDelay(after: APIError.subscriptionRequired, attempt: 0))
        XCTAssertLessThanOrEqual(MealPlanGeneratorService.recipeConcurrency, 3)
    }

    // MARK: - 8. Protein on the on-device fallback

    func testScaleFactorsTradeProteinRichFoodsForTheRest() {
        // 2000 kcal day: chicken-type 800 kcal / 160 g protein, rice-type 1200 kcal / 30 g.
        // Target 2000 kcal / 220 g protein (uniform scaling would leave 190 g).
        let f = MealPlanGeneratorService.scaleFactors(
            proteinRich: (800, 160), other: (1200, 30),
            targetCalories: 2000, targetProtein: 220
        )
        let protein = f.rich * 160 + f.other * 30
        let calories = f.rich * 800 + f.other * 1200
        XCTAssertEqual(calories, 2000, accuracy: 5)
        XCTAssertGreaterThan(f.rich, f.other, "Protein-rich foods grow, the rest shrink")
        XCTAssertEqual(protein, 220, accuracy: 12)
    }

    func testScaleFactorsFallBackToUniformWhenProteinAlreadyClose() {
        let f = MealPlanGeneratorService.scaleFactors(
            proteinRich: (800, 160), other: (1200, 30),
            targetCalories: 2200, targetProtein: 209
        )
        XCTAssertEqual(f.rich, f.other, accuracy: 0.0001)
        XCTAssertEqual(f.rich, 1.1, accuracy: 0.0001)
    }
}
