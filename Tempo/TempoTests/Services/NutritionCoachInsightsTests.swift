//
// NutritionCoachInsightsTests.swift
// Tempo
//
// The Coach tab's AI layer: per-day cache, per-section load states, the
// "AI off → template" fallbacks (offline, no Pro / no consent), and the
// user-facing NutritionCoachError copy.
//

@testable import Tempo
import XCTest

// MARK: - FakeCoachProvider

private final class FakeCoachProvider: NutritionCoachInsightProviding, @unchecked Sendable {
    var dailyResult: Result<String, Error> = .success("Pace is fine. Hit 40g protein at lunch.")
    var recoveryResult: Result<CoachRecoveryGuidance, Error> = .success(
        CoachRecoveryGuidance(message: "Recovery is yellow. Eat to target.", tips: ["Drink 3L", "Protein every meal"])
    )
    var mealResult: Result<String, Error> = .success("Strong protein hit.")
    private(set) var dailyCalls = 0
    private(set) var recoveryCalls = 0
    private(set) var mealCalls = 0

    func dailyBriefing(_: CoachDayContext) async throws -> String {
        dailyCalls += 1
        return try dailyResult.get()
    }

    func recoveryGuidance(_: CoachDayContext) async throws -> CoachRecoveryGuidance {
        recoveryCalls += 1
        return try recoveryResult.get()
    }

    func mealFeedback(for _: CoachMealSnapshot, day _: CoachDayContext) async throws -> String {
        mealCalls += 1
        return try mealResult.get()
    }
}

// MARK: - NutritionCoachInsightsTests

@MainActor
final class NutritionCoachInsightsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var today: Date!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "NutritionCoachInsightsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        today = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    private var cache: CoachInsightCache {
        CoachInsightCache(defaults: defaults)
    }

    private func makeModel(now: Date? = nil) -> NutritionCoachInsightsModel {
        let date = now ?? today!
        return NutritionCoachInsightsModel(cache: cache, now: { date })
    }

    private func meal(_ name: String = "Lunch", id: UUID = UUID()) -> CoachMealSnapshot {
        CoachMealSnapshot(id: id, name: name, calories: 650, protein: 45, carbs: 70, fat: 18, time: "12:30", items: ["chicken", "rice"])
    }

    private func day(meals: [CoachMealSnapshot] = [], recovery: WhoopRecoveryData? = nil) -> CoachDayContext {
        CoachDayContext(
            eatenMeals: meals,
            caloriesConsumed: 650,
            proteinConsumed: 45,
            carbsConsumed: 70,
            fatConsumed: 18,
            calorieTarget: 2800,
            proteinTarget: 180,
            carbsTarget: 320,
            fatTarget: 80,
            mealsPlanned: 4,
            recovery: recovery,
            sleep: nil,
            trainingToday: "Strength",
            tomorrowTraining: "Rest"
        )
    }

    private var recovery: WhoopRecoveryData {
        WhoopRecoveryData(score: 50, hrvRmssd: 60, restingHeartRate: 55, spo2: nil, skinTemp: nil, date: Date())
    }

    // MARK: - Cache

    func testCache_roundTripsSameDay_andMissesNextDay() throws {
        cache.store("Briefing", for: .dailyBriefing, on: today)
        XCTAssertEqual(cache.string(for: .dailyBriefing, on: today), "Briefing")

        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        XCTAssertNil(cache.string(for: .dailyBriefing, on: tomorrow), "Yesterday's briefing must not show today")
    }

    func testCache_writePrunesOtherDays() throws {
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today))
        cache.store("Old", for: .dailyBriefing, on: yesterday)
        cache.store("New", for: .recoveryGuidance, on: today)

        XCTAssertNil(cache.string(for: .dailyBriefing, on: yesterday), "Writing today drops other days' entries")
        XCTAssertEqual(cache.string(for: .recoveryGuidance, on: today), "New")
    }

    func testCache_sectionsAndMealsAreIndependent() {
        let a = UUID(), b = UUID()
        cache.store("A", for: .mealFeedback(a), on: today)
        cache.store("B", for: .mealFeedback(b), on: today)
        cache.store("D", for: .dailyBriefing, on: today)

        XCTAssertEqual(cache.string(for: .mealFeedback(a), on: today), "A")
        XCTAssertEqual(cache.string(for: .mealFeedback(b), on: today), "B")
        XCTAssertEqual(cache.string(for: .dailyBriefing, on: today), "D")
    }

    func testCache_codableValueRoundTrips() {
        let guidance = CoachRecoveryGuidance(message: "M", tips: ["t1", "t2"])
        cache.store(guidance, for: .recoveryGuidance, on: today)
        XCTAssertEqual(cache.value(CoachRecoveryGuidance.self, for: .recoveryGuidance, on: today), guidance)
    }

    // MARK: - Daily briefing

    func testDailyBriefing_loadsOnceThenServesCache() async {
        let provider = FakeCoachProvider()
        let model = makeModel()

        await model.loadDailyBriefing(day(), provider: provider, isOnline: true)
        XCTAssertEqual(model.daily, .loaded("Pace is fine. Hit 40g protein at lunch."))

        // Fresh model (tab reopened) → served from the persisted cache, no call.
        let reopened = makeModel()
        await reopened.loadDailyBriefing(day(), provider: provider, isOnline: true)
        XCTAssertEqual(reopened.daily, .loaded("Pace is fine. Hit 40g protein at lunch."))
        XCTAssertEqual(provider.dailyCalls, 1, "Cached once per calendar day")
    }

    func testDailyBriefing_forceRefreshCallsAgain() async {
        let provider = FakeCoachProvider()
        let model = makeModel()
        await model.loadDailyBriefing(day(), provider: provider, isOnline: true)
        provider.dailyResult = .success("Updated.")

        await model.loadDailyBriefing(day(), provider: provider, isOnline: true, force: true)

        XCTAssertEqual(provider.dailyCalls, 2)
        XCTAssertEqual(model.daily, .loaded("Updated."))
        XCTAssertEqual(cache.string(for: .dailyBriefing, on: today), "Updated.")
    }

    func testDailyBriefing_newDayCallsAgain() async throws {
        let provider = FakeCoachProvider()
        await makeModel().loadDailyBriefing(day(), provider: provider, isOnline: true)

        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        await makeModel(now: tomorrow).loadDailyBriefing(day(), provider: provider, isOnline: true)

        XCTAssertEqual(provider.dailyCalls, 2)
    }

    func testDailyBriefing_offline_fallsBackWithoutCalling() async {
        let provider = FakeCoachProvider()
        let model = makeModel()

        await model.loadDailyBriefing(day(), provider: provider, isOnline: false)

        XCTAssertEqual(model.daily, .fallback)
        XCTAssertEqual(provider.dailyCalls, 0)
    }

    func testDailyBriefing_offline_stillServesTodaysCache() async {
        cache.store("Cached", for: .dailyBriefing, on: today)
        let model = makeModel()

        await model.loadDailyBriefing(day(), provider: FakeCoachProvider(), isOnline: false)

        XCTAssertEqual(model.daily, .loaded("Cached"))
    }

    func testEntitlementGate_fallsBackSilently_andStopsFurtherCalls() async {
        let provider = FakeCoachProvider()
        provider.dailyResult = .failure(NutritionCoachError.apiFailed(APIError.subscriptionRequired))
        let model = makeModel()

        await model.loadDailyBriefing(day(), provider: provider, isOnline: true)
        await model.loadRecoveryGuidance(day(recovery: recovery), provider: provider, isOnline: true)
        await model.loadMealFeedback(for: [meal()], day: day(), provider: provider, isOnline: true)

        XCTAssertEqual(model.daily, .fallback, "No Pro is 'AI off', not an error")
        XCTAssertNil(model.daily.errorMessage)
        XCTAssertTrue(model.isAIGated)
        XCTAssertEqual(model.recovery, .fallback)
        XCTAssertEqual(provider.recoveryCalls, 0, "Gated → no further calls")
        XCTAssertEqual(provider.mealCalls, 0)
    }

    func testAIConsentGate_isAlsoSilentFallback() async {
        let provider = FakeCoachProvider()
        provider.dailyResult = .failure(NutritionCoachError.apiFailed(APIError.aiConsentRequired))
        let model = makeModel()

        await model.loadDailyBriefing(day(), provider: provider, isOnline: true)

        XCTAssertEqual(model.daily, .fallback)
    }

    func testRealFailure_showsUserMessage_andIsNotCached() async {
        let provider = FakeCoachProvider()
        provider.dailyResult = .failure(NutritionCoachError.apiFailed(APIError.serverError(statusCode: 500)))
        let model = makeModel()

        await model.loadDailyBriefing(day(), provider: provider, isOnline: true)

        XCTAssertEqual(model.daily, .failed(APIError.serverError(statusCode: 500).userMessage))
        XCTAssertNil(cache.string(for: .dailyBriefing, on: today), "Failures must not poison the day's cache")
    }

    func testCancelledLoad_doesNotShowError() async {
        let provider = FakeCoachProvider()
        // APIClient rewraps a cancelled request as a timeout.
        provider.dailyResult = .failure(NutritionCoachError.apiFailed(APIError.timeout))
        let model = makeModel()

        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.loadDailyBriefing(day(), provider: provider, isOnline: true)
        }
        await task.value

        XCTAssertNil(model.daily.errorMessage, "A .task(id:) restart must not flash an error")
    }

    // MARK: - Recovery guidance

    func testRecoveryGuidance_withoutWhoop_staysIdleWithoutCalling() async {
        let provider = FakeCoachProvider()
        let model = makeModel()

        await model.loadRecoveryGuidance(day(recovery: nil), provider: provider, isOnline: true)

        XCTAssertEqual(model.recovery, .idle, "Template 'Connect Whoop' copy is the answer")
        XCTAssertEqual(provider.recoveryCalls, 0)
    }

    func testRecoveryGuidance_loadsAndCaches() async {
        let provider = FakeCoachProvider()
        let model = makeModel()

        await model.loadRecoveryGuidance(day(recovery: recovery), provider: provider, isOnline: true)
        await makeModel().loadRecoveryGuidance(day(recovery: recovery), provider: provider, isOnline: true)

        XCTAssertEqual(model.recovery.value?.tips, ["Drink 3L", "Protein every meal"])
        XCTAssertEqual(provider.recoveryCalls, 1)
    }

    // MARK: - Meal feedback

    func testMealFeedback_perMealOncePerDay() async {
        let provider = FakeCoachProvider()
        let model = makeModel()
        let first = meal("Breakfast")
        let second = meal("Lunch")

        await model.loadMealFeedback(for: [first], day: day(meals: [first]), provider: provider, isOnline: true)
        await model.loadMealFeedback(for: [first, second], day: day(meals: [first, second]), provider: provider, isOnline: true)

        XCTAssertEqual(provider.mealCalls, 2, "Only the newly eaten meal triggers a call")
        XCTAssertEqual(model.feedbackState(for: first.id), .loaded("Strong protein hit."))
        XCTAssertEqual(model.feedbackState(for: second.id), .loaded("Strong protein hit."))
    }

    func testRestoreFromCache_showsCachedSectionsWithoutNetwork() {
        let eaten = meal()
        cache.store("Daily", for: .dailyBriefing, on: today)
        cache.store("Meal", for: .mealFeedback(eaten.id), on: today)
        let model = makeModel()

        model.restoreFromCache(eatenMealIDs: [eaten.id])

        XCTAssertEqual(model.daily, .loaded("Daily"))
        XCTAssertEqual(model.feedbackState(for: eaten.id), .loaded("Meal"))
        XCTAssertEqual(model.recovery, .idle)
    }

    // MARK: - Recovery JSON parsing

    func testParseRecoveryGuidance_plainJSON() throws {
        let parsed = try NutritionCoachService.parseRecoveryGuidance(#"{"message":"Eat.","tips":["a","b"]}"#)
        XCTAssertEqual(parsed, CoachRecoveryGuidance(message: "Eat.", tips: ["a", "b"]))
    }

    func testParseRecoveryGuidance_fencedJSON() throws {
        let parsed = try NutritionCoachService.parseRecoveryGuidance("```json\n{\"message\":\"Eat.\",\"tips\":[\"a\"]}\n```")
        XCTAssertEqual(parsed.message, "Eat.")
        XCTAssertEqual(parsed.tips, ["a"])
    }

    func testParseRecoveryGuidance_plainTextBecomesMessage() throws {
        let parsed = try NutritionCoachService.parseRecoveryGuidance("Recovery is red. Eat to target.")
        XCTAssertEqual(parsed.message, "Recovery is red. Eat to target.")
        XCTAssertTrue(parsed.tips.isEmpty)
    }

    func testParseRecoveryGuidance_brokenJSONThrows() {
        XCTAssertThrowsError(try NutritionCoachService.parseRecoveryGuidance("{\"message\": "))
    }

    // MARK: - NutritionCoachError copy

    func testCoachError_unwrapsAPIErrorUserMessage() {
        let error: Error = NutritionCoachError.apiFailed(APIError.subscriptionRequired)
        XCTAssertEqual(error.localizedDescription, APIError.subscriptionRequired.userMessage)
    }

    func testCoachError_networkMessage() {
        let error: Error = NutritionCoachError.apiFailed(APIError.networkError("offline"))
        XCTAssertEqual(error.localizedDescription, "Network error. Check your connection and try again.")
    }

    func testCoachError_parseFailureIsHumanReadable() {
        let error: Error = NutritionCoachError.jsonParsingFailed("Could not parse meal_suggestions response as X")
        XCTAssertFalse(error.localizedDescription.contains("Tempo.NutritionCoachError"))
        XCTAssertFalse(error.localizedDescription.contains("meal_suggestions"), "No internal feature ids in UI copy")
    }

    func testCoachError_entitlementGateDetection() {
        XCTAssertTrue(NutritionCoachError.apiFailed(APIError.subscriptionRequired).isEntitlementGate)
        XCTAssertTrue(NutritionCoachError.apiFailed(APIError.aiConsentRequired).isEntitlementGate)
        XCTAssertFalse(NutritionCoachError.apiFailed(APIError.timeout).isEntitlementGate)
        XCTAssertFalse(NutritionCoachError.circuitOpen.isEntitlementGate)
    }

    // MARK: - Prompt framing

    func testDailySummaryPrompt_inProgressFraming() {
        let prompt = NutritionCoachPrompts.dailySummaryPrompt(
            meals: [], totalCalories: 600, totalProtein: 40, totalCarbs: 60, totalFat: 20,
            calorieTarget: 2800, proteinTarget: 180, carbsTarget: 300, fatTarget: 80,
            mealsLogged: 1, mealsPlanned: 4, recoveryScore: nil, recoveryZone: nil,
            tomorrowTraining: nil, dayInProgress: true, trainingToday: "Strength"
        )
        XCTAssertTrue(prompt.contains("IN PROGRESS"))
        XCTAssertFalse(prompt.contains("end-of-day"))
        XCTAssertTrue(prompt.contains("<today>Day type: Strength</today>"))
    }

    func testDailySummaryPrompt_defaultStaysEndOfDay() {
        let prompt = NutritionCoachPrompts.dailySummaryPrompt(
            meals: [], totalCalories: 600, totalProtein: 40, totalCarbs: 60, totalFat: 20,
            calorieTarget: 2800, proteinTarget: 180, carbsTarget: 300, fatTarget: 80,
            mealsLogged: 1, mealsPlanned: 4, recoveryScore: nil, recoveryZone: nil, tomorrowTraining: nil
        )
        XCTAssertTrue(prompt.contains("end-of-day"))
    }

    func testRecoveryPrompt_withTipsAsksForJSON() {
        let prompt = NutritionCoachPrompts.recoveryNutritionPrompt(
            recoveryScore: 30, recoveryZone: "red", hrvRmssd: 40, restingHeartRate: 60,
            sleepHours: 6, sleepScore: 70, todayCalories: 900, todayProtein: 60, todayCarbs: 90, todayFat: 30,
            calorieTarget: 2800, proteinTarget: 180, trainingToday: nil, withTips: true
        )
        XCTAssertTrue(prompt.contains("\"tips\""))
        XCTAssertFalse(prompt.contains("Output ONLY the guidance text"))

        let plain = NutritionCoachPrompts.recoveryNutritionPrompt(
            recoveryScore: 30, recoveryZone: "red", hrvRmssd: 40, restingHeartRate: 60,
            sleepHours: nil, sleepScore: nil, todayCalories: 900, todayProtein: 60, todayCarbs: 90, todayFat: 30,
            calorieTarget: 2800, proteinTarget: 180, trainingToday: nil
        )
        XCTAssertTrue(plain.contains("Output ONLY the guidance text"))
    }
}
