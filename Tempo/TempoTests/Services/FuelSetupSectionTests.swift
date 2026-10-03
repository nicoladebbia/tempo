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

    func testEmptySectionsReadNotSet() {
        let draft = FuelSetupDraft()
        for section in [FuelSetupSection.you, .goal, .meals, .week, .shopping] {
            XCTAssertEqual(draft.summary(for: section), "Not set", "\(section)")
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
        XCTAssertEqual(draft.missingFields(in: .week), [.wakeTime])
        XCTAssertTrue(draft.missingFields(in: .food).isEmpty)
        XCTAssertEqual(draft.incompleteSections, [.you, .goal, .meals, .week])
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
        XCTAssertEqual(FuelFlowStep.steps(for: .you, draft: draft, locked: locked), [.weight, .height, .age, .sex, .bodyFat])
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
