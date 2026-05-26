//
// BehaviorObserverTests.swift
// Tempo
//
// Coach v2.1 Phase 4b — covers the meal-skip pattern detection, timing
// variance detection, reinforcement vs propose, contradiction flagging,
// and the daily decay step.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class BehaviorObserverTests: XCTestCase {
    // MARK: - Container helper

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WeeklyMealPlan.self,
            PlannedMeal.self,
            LearnedPreference.self,
            LearnedOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Seed `count` PlannedMeal rows for the same mealNumber across
    /// consecutive past days ending yesterday. `skipDays` controls how
    /// many of those are .skipped. `times` (optional) provides per-day
    /// actualEatenAt offsets in minutes from the scheduled time.
    private func seedMeals(
        in context: ModelContext,
        mealNumber: Int,
        scheduledTime: String,
        count: Int,
        skipDays: Int = 0,
        actualEatTimeOffsetsMin: [Double] = [],
        today: Date,
        calendar: Calendar = .current
    ) {
        for i in 0..<count {
            // i=0 → yesterday, i=1 → two days ago, etc.
            let day = calendar.date(
                byAdding: .day,
                value: -(i + 1),
                to: calendar.startOfDay(for: today)
            )!
            let meal = PlannedMeal(
                dayDate: day,
                mealNumber: mealNumber,
                mealName: BehaviorObserver.mealSlotName(for: mealNumber).capitalized,
                scheduledTime: scheduledTime,
                totalCalories: 500,
                totalProtein: 30,
                totalCarbs: 50,
                totalFat: 15,
                status: i < skipDays ? .skipped : .eaten
            )
            if i < actualEatTimeOffsetsMin.count, meal.status == .eaten {
                let parts = scheduledTime.split(separator: ":").map { Int($0) ?? 0 }
                let scheduled = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)!
                meal.actualEatenAt = scheduled.addingTimeInterval(actualEatTimeOffsetsMin[i] * 60)
            }
            context.insert(meal)
        }
    }

    // MARK: - Skip pattern

    func testProposesNewSkipPreference_whenSkipsMeetThreshold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // 5 of 7 breakfasts skipped → ≥4 threshold met.
        seedMeals(in: context, mealNumber: 1, scheduledTime: "07:30", count: 7, skipDays: 5, today: today)
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertEqual(report.proposed, 1)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        let skipPref = prefs.first { $0.subject == "meal_timing.breakfast.skipped" }
        XCTAssertNotNil(skipPref)
        XCTAssertEqual(skipPref?.source, .observed)
        // Confidence is proposed at 0.5 then immediately decayed once
        // (meal_timing.* = 0.98/day) by the same observer run. So expect
        // 0.5 * 0.98 = 0.49 within tolerance.
        let expected = BehaviorObserver.proposedConfidence * 0.98
        XCTAssertEqual(skipPref?.confidence ?? -1, expected, accuracy: 0.005)
    }

    func testDoesNotProposeBelowThreshold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // Only 3 of 7 skipped — below 4-of-7 threshold.
        seedMeals(in: context, mealNumber: 2, scheduledTime: "12:30", count: 7, skipDays: 3, today: today)
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertEqual(report.proposed, 0)
    }

    func testReinforcesExistingSkipPreference() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // Existing low-confidence skip pref for breakfast.
        let existing = LearnedPreference(
            text: "user usually skips breakfast",
            subject: "meal_timing.breakfast.skipped",
            source: .observed,
            confidence: 0.55,
            evidenceCount: 1,
            lastSeenAt: today.addingTimeInterval(-7 * 86_400)
        )
        context.insert(existing)
        seedMeals(in: context, mealNumber: 1, scheduledTime: "07:30", count: 7, skipDays: 5, today: today)
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertEqual(report.reinforced, 1)
        XCTAssertEqual(report.proposed, 0)
        XCTAssertEqual(existing.evidenceCount, 2)
        XCTAssertGreaterThan(existing.confidence, 0.55)
    }

    func testFlagsContradictionWhenHighConfidenceUnsupported() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // High-confidence skip pref, but recent behavior contradicts (only 1 skip).
        let existing = LearnedPreference(
            text: "user usually skips breakfast",
            subject: "meal_timing.breakfast.skipped",
            source: .observed,
            confidence: 0.85,
            evidenceCount: 5
        )
        context.insert(existing)
        seedMeals(in: context, mealNumber: 1, scheduledTime: "07:30", count: 7, skipDays: 1, today: today)
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertEqual(report.contradictionsFlagged, 1)
        XCTAssertTrue(existing.needsReview)
    }

    // MARK: - Timing variance

    func testProposesActualTimingWhenConsistentlyLate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // 4 lunches eaten 35 min late → ≥30 min mean threshold.
        seedMeals(
            in: context,
            mealNumber: 2,
            scheduledTime: "12:30",
            count: 4,
            actualEatTimeOffsetsMin: [35, 32, 40, 33],
            today: today
        )
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertGreaterThanOrEqual(report.proposed, 1)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        let actual = prefs.first { $0.subject == "meal_timing.lunch.actual" }
        XCTAssertNotNil(actual)
        XCTAssertTrue(actual?.text.contains("after schedule") ?? false)
    }

    func testDoesNotProposeWhenMeanUnderThreshold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // Mean offset = 12 → under 30-min threshold.
        seedMeals(
            in: context,
            mealNumber: 3,
            scheduledTime: "19:30",
            count: 4,
            actualEatTimeOffsetsMin: [15, 10, 12, 11],
            today: today
        )
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertFalse(prefs.contains { $0.subject == "meal_timing.dinner.actual" })
        XCTAssertEqual(report.proposed, 0)
    }

    func testTimingPreferenceRefreshesText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // Existing pref says "~25 min after schedule" but new behavior averages 40.
        let existing = LearnedPreference(
            text: "user usually eats lunch ~25 min after schedule",
            subject: "meal_timing.lunch.actual",
            source: .observed,
            confidence: 0.55
        )
        context.insert(existing)
        seedMeals(
            in: context,
            mealNumber: 2,
            scheduledTime: "12:30",
            count: 4,
            actualEatTimeOffsetsMin: [40, 42, 38, 41],
            today: today
        )
        try context.save()

        _ = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertTrue(existing.text.contains("40 min") || existing.text.contains("41 min"))
    }

    // MARK: - Daily decay

    func testDailyDecayRunsAfterScans() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        let pref = LearnedPreference(
            text: "x",
            subject: "tone.style",
            source: .observed,
            confidence: 0.80
        )
        context.insert(pref)
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        // tone.* decays at 0.99/day → confidence dropped slightly.
        XCTAssertLessThan(pref.confidence, 0.80)
        XCTAssertEqual(report.decayed, 1)
    }

    func testDailyDecayDoesNotTouchInactiveRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        let pref = LearnedPreference(
            text: "x",
            subject: "tone.style",
            source: .observed,
            confidence: 0.30,
            isActive: false
        )
        context.insert(pref)
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertEqual(pref.confidence, 0.30, accuracy: 0.001)
        XCTAssertEqual(report.decayed, 0)
    }

    func testDailyDecayCountsAutoDeactivation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        // schedule.* decays at 0.95/day; starting at 0.21 → 0.1995 < 0.2.
        let pref = LearnedPreference(
            text: "x",
            subject: "schedule.exceptions",
            source: .observed,
            confidence: 0.21
        )
        context.insert(pref)
        try context.save()

        let report = try BehaviorObserver.observe(modelContext: context, today: today)
        XCTAssertEqual(report.deactivatedByDecay, 1)
        XCTAssertFalse(pref.isActive)
    }

    // MARK: - Helpers

    func testScheduledDateParsing() {
        let dayDate = Calendar.current.startOfDay(for: Date())
        let meal = PlannedMeal(
            dayDate: dayDate,
            mealNumber: 1,
            mealName: "Breakfast",
            scheduledTime: "07:30"
        )
        let date = BehaviorObserver.scheduledDate(for: meal)
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date!)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
    }

    func testScheduledDateMalformedReturnsNil() {
        let dayDate = Calendar.current.startOfDay(for: Date())
        let meal = PlannedMeal(
            dayDate: dayDate,
            mealNumber: 1,
            mealName: "Breakfast",
            scheduledTime: "not-a-time"
        )
        XCTAssertNil(BehaviorObserver.scheduledDate(for: meal))
    }
}
