//
// FuelSetupSectionTests.swift
// Tempo
//
// The sectioned "Edit setup": card summaries, Apple Health read-only rules,
// which screens each flow shows, and that a per-section save writes only its
// own fields (through the same stores) and announces the change once.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class FuelSetupSectionTests: XCTestCase {
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

    private var profile: DietaryProfile? {
        (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first
    }

    private func fullDraft() -> FuelSetupDraft {
        var draft = FuelSetupDraft()
        draft.weightKg = 80
        draft.heightCm = 180
        draft.age = 25
        draft.sex = .male
        draft.goal = .leanGain
        draft.goalWeightKg = 85
        draft.weeklyRateKg = 0.25
        draft.trainingDaysPerWeek = 4
        draft.mealsPerDay = 4
        draft.allergies = ["Peanuts"]
        draft.dislikedFoods = ["Olives"]
        draft.cookMinutesWeekday = 30
        draft.cookableDaysPerWeek = 4
        draft.weeklyBudgetUSD = 90
        draft.stores = ["Aldi"]
        draft.routine[1].wakeMinutes = 7 * 60
        return draft
    }

    // MARK: - Summaries

    func testSummariesAreOneLine() {
        let draft = fullDraft()
        XCTAssertEqual(draft.summary(for: .you), "80 kg · 180 cm · 25 yrs · Male")
        XCTAssertEqual(draft.summary(for: .goal), "Lean Gain · to 85 kg · 4 training days")
        XCTAssertEqual(draft.summary(for: .shopping), "$90/week · Aldi")
        XCTAssertEqual(draft.summary(for: .food), "1 allergy · 1 won't eat")
        XCTAssertEqual(draft.summary(for: .recovery), "Same meals every day")
    }

    func testSummaryUsesTheUsersUnit() {
        var draft = FuelSetupDraft()
        draft.weightKg = 80
        XCTAssertEqual(draft.summary(for: .you, unit: .lbs), "176 lbs")
    }

    func testEmptyRequiredSectionsReadNotSet() {
        let draft = FuelSetupDraft()
        for section in [FuelSetupSection.you, .goal, .meals] {
            XCTAssertEqual(draft.summary(for: section), "Not set", "\(section)")
        }
    }

    func testEmptyOptionalSectionsReadSensibleDefaults() {
        let draft = FuelSetupDraft()
        for section in [FuelSetupSection.week, .food, .cooking, .shopping] {
            XCTAssertEqual(draft.summary(for: section), "Not set — we'll use sensible defaults", "\(section)")
        }
    }

    func testMealsSummaryShowsWindowAndBreakfast() {
        var draft = FuelSetupDraft()
        draft.mealsPerDay = 3
        draft.breakfastSkipped = true
        draft.eatingWindowStartMinutes = 12 * 60
        draft.eatingWindowEndMinutes = 20 * 60
        XCTAssertEqual(draft.summary(for: .meals), "3 meals · no breakfast · 12:00–20:00")
        XCTAssertEqual(draft.mealSpacingText, "About every 4 h")
    }

    // MARK: - Missing / dirty

    func testMissingFieldsAreAttributedToTheirSection() {
        let draft = FuelSetupDraft()
        XCTAssertEqual(Set(draft.missingFields(in: .you)), [.weight, .height, .age, .sex])
        XCTAssertEqual(draft.missingFields(in: .goal), [.goal])
        XCTAssertEqual(draft.missingFields(in: .meals), [.meals])
        XCTAssertTrue(draft.missingFields(in: .week).isEmpty, "the week is optional")
        XCTAssertTrue(draft.missingFields(in: .food).isEmpty)
        XCTAssertEqual(draft.incompleteSections, [.you, .goal, .meals])
        XCTAssertTrue(fullDraft().incompleteSections.isEmpty)
    }

    func testDirtyOnlyForTheSectionThatChanged() {
        let saved = fullDraft()
        var edited = saved
        edited.allergies.append("Shellfish")
        XCTAssertTrue(edited.isDirty(.food, comparedTo: saved))
        for section in FuelSetupSection.allCases where section != .food {
            XCTAssertFalse(edited.isDirty(section, comparedTo: saved), "\(section)")
        }
    }

    func testCopyTouchesOnlyThatSection() {
        var base = fullDraft()
        var other = fullDraft()
        other.weightKg = 70
        other.allergies = ["Eggs"]
        base.copy(.food, from: other)
        XCTAssertEqual(base.allergies, ["Eggs"])
        XCTAssertEqual(base.weightKg, 80)
    }

    // MARK: - Health

    func testHealthValuesLockAndOnlyMissingOnesAreAsked() {
        var draft = FuelSetupDraft()
        draft.weightKg = 70 // typed earlier
        let locked = draft.apply(health: HealthBodyStats(weightKg: 82.4, heightCm: 181, age: 24))
        XCTAssertEqual(locked, [.weight, .height, .age])
        XCTAssertEqual(draft.weightKg, 82.4, "Health wins over a typed value")
        XCTAssertNil(draft.sex)
        let steps = FuelFlowStep.steps(for: .you, draft: draft, locked: locked)
        XCTAssertEqual(steps, [.healthBody, .sex, .bodyFat])
        XCTAssertFalse(steps.contains(.bodyStats), "weight, height and age all come from Health")
    }

    func testEverythingFromHealthIsOneReadOnlyScreen() {
        var draft = FuelSetupDraft()
        let locked = draft.apply(health: HealthBodyStats(weightKg: 80, heightCm: 180, bodyFatPercent: 15, age: 30, sex: .female))
        XCTAssertEqual(locked.count, 5)
        XCTAssertEqual(FuelFlowStep.steps(for: .you, draft: draft, locked: locked), [.healthBody])
    }

    func testNoHealthDataAsksEverything() {
        var draft = FuelSetupDraft()
        let locked = draft.apply(health: HealthBodyStats())
        XCTAssertTrue(locked.isEmpty)
        XCTAssertEqual(FuelFlowStep.steps(for: .you, draft: draft, locked: locked), [.bodyStats, .sex, .bodyFat])
    }

    func testBogusHealthValuesAreIgnored() {
        var draft = FuelSetupDraft()
        let locked = draft.apply(health: HealthBodyStats(weightKg: 0, heightCm: -3, bodyFatPercent: 140))
        XCTAssertTrue(locked.isEmpty)
        XCTAssertNil(draft.weightKg)
    }

    // MARK: - Flow steps

    func testMaintainSkipsTheTargetScreen() {
        var draft = FuelSetupDraft()
        draft.goal = .maintain
        XCTAssertEqual(FuelFlowStep.steps(for: .goal, draft: draft), [.goal, .trainingDays])
        draft.goal = .cut
        XCTAssertEqual(FuelFlowStep.steps(for: .goal, draft: draft), [.goal, .goalTarget, .trainingDays])
    }

    func testEatingWindowValidation() {
        var draft = FuelSetupDraft()
        XCTAssertTrue(FuelFlowStep.window.isValid(in: draft))
        draft.eatingWindowStartMinutes = 20 * 60
        draft.eatingWindowEndMinutes = 8 * 60
        XCTAssertFalse(FuelFlowStep.window.isValid(in: draft))
        draft.eatingWindowEndMinutes = 22 * 60
        XCTAssertTrue(FuelFlowStep.window.isValid(in: draft))
        draft.eatingWindowEndMinutes = nil
        XCTAssertFalse(FuelFlowStep.window.isValid(in: draft))
    }

    func testWeightHeightAgeShareOneScreenAndValidateTogether() {
        var draft = FuelSetupDraft()
        draft.weightKg = 80
        draft.heightCm = 180
        XCTAssertFalse(FuelFlowStep.bodyStats.isValid(in: draft), "age still missing")
        draft.age = 30
        XCTAssertTrue(FuelFlowStep.bodyStats.isValid(in: draft))
        XCTAssertTrue(FuelFlowStep.bodyStats.isValid(in: FuelSetupDraft(), locked: [.weight, .height, .age]), "Health supplies all three")
    }

    func testRelatedQuestionsAreGroupedPerScreen() {
        let draft = FuelSetupDraft()
        XCTAssertEqual(FuelFlowStep.steps(for: .meals, draft: draft), [.meals, .window])
        XCTAssertEqual(FuelFlowStep.steps(for: .cooking, draft: draft), [.skill, .cookTimes, .leftovers, .equipment, .clearSkin])
        XCTAssertEqual(FuelFlowStep.steps(for: .shopping, draft: draft), [.shopping])
        XCTAssertEqual(FuelFlowStep.steps(for: .food, draft: draft), [.restrictions, .wontEat, .favourites, .tastes, .appetite])
    }

    // MARK: - Required vs optional

    func testOnlyYouGoalAndMealsAreRequired() {
        XCTAssertEqual(FuelSetupSection.required, [.you, .goal, .meals])
        for section in [FuelSetupSection.week, .food, .cooking, .shopping, .recovery] {
            XCTAssertFalse(section.isRequired, "\(section)")
        }
    }

    func testRequiredQuestionsCannotBeSkippedButOptionalOnesCan() {
        for step in [FuelFlowStep.bodyStats, .sex, .goal, .meals] {
            XCTAssertFalse(step.isOptional, "\(step)")
        }
        for step in [FuelFlowStep.bodyFat, .window, .trainingDays, .wontEat, .tastes, .appetite, .cookTimes, .shopping, .recovery, .notes] {
            XCTAssertTrue(step.isOptional, "\(step)")
            XCTAssertTrue(step.isValid(in: FuelSetupDraft()), "an optional screen never blocks: \(step)")
        }
    }

    func testRequiredMissingMessageNamesExactlyWhatIsMissing() {
        var draft = FuelSetupDraft()
        XCTAssertEqual(draft.requiredMissingMessage, "Finish You, Goal and Meals & eating window to build your plan.")
        draft.weightKg = 80
        draft.heightCm = 180
        draft.age = 30
        draft.sex = .male
        draft.mealsPerDay = 3
        XCTAssertEqual(draft.requiredMissingMessage, "Finish Goal to build your plan.")
        draft.goal = .maintain
        XCTAssertNil(draft.requiredMissingMessage, "optional sections never block")
        XCTAssertTrue(draft.isComplete)
    }

    func testRequiredStoreCheckBlocksOnlyOnRequiredSections() {
        XCTAssertNotNil(FuelSetupDraft.requiredMissingMessage(in: context), "no profile yet")
        let draft = fullDraft()
        draft.save(to: context)
        XCTAssertNil(FuelSetupDraft.requiredMissingMessage(in: context), "week, food, cooking, shopping were never asked")
    }

    // MARK: - Finish setup chain

    func testFinishChainListsRequiredFirstThenUnsetOptionalSections() {
        let draft = FuelSetupDraft()
        XCTAssertEqual(draft.remainingSections(), [.you, .goal, .meals, .week, .food, .cooking, .shopping])
        var body = fullDraft()
        XCTAssertEqual(body.remainingSections(), [.week, .food, .cooking, .shopping].filter { body.isUnset($0) })
        body.routine = .empty
        body.allergies = []
        body.dislikedFoods = []
        body.cookMinutesWeekday = nil
        body.cookableDaysPerWeek = nil
        body.weeklyBudgetUSD = nil
        body.stores = []
        XCTAssertEqual(body.remainingSections(), [.week, .food, .cooking, .shopping])
    }

    func testSkippedOrSavedOptionalSectionsLeaveTheChain() {
        var draft = FuelSetupDraft()
        draft.weightKg = 80
        draft.heightCm = 180
        draft.age = 30
        draft.sex = .male
        draft.goal = .cut
        draft.mealsPerDay = 4
        XCTAssertEqual(draft.remainingSections(), [.week, .food, .cooking, .shopping])
        XCTAssertEqual(draft.remainingSections(reviewed: [.food, .shopping]), [.week, .cooking])
        draft.favoriteCuisines = ["Italian"]
        XCTAssertFalse(draft.remainingSections().contains(.food), "an answered section is not left")
    }

    func testChainOrderAndEnd() {
        let chain: [FuelSetupSection] = [.you, .goal, .meals, .food]
        XCTAssertEqual(FuelSetupDraft.next(after: .you, in: chain), .goal)
        XCTAssertEqual(FuelSetupDraft.next(after: .meals, in: chain), .food)
        XCTAssertNil(FuelSetupDraft.next(after: .food, in: chain), "Done")
        XCTAssertNil(FuelSetupDraft.next(after: .week, in: chain), "not in the chain")
    }

    func testReviewedSectionsPersistOnTheDevice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "fuel-progress-\(UUID().uuidString)"))
        XCTAssertTrue(FuelSetupProgress.reviewed(defaults: defaults).isEmpty)
        FuelSetupProgress.markReviewed(.food, defaults: defaults)
        FuelSetupProgress.markReviewed(.shopping, defaults: defaults)
        XCTAssertEqual(FuelSetupProgress.reviewed(defaults: defaults), [.food, .shopping])
    }

    // MARK: - Dirty after a talk-merge

    func testTalkMergeMarksEveryChangedSectionDirtyAndNothingElse() throws {
        let saved = fullDraft()
        let reply = """
        {"profile":{"weightKg":80,"heightCm":180,"age":25,"sex":"male","goal":"leanGain","goalWeightKg":85,"weeklyRateKg":0.25,\
        "trainingDaysPerWeek":4,"mealsPerDay":4,"allergies":["Peanuts"],"dislikedFoods":["Olives"],"favoriteFoods":["salmon"],\
        "favoriteCuisines":["Italian"],"spiceLevel":"hot","cookMinutesWeekday":30,"cookableDaysPerWeek":4,\
        "weeklyBudgetUSD":90,"stores":["Aldi"],"days":[{"day":"mon","wake":"07:00"}]},"followUps":[]}
        """
        let answer = try FuelSetupExtractor.parse(reply)
        let merged = saved.adopting(answer.draft, returnedDays: answer.returnedDays)
        XCTAssertTrue(merged.isDirty(.food, comparedTo: saved), "new favourites, cuisine and spice show Unsaved")
        for section in FuelSetupSection.allCases where section != .food {
            XCTAssertFalse(merged.isDirty(section, comparedTo: saved), "\(section)")
        }
        XCTAssertEqual(merged.favoriteCuisines, ["Italian"])
        XCTAssertEqual(merged.spiceLevel, .hot)
    }

    func testTalkMergeThatRemovesAnAnswerIsDirtyToo() throws {
        let saved = fullDraft()
        var withSpice = saved
        withSpice.spiceLevel = .mild
        let answer = try FuelSetupExtractor.parse(#"{"profile":{"spiceLevel":null},"followUps":[]}"#)
        let merged = withSpice.adopting(answer.draft, returnedDays: [])
        XCTAssertNil(merged.spiceLevel)
        XCTAssertTrue(merged.isDirty(.food, comparedTo: withSpice))
    }

    // MARK: - Personalisation fields

    func testPersonalisationSummaryShowsTheNewAnswers() {
        var draft = FuelSetupDraft()
        draft.favoriteCuisines = ["Italian", "Mexican", "Thai"]
        draft.spiceLevel = .hot
        draft.breakfastStyle = .savoury
        draft.snacksPerDay = 2
        draft.appetite = .big
        XCTAssertEqual(draft.summary(for: .food), "Italian, Mexican +1 · hot spice · savoury breakfasts · 2 snacks · big eater")
        draft.snacksPerDay = 0
        draft.appetite = .normal
        XCTAssertTrue(draft.summary(for: .food).contains("no snacks"))
        XCTAssertFalse(draft.summary(for: .food).contains("normal"), "normal appetite says nothing")
    }

    func testPersonalisationSavesToTheProfileAndLoadsBack() throws {
        var draft = fullDraft()
        draft.favoriteCuisines = ["Italian"]
        draft.spiceLevel = .medium
        draft.breakfastStyle = .quick
        draft.snacksPerDay = 1
        draft.appetite = .light
        draft.save(to: context)
        let stored = try XCTUnwrap(profile)
        XCTAssertEqual(stored.favoriteCuisines, ["Italian"])
        XCTAssertEqual(stored.spiceLevel, .medium)
        XCTAssertEqual(stored.breakfastStyle, .quick)
        XCTAssertEqual(stored.snacksPerDay, 1)
        XCTAssertEqual(stored.appetite, .light)
        let loaded = FuelSetupDraft.load(from: context)
        XCTAssertEqual(loaded.favoriteCuisines, ["Italian"])
        XCTAssertEqual(loaded.spiceLevel, .medium)
        XCTAssertEqual(loaded.appetite, .light)
        XCTAssertEqual(loaded.snacksPerDay, 1)
        draft.spiceLevel = nil
        draft.save(sections: [.food], to: context)
        XCTAssertNil(profile?.spiceLevel, "clearing a pill clears the stored answer")
    }

    func testPersonalisationReachesThePlanPromptAndOnlyWhenSet() throws {
        var draft = fullDraft()
        draft.favoriteCuisines = ["Italian", "Mexican"]
        draft.spiceLevel = .hot
        draft.breakfastStyle = .savoury
        draft.snacksPerDay = 0
        draft.appetite = .big
        draft.save(to: context)
        let restrictions = MealPlanPrompts.DietaryRestrictions(from: try XCTUnwrap(profile))
        let prompt = MealPlanPrompts.weeklyPlanPrompt(targets: [:], restrictions: restrictions, preferences: "").user
        XCTAssertTrue(prompt.contains("<taste_preferences>"))
        XCTAssertTrue(prompt.contains("FAVOURITE CUISINES"))
        XCTAssertTrue(prompt.contains("Italian, Mexican"))
        XCTAssertTrue(prompt.contains("SPICE: hot"))
        XCTAssertTrue(prompt.contains("BREAKFAST STYLE: savoury"))
        XCTAssertTrue(prompt.contains("SNACKS: none"))
        XCTAssertTrue(prompt.contains("PORTIONS: big eater"))

        let plain = MealPlanPrompts.weeklyPlanPrompt(targets: [:], restrictions: MealPlanPrompts.DietaryRestrictions(), preferences: "").user
        XCTAssertFalse(plain.contains("<taste_preferences>"), "nothing set, nothing said")
        XCTAssertEqual(MealPlanPrompts.DietaryRestrictions(appetite: .normal).tastePreferencesBlock, "")
    }

    func testPersonalisationChangesTheStalePlanFingerprint() {
        draftSaved()
        let before = MealPlanInputsFingerprint.current(in: context)
        profile?.spiceLevel = .hot
        XCTAssertNotEqual(MealPlanInputsFingerprint.current(in: context), before)
    }

    private func draftSaved() {
        fullDraft().save(to: context)
    }

    // MARK: - Per-section save

    func testSectionSaveWritesOnlyThatSection() throws {
        fullDraft().save(to: context)
        var edited = fullDraft()
        edited.allergies = ["Eggs"]
        edited.weightKg = 60 // different section: must NOT be written
        edited.weeklyBudgetUSD = 10 // different section: must NOT be written
        edited.save(sections: [.food], to: context)

        let stored = try XCTUnwrap(profile)
        XCTAssertEqual(stored.allergies, ["Eggs"])
        XCTAssertEqual(stored.currentWeightKg, 80)
        XCTAssertEqual(settings.groceryBudgetCapUSD, 90)
    }

    func testShoppingSaveDoesNotTouchTheProfile() throws {
        fullDraft().save(to: context)
        var edited = fullDraft()
        edited.weeklyBudgetUSD = 120
        edited.stores = ["Costco"]
        edited.dislikedFoods = []
        edited.save(sections: [.shopping], to: context)
        XCTAssertEqual(settings.groceryBudgetCapUSD, 120)
        XCTAssertEqual(settings.groceryPreferredStores, ["Costco"])
        XCTAssertEqual(try XCTUnwrap(profile).dislikedFoods, ["Olives"])
    }

    func testSectionSaveWithoutAProfileDoesNotCreateOne() {
        var draft = FuelSetupDraft()
        draft.weeklyBudgetUSD = 70
        draft.save(sections: [.shopping], to: context)
        XCTAssertNil(profile)
        XCTAssertEqual(settings.groceryBudgetCapUSD, 70)
    }

    func testMealsSaveWritesThePlannersWindow() throws {
        var draft = fullDraft()
        draft.eatingWindowStartMinutes = 11 * 60
        draft.eatingWindowEndMinutes = 20 * 60
        draft.mealsPerDay = 3
        draft.save(sections: [.meals], to: context)
        let daily = try XCTUnwrap(UserDailyPlanProfile.current(in: context))
        XCTAssertEqual(MealPlanIntake.seeded(settings: settings, dailyPlan: daily).eatingWindow, EatingWindow(firstMealHour: 11, lastMealHour: 20))
        XCTAssertEqual(settings.mealsPerDayPreference, 3)
    }

    func testEachSectionSavePostsTheChangeOnce() {
        var count = 0
        let token = NotificationCenter.default.addObserver(forName: .tempoDietaryProfileChanged, object: nil, queue: nil) { _ in
            count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }
        fullDraft().save(sections: [.food], to: context)
        XCTAssertEqual(count, 1)
        fullDraft().save(to: context)
        XCTAssertEqual(count, 2)
    }

    func testFullSaveStillWritesEverything() throws {
        fullDraft().save(to: context)
        let stored = try XCTUnwrap(profile)
        XCTAssertEqual(stored.currentWeightKg, 80)
        XCTAssertEqual(stored.primaryGoal, .leanGain)
        XCTAssertEqual(stored.trainingFrequency, 4)
        XCTAssertEqual(settings.groceryBudgetCapUSD, 90)
        XCTAssertEqual(settings.cookTimeWeekdayMins, 30)
    }
}
