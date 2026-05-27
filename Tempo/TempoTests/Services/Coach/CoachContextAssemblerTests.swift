//
// CoachContextAssemblerTests.swift
// Tempo
//
// Coach v2.1 Phase 5 — covers identity assembly, backward/forward window
// construction, goal-progress block, calendar event mapping, and the
// render-pipeline's token-budget pruning passes.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachContextAssemblerTests: XCTestCase {
    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            UserSettings.self,
            DietaryProfile.self,
            WeeklyMealPlan.self,
            PlannedMeal.self,
            WorkoutPlan.self,
            PlannedExercise.self,
            PlannedSet.self,
            DailyRecovery.self,
            LearnedPreference.self,
            LearnedOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTodayLive(date: Date) -> TodayLiveSnapshot {
        TodayLiveSnapshot(
            date: date,
            dayType: .strength,
            recoveryScore: 84,
            recoveryZone: "green",
            hrvMs: 90,
            restingHR: 52,
            sleepHoursLastNight: 8.5,
            stepsSoFar: 1200,
            plannedMealCount: 4,
            loggedKcalSoFar: 420,
            targetKcal: 2800,
            workoutTitle: "Push day",
            workoutTime: "17:00"
        )
    }

    // MARK: - Identity

    func testIdentity_pullsFromUserProfileAndDietaryProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profile = UserProfile(
            appleID: "apple-1",
            username: "nico",
            displayName: "Nicola",
            identityLabel: "footballer",
            weightKg: 81,
            heightCm: 178,
            age: 20
        )
        context.insert(profile)
        let diet = DietaryProfile(primaryGoal: .cut, currentWeightKg: 81)
        context.insert(diet)
        try context.save()

        let identity = CoachContextAssembler.makeIdentity(in: context)
        XCTAssertEqual(identity.displayName, "Nicola")
        XCTAssertEqual(identity.age, 20)
        XCTAssertEqual(identity.sport, "footballer")
        XCTAssertEqual(identity.primaryGoal, DietaryGoal.cut.displayName)
        XCTAssertEqual(try XCTUnwrap(identity.currentWeightKg), 81, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(identity.heightCm), 178, accuracy: 0.001)
    }

    func testIdentity_emptyContextHasSafeDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let identity = CoachContextAssembler.makeIdentity(in: context)
        XCTAssertEqual(identity.displayName, "User")
        XCTAssertNil(identity.age)
        XCTAssertNil(identity.sport)
        XCTAssertNil(identity.primaryGoal)
    }

    // MARK: - Backward window

    func testBackwardWindow_collectsLastSevenDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        // Seed 7 days of meals: dayDate i days ago, mealNumber 1.
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let meal = PlannedMeal(
                dayDate: day,
                mealNumber: 1,
                mealName: "Breakfast",
                scheduledTime: "07:30",
                totalCalories: 600,
                status: offset.isMultiple(of: 2) ? .eaten : .skipped
            )
            context.insert(meal)
        }
        try context.save()

        let window = CoachContextAssembler.makeBackwardWindow(
            in: context,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(window.count, 7)
        XCTAssertTrue(window.contains { $0.skippedMealCount > 0 }, "skipped meals tracked")
    }

    func testBackwardDay_flagsDeviation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        // Planned 600, but skipped — eatenKcal=0, plannedKcal=600 → diff > 250.
        let meal = PlannedMeal(
            dayDate: yesterday,
            mealNumber: 1,
            mealName: "Breakfast",
            scheduledTime: "07:30",
            totalCalories: 600,
            status: .skipped
        )
        context.insert(meal)
        try context.save()

        let window = CoachContextAssembler.makeBackwardWindow(
            in: context,
            today: today,
            calendar: calendar
        )
        let yesterdayBlock = window.first { calendar.isDate($0.date, inSameDayAs: yesterday) }
        XCTAssertNotNil(yesterdayBlock)
        XCTAssertTrue(yesterdayBlock?.deviationsFlag ?? false)
    }

    // MARK: - Forward window

    func testForwardWindow_collectsNextSevenDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let meal = PlannedMeal(
                dayDate: day,
                mealNumber: 1,
                mealName: "Breakfast",
                scheduledTime: "07:30",
                totalCalories: 600
            )
            context.insert(meal)
        }
        try context.save()

        let window = CoachContextAssembler.makeForwardWindow(
            in: context,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(window.count, 7)
        for day in window {
            XCTAssertEqual(day.plannedKcal, 600, accuracy: 0.001)
            XCTAssertEqual(day.plannedMealCount, 1)
        }
    }

    // MARK: - Goal progress

    func testGoalProgress_buildFromDietaryProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let diet = DietaryProfile(primaryGoal: .cut, currentWeightKg: 81.2)
        context.insert(diet)
        try context.save()

        let goal = CoachContextAssembler.makeGoalProgress(
            in: context,
            today: Date(),
            calendar: .current
        )
        XCTAssertNotNil(goal)
        XCTAssertEqual(goal?.primaryGoal, DietaryGoal.cut.displayName)
        XCTAssertEqual(try XCTUnwrap(goal?.currentWeightKg), 81.2, accuracy: 0.001)
        // Target + trajectory deferred — must be nil for v2.1.
        XCTAssertNil(goal?.targetWeightKg)
        XCTAssertNil(goal?.trajectoryLabel)
    }

    func testGoalProgress_returnsNilWhenNoDietaryProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let goal = CoachContextAssembler.makeGoalProgress(
            in: context,
            today: Date(),
            calendar: .current
        )
        XCTAssertNil(goal)
    }

    // MARK: - Calendar event mapping

    func testCalendarEventSummary_formatsHHmm() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 19, minute: 30))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 20, minute: 30))!
        let event = CalendarEvent(
            title: "Soccer practice",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarName: "Sports"
        )
        let summary = CalendarEventSummary(event)
        XCTAssertEqual(summary.title, "Soccer practice")
        XCTAssertEqual(summary.startHHmm, "19:30")
        XCTAssertEqual(summary.endHHmm, "20:30")
    }

    // MARK: - End-to-end assemble

    func testAssemble_returnsAllSections() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        let profile = UserProfile(
            appleID: "apple-1",
            username: "nico",
            displayName: "Nicola",
            weightKg: 81,
            heightCm: 178,
            age: 20
        )
        context.insert(profile)
        let diet = DietaryProfile(primaryGoal: .cut, currentWeightKg: 81)
        context.insert(diet)
        let pref = LearnedPreference(
            text: "user prefers chicken bowls for dinner",
            subject: "meal_prefs.cuisines.likes",
            source: .explicit
        )
        context.insert(pref)
        try context.save()

        let snapshot = CoachContextAssembler.assemble(
            modelContext: context,
            today: today,
            userMessage: "what should I eat tonight",
            todayLive: makeTodayLive(date: today),
            calendarEvents: [
                CalendarEventSummary(title: "Class", startHHmm: "09:00", endHHmm: "10:30"),
            ],
            recentConversationSummaries: [
                ConversationSummary(id: UUID(), endedAt: today, titleSummary: "Soccer night dinner shift"),
            ],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.identity.displayName, "Nicola")
        XCTAssertNotNil(snapshot.goalProgress)
        XCTAssertEqual(snapshot.calendarEvents.count, 1)
        XCTAssertEqual(snapshot.conversationSummaries.count, 1)
        XCTAssertTrue(snapshot.preferences.contains { $0.id == pref.id })
    }

    // MARK: - render

    func testRender_smallSnapshotUnderBudget() {
        let snapshot = sampleSnapshot()
        let rendered = snapshot.render()
        XCTAssertTrue(rendered.contains("<identity>"))
        XCTAssertTrue(rendered.contains("<today-live>"))
        XCTAssertTrue(rendered.contains("<preferences-relevant-to-this-message>"))
        let approxTokens = rendered.count / CoachContextAssembler.charsPerToken
        XCTAssertLessThan(approxTokens, CoachContextAssembler.targetTokenBudget)
    }

    func testRender_collapsesForwardWhenOverBudget() {
        // Build a snapshot well over the budget — long forward window dominates.
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let forward: [ForwardDay] = (1...30).compactMap { (i: Int) -> ForwardDay? in
            guard let day = calendar.date(byAdding: .day, value: i, to: today) else { return nil }
            return ForwardDay(date: day, dayType: .push, plannedMealCount: 4, plannedKcal: 2800)
        }
        let snapshot = CoachContextSnapshot(
            identity: IdentityBlock(displayName: "X", age: 20, sport: nil, primaryGoal: nil, currentWeightKg: nil, heightCm: nil),
            preferences: [],
            outcomes: [],
            todayLive: makeTodayLive(date: today),
            calendarEvents: [],
            backwardWindow: [],
            forwardWindow: forward,
            goalProgress: nil,
            conversationSummaries: []
        )
        // 200-token budget forces collapse.
        let rendered = snapshot.render(budget: 200)
        XCTAssertTrue(rendered.contains("days planned — request details inline"))
    }

    func testRender_trimsPreferencesWhenOverBudget() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        // 50 preferences. With a tight budget, render must trim them down,
        // floor at 5.
        let prefs = (0..<50).map { i in
            LearnedPreference(text: "pref number \(i) with some descriptive padding text to inflate", subject: "tone.style", source: .observed)
        }
        let snapshot = CoachContextSnapshot(
            identity: IdentityBlock(displayName: "X", age: nil, sport: nil, primaryGoal: nil, currentWeightKg: nil, heightCm: nil),
            preferences: prefs,
            outcomes: [],
            todayLive: makeTodayLive(date: today),
            calendarEvents: [],
            backwardWindow: [],
            forwardWindow: [],
            goalProgress: nil,
            conversationSummaries: []
        )
        let rendered = snapshot.render(budget: 250)
        let approxTokens = rendered.count / CoachContextAssembler.charsPerToken
        // Must succeed (eventually drop down to the 5-pref floor).
        XCTAssertLessThanOrEqual(approxTokens, 350, "must fit within budget plus small slack")
    }

    func testRender_includesGoalAndCalendarSectionsWhenPresent() {
        let snapshot = sampleSnapshot()
        let rendered = snapshot.render()
        XCTAssertTrue(rendered.contains("<goal-progress>"))
        XCTAssertTrue(rendered.contains("<today-live>"))
    }

    // MARK: - Helpers

    private func sampleSnapshot() -> CoachContextSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        return CoachContextSnapshot(
            identity: IdentityBlock(
                displayName: "Nicola",
                age: 20,
                sport: "footballer",
                primaryGoal: DietaryGoal.cut.displayName,
                currentWeightKg: 81.2,
                heightCm: 178
            ),
            preferences: [
                LearnedPreference(
                    text: "user needs 2.5h between dinner and sleep",
                    subject: "digestion.before_bed",
                    source: .observed,
                    confidence: 0.82
                ),
            ],
            outcomes: [],
            todayLive: makeTodayLive(date: today),
            calendarEvents: [
                CalendarEventSummary(title: "Class", startHHmm: "09:00", endHHmm: "10:30"),
            ],
            backwardWindow: [],
            forwardWindow: [],
            goalProgress: GoalProgressBlock(
                primaryGoal: DietaryGoal.cut.displayName,
                currentWeightKg: 81.2,
                targetWeightKg: nil,
                weeklyChangeKg: nil,
                trajectoryLabel: nil
            ),
            conversationSummaries: []
        )
    }
}
