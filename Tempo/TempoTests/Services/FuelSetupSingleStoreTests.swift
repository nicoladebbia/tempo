//
// FuelSetupSingleStoreTests.swift
// Tempo
//
// Round 3 "one setup + 3 weekly questions": Fuel setup is the only home for
// permanent answers, the plan wizard asks only this week's questions.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class FuelSetupSingleStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
        context.insert(UserSettings())
        try context.save()
    }

    private var settings: UserSettings {
        MealPlanGeneratorService.fetchUserSettings(modelContext: context)!
    }

    // MARK: - Eating window: one writer, one value

    func testFuelSetupWindowIsTheWindowThePlannerUses() throws {
        var draft = FuelSetupDraft()
        draft.eatingWindowStartMinutes = 11 * 60 + 30
        draft.eatingWindowEndMinutes = 19 * 60 + 45
        draft.save(to: context)

        let daily = try XCTUnwrap(UserDailyPlanProfile.current(in: context))
        let planner = MealPlanIntake.seeded(settings: settings, dailyPlan: daily).eatingWindow
        XCTAssertEqual(planner, EatingWindow(firstMealHour: 12, lastMealHour: 19))

        let reloaded = FuelSetupDraft.load(from: context)
        let shown = EatingWindow(
            firstMealHour: Int((Double(try XCTUnwrap(reloaded.eatingWindowStartMinutes)) / 60).rounded(.up)),
            lastMealHour: try XCTUnwrap(reloaded.eatingWindowEndMinutes) / 60
        )
        XCTAssertEqual(shown, planner, "Fuel setup shows what the planner uses")
        XCTAssertEqual(MealPlanIntake.loadPersisted(from: settings).eatingWindow, planner)
    }

    func testStaleOnboardingWindowNeverBeatsTheSavedOne() throws {
        // Planner hours saved (10-22) while onboarding minutes still say 8-20.
        let daily = UserDailyPlanProfile(eatingWindowStartMinutes: 8 * 60, eatingWindowEndMinutes: 20 * 60)
        context.insert(daily)
        settings.mealIntakeFirstMealHour = 10
        settings.mealIntakeLastMealHour = 22
        try context.save()
        let draft = FuelSetupDraft.load(from: context)
        XCTAssertEqual(draft.eatingWindowStartMinutes, 10 * 60)
        XCTAssertEqual(draft.eatingWindowEndMinutes, 22 * 60)
    }

    // MARK: - This week's answers stay this week's

    func testWizardAnswersDoNotReachNextWeekOrPermanentFields() {
        let now = Date()
        var intake = MealPlanIntake.default
        intake.cookableDaysThisWeek = 1
        intake.temporaryExclusions = ["tofu"]
        intake.recoveryAdjusted = true
        intake.persist(to: settings, now: now)

        let thisWeek = MealPlanIntake.loadPersisted(from: settings, now: now)
        XCTAssertEqual(thisWeek.cookableDaysThisWeek, 1)
        XCTAssertEqual(thisWeek.temporaryExclusions, ["tofu"])

        let next = MealPlanIntake.loadPersisted(from: settings, now: now.addingTimeInterval(8 * 86400))
        XCTAssertEqual(next.cookableDaysThisWeek, MealPlanIntake.default.cookableDaysThisWeek)
        XCTAssertTrue(next.temporaryExclusions.isEmpty)
        XCTAssertFalse(next.recoveryAdjusted)
        XCTAssertNil(settings.mealIntakeCookableDays)
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "")
        XCTAssertFalse(settings.mealIntakeRecoveryAdjusted)
    }

    // MARK: - One "won't eat" list

    func testLegacyExclusionsMergeIntoDislikedFoodsWithoutLoss() {
        let profile = DietaryProfile()
        profile.dislikedFoods = ["broccoli", "olives"]
        settings.mealIntakeExclusionsRaw = "Broccoli, shellfish , "
        context.insert(profile)

        XCTAssertTrue(MealPlanIntake.migrateLegacyExclusions(settings: settings, profile: profile))
        XCTAssertEqual(profile.dislikedFoods, ["broccoli", "olives", "shellfish"])
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "")
        XCTAssertFalse(MealPlanIntake.migrateLegacyExclusions(settings: settings, profile: profile), "Idempotent")
    }

    func testLegacyExclusionsWaitForAProfileInsteadOfBeingDropped() {
        settings.mealIntakeExclusionsRaw = "shellfish"
        XCTAssertFalse(MealPlanIntake.migrateLegacyExclusions(settings: settings, profile: nil))
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "shellfish")
    }

    func testFuelSetupLoadMigratesAndSaveKeepsOneList() throws {
        let profile = DietaryProfile()
        profile.dislikedFoods = ["olives"]
        context.insert(profile)
        settings.mealIntakeExclusionsRaw = "shellfish"
        try context.save()

        var draft = FuelSetupDraft.load(from: context)
        XCTAssertEqual(draft.dislikedFoods, ["olives", "shellfish"])
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "")
        draft.dislikedFoods.append("tofu")
        draft.save(to: context)
        XCTAssertEqual(profile.dislikedFoods, ["olives", "shellfish", "tofu"])
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "")
    }

    // MARK: - Moved into Fuel setup

    func testKitchenRecoveryBoredAndClearSkinRoundTrip() throws {
        let key = ClearSkinFocusSetting.key
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        var draft = FuelSetupDraft.load(from: context)
        XCTAssertEqual(draft.equipment[KitchenApplianceKind.oven.rawValue], true, "Seeded defaults show before any row exists")
        XCTAssertEqual(draft.equipment[KitchenApplianceKind.airFryer.rawValue], false)

        draft.equipment[KitchenApplianceKind.airFryer.rawValue] = true
        draft.equipment[KitchenApplianceKind.oven.rawValue] = false
        draft.recoveryAdjusted = true
        draft.boredOfFoods = ["chicken"]
        draft.clearSkinFocus = true
        // A profile needs real body and goal answers to exist.
        draft.weightKg = 80
        draft.heightCm = 180
        draft.age = 30
        draft.sex = .male
        draft.goal = .maintain
        draft.save(to: context)

        let again = FuelSetupDraft.load(from: context)
        XCTAssertEqual(again.equipment[KitchenApplianceKind.airFryer.rawValue], true)
        XCTAssertEqual(again.equipment[KitchenApplianceKind.oven.rawValue], false)
        XCTAssertTrue(again.recoveryAdjusted)
        XCTAssertEqual(again.boredOfFoods, ["chicken"])
        XCTAssertTrue(again.clearSkinFocus)
        XCTAssertTrue(settings.mealIntakeRecoveryAdjusted)
        let rows = try context.fetch(FetchDescriptor<KitchenEquipment>())
        XCTAssertEqual(rows.count, KitchenApplianceKind.allCases.count)
    }

    func testAIAdoptionKeepsTheFieldsTheWireCannotCarry() {
        var current = FuelSetupDraft()
        current.boredOfFoods = ["chicken"]
        current.clearSkinFocus = true
        current.recoveryAdjusted = true
        current.equipment = ["oven": false]
        let adopted = current.adopting(FuelSetupDraft(), returnedDays: [])
        XCTAssertEqual(adopted.boredOfFoods, ["chicken"])
        XCTAssertTrue(adopted.clearSkinFocus)
        XCTAssertTrue(adopted.recoveryAdjusted)
        XCTAssertEqual(adopted.equipment, ["oven": false])
    }

    // MARK: - Wizard = 3 questions

    func testWizardAsksOnlyThisWeeksThreeQuestions() {
        let pantry = PantrySnapshot(itemCount: 0, mostRecentUpdate: nil)
        let noWhoop = WizardLaunchSnapshot(pantry: pantry, whoop: nil)
        XCTAssertEqual(
            WizardCoordinator.computeVisibleSteps(snapshot: noWhoop, intake: .default),
            [.cookingCapacity, .temporaryExclusions, .review]
        )
        let whoop = WizardLaunchSnapshot(pantry: pantry, whoop: WhoopSnapshot(recoveryScore: 60))
        XCTAssertEqual(
            WizardCoordinator.computeVisibleSteps(snapshot: whoop, intake: .default),
            [.cookingCapacity, .temporaryExclusions, .recoveryOverride, .review]
        )
        XCTAssertEqual(WizardStep.allCases.count, 4)
    }

    // MARK: - Round 3 review fixes

    func testFuelSetupSaveKeepsThisWeeksExclusionsAndOnlyClearsSupersededTemps() {
        let week = WeeklyPlanService.currentWeekStart(for: Date())
        settings.mealIntakeCookableDays = 4
        settings.mealIntakeTempWeekStart = week
        settings.mealIntakeTempCookableDays = 2
        settings.mealIntakeTempExclusionsRaw = "fish"
        settings.mealIntakeTempRecoveryAdjusted = true

        var draft = FuelSetupDraft()
        draft.cookableDaysPerWeek = 4 // unchanged -> temp days stay
        draft.recoveryAdjusted = false // permanent was false -> unchanged
        draft.save(to: context)
        var intake = MealPlanIntake.loadPersisted(from: settings)
        XCTAssertEqual(intake.cookableDaysThisWeek, 2)
        XCTAssertTrue(intake.recoveryAdjusted)
        XCTAssertEqual(intake.temporaryExclusions, ["fish"])

        draft.cookableDaysPerWeek = 6 // changed -> temp days superseded
        draft.recoveryAdjusted = true
        draft.save(to: context)
        intake = MealPlanIntake.loadPersisted(from: settings)
        XCTAssertEqual(intake.cookableDaysThisWeek, 6)
        XCTAssertTrue(intake.recoveryAdjusted)
        XCTAssertEqual(intake.temporaryExclusions, ["fish"], "Exclusions for this week survive")
    }

    func testPermanentRecoveryChangeBeatsStaleTempWithoutCookableDays() {
        settings.mealIntakeTempWeekStart = WeeklyPlanService.currentWeekStart(for: Date())
        settings.mealIntakeTempRecoveryAdjusted = true
        settings.mealIntakeRecoveryAdjusted = true

        var draft = FuelSetupDraft()
        draft.cookableDaysPerWeek = nil
        draft.recoveryAdjusted = false
        draft.save(to: context)
        XCTAssertFalse(MealPlanIntake.loadPersisted(from: settings).recoveryAdjusted)
    }

    func testLegacyExclusionsSeedDraftWithoutProfileAndSurviveSave() throws {
        settings.mealIntakeExclusionsRaw = "shellfish, olives"
        try context.save()
        var draft = FuelSetupDraft.load(from: context)
        XCTAssertEqual(draft.dislikedFoods, ["shellfish", "olives"])
        // Without body and goal no profile is made up: the legacy list stays put.
        draft.save(to: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DietaryProfile>()).isEmpty)
        XCTAssertEqual(settings.mealIntakeExclusionsRaw, "shellfish, olives")
        draft.weightKg = 80
        draft.heightCm = 180
        draft.age = 30
        draft.sex = .male
        draft.goal = .maintain
        draft.save(to: context)
        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<DietaryProfile>()).first)
        XCTAssertEqual(profile.dislikedFoods, ["shellfish", "olives"])
    }

    func testSetupFlagsOnlyContributeWhenNonDefault() {
        XCTAssertTrue(MealPlanInputsFingerprint.setupFlagFields(settings: settings, equipment: [], clearSkinFocus: false).isEmpty)
        let seededOnly = KitchenEquipment.seededSet()
        XCTAssertTrue(MealPlanInputsFingerprint.setupFlagFields(settings: settings, equipment: seededOnly, clearSkinFocus: false).isEmpty)

        let flipped = KitchenEquipment.seededSet()
        flipped[0].isAvailable.toggle()
        let base = MealPlanInputsFingerprint.setupFlagFields(settings: settings, equipment: flipped, clearSkinFocus: false)
        XCTAssertEqual(base.count, 1, "Equipment change is tracked")
        XCTAssertEqual(MealPlanInputsFingerprint.setupFlagFields(settings: settings, equipment: [], clearSkinFocus: true), ["clearSkinFocus=true"])
        settings.mealIntakeRecoveryAdjusted = true
        XCTAssertEqual(MealPlanInputsFingerprint.setupFlagFields(settings: settings, equipment: [], clearSkinFocus: false), ["recoveryAdjusted=true"])
    }
}
