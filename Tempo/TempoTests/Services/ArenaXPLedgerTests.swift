//
// ArenaXPLedgerTests.swift
// TempoTests
//
// XP has one writer: the ledger turns what the user really did into XPEvent
// rows, once per day per source, and mirrors the total onto the profile. These
// tests pin the amounts, the "run it twice, nothing changes" rule, and that
// undoing something takes its XP back.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ArenaXPLedgerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let engine = XPEngine()
    private let calendar = ArenaCalendar.calendar(timeZone: TimeZone(identifier: "Europe/Rome")!)

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = ModelContext(container)
    }

    /// A fixed "now": Tuesday 24 Nov 2026, 10:00 in Rome.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 10))!
    }

    private func day(_ offset: Int, hour: Int = 18) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    private func finishedWorkout(on date: Date) -> WorkoutPlan {
        let plan = WorkoutPlan(date: date, type: .push, status: .completed)
        plan.date = calendar.startOfDay(for: date)
        plan.startedAt = date
        context.insert(plan)
        return plan
    }

    private func sync() -> ArenaXPLedger.Summary {
        ArenaXPLedger.sync(in: context, engine: engine, now: now, calendar: calendar)
    }

    private func xpRows() -> [XPEvent] {
        (try? context.fetch(FetchDescriptor<XPEvent>())) ?? []
    }

    // MARK: - What a day is worth

    func testWorkoutDayAwards() {
        let awards = engine.dayAwards(for: XPDayActivity(workouts: 1, exercisesPerformed: 4, earliestWorkoutHour: 18))
        XCTAssertEqual(awards.count, 1)
        // 50 for the workout, 4 x 10 for exercises, 10 for the first of the day.
        XCTAssertEqual(awards.first?.source, .workout)
        XCTAssertEqual(awards.first?.amount, 100)
    }

    func testEarlyBirdWorkoutAddsBonus() {
        let early = engine.dayAwards(for: XPDayActivity(workouts: 1, exercisesPerformed: 0, earliestWorkoutHour: 6))
        let late = engine.dayAwards(for: XPDayActivity(workouts: 1, exercisesPerformed: 0, earliestWorkoutHour: 19))
        XCTAssertEqual((early.first?.amount ?? 0) - (late.first?.amount ?? 0), 25)
    }

    func testMealsAndStudyAndTasks() {
        let meals = engine.dayAwards(for: XPDayActivity(mealSlotsLogged: 3, mainMealsAllLogged: true))
        XCTAssertEqual(meals.first?.amount, 3 * 5 + 40)
        let someMeals = engine.dayAwards(for: XPDayActivity(mealSlotsLogged: 2))
        XCTAssertEqual(someMeals.first?.amount, 10)

        let study = engine.dayAwards(for: XPDayActivity(studyMinutes: 55, earliestStudyHour: 14))
        // Two full 25-minute blocks, plus the first-of-the-day bonus.
        XCTAssertEqual(study.first?.amount, 2 * 25 + 10)
        XCTAssertTrue(engine.dayAwards(for: XPDayActivity(studyMinutes: 20)).isEmpty, "under one block earns nothing")

        let tasks = engine.dayAwards(for: XPDayActivity(allNonNegotiablesDone: true))
        XCTAssertEqual(tasks.first?.source, .nonNegotiable)
        XCTAssertEqual(tasks.first?.amount, 100)
    }

    func testAnEmptyDayIsWorthNothingNeverLess() {
        XCTAssertTrue(engine.dayAwards(for: XPDayActivity()).isEmpty)
    }

    func testLevelTitlesAreDistinct() {
        XCTAssertEqual(LevelSystem.displayTitle(for: 1), "Recruit")
        XCTAssertNotEqual(LevelSystem.displayTitle(for: 1), LevelSystem.displayTitle(for: 2))
        let titles = (1 ... LevelSystem.definitions.count).map { LevelSystem.displayTitle(for: $0) }
        XCTAssertEqual(Set(titles).count, titles.count, "every level reads differently")
        // The band name is unchanged for the places that mean the band.
        XCTAssertEqual(LevelSystem.definition(for: 2).name, LevelSystem.definition(for: 1).name)
    }

    // MARK: - Records to days

    func testActivityGroupsRecordsByDay() {
        let records = ArenaXPLedger.Records(
            workouts: [
                .init(day: calendar.startOfDay(for: day(0)), start: day(0, hour: 7), startHour: 7, exercises: 3, volumeKg: 1000),
                .init(day: calendar.startOfDay(for: day(0)), start: day(0, hour: 19), startHour: 19, exercises: 2, volumeKg: 500),
            ],
            meals: [
                .init(day: calendar.startOfDay(for: day(0)), slot: "breakfast"),
                .init(day: calendar.startOfDay(for: day(0)), slot: "lunch"),
                .init(day: calendar.startOfDay(for: day(0)), slot: "dinner"),
                .init(day: calendar.startOfDay(for: day(-1)), slot: "snack"),
            ],
            studySessions: [.init(day: calendar.startOfDay(for: day(0)), start: day(0, hour: 9), minutes: 50, pomodoros: 2)],
            taskDays: [.init(day: calendar.startOfDay(for: day(0)), allDone: true)]
        )
        let activity = ArenaXPLedger.activity(from: records, calendar: calendar)
        let today = activity[ArenaCalendar.dayKey(now, calendar: calendar)]
        XCTAssertEqual(today?.workouts, 2)
        XCTAssertEqual(today?.exercisesPerformed, 5)
        XCTAssertEqual(today?.earliestWorkoutHour, 7)
        XCTAssertEqual(today?.mealSlotsLogged, 3)
        XCTAssertEqual(today?.mainMealsAllLogged, true)
        XCTAssertEqual(today?.studyMinutes, 50)
        XCTAssertEqual(today?.allNonNegotiablesDone, true)
        let yesterday = activity[ArenaCalendar.dayKey(day(-1), calendar: calendar)]
        XCTAssertEqual(yesterday?.mealSlotsLogged, 1)
        XCTAssertEqual(yesterday?.mainMealsAllLogged, false)
    }

    // MARK: - Sync

    func testSyncWritesOneRowPerDayPerSourceAndTheTotalMatches() {
        _ = finishedWorkout(on: day(0))
        _ = finishedWorkout(on: day(-1))
        try? context.save()
        let summary = sync()

        let rows = xpRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.source == .workout })
        XCTAssertEqual(rows.reduce(0) { $0 + $1.amount }, summary.totalXP)
        XCTAssertGreaterThan(summary.totalXP, 0)
        XCTAssertEqual(summary.level, engine.currentLevel(totalXP: summary.totalXP))
    }

    func testSyncTwiceChangesNothing() {
        _ = finishedWorkout(on: day(0))
        try? context.save()
        let first = sync()
        let ids = Set(xpRows().map(\.id))
        let second = sync()
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(xpRows().map(\.id)), ids, "no row is replaced or duplicated")
    }

    func testUndoingAWorkoutTakesItsXPBack() throws {
        let plan = finishedWorkout(on: day(0))
        try context.save()
        XCTAssertGreaterThan(sync().totalXP, 0)

        context.delete(plan)
        try context.save()
        let after = sync()
        XCTAssertEqual(after.totalXP, 0)
        XCTAssertTrue(xpRows().isEmpty)
    }

    func testProfileMirrorsTotalAndLevel() throws {
        let profile = UserProfile(appleID: "apple.1", username: "nic", displayName: "Nic")
        context.insert(profile)
        _ = finishedWorkout(on: day(0))
        try context.save()
        let summary = sync()
        XCTAssertEqual(profile.totalXP, summary.totalXP)
        XCTAssertEqual(profile.currentLevel, summary.level)
    }

    func testSummaryDaysCoverTheLastTwoWeeksAndWeekTotalsMatch() {
        _ = finishedWorkout(on: day(0))
        try? context.save()
        let summary = sync()
        XCTAssertGreaterThanOrEqual(summary.days.count, ArenaXPLedger.alwaysSentDays)
        XCTAssertEqual(summary.days.first?.day, ArenaCalendar.dayKey(now, calendar: calendar))
        XCTAssertEqual(summary.days.first?.workouts, 1)
        XCTAssertEqual(summary.days.map(\.xp).reduce(0, +), summary.totalXP)

        // The week the friends board ranks is the same ISO week the Arena shows.
        let weekStart = ArenaCalendar.weekStart(containing: now, calendar: calendar)
        let week = ArenaWeekStats(summary: summary, weekStart: weekStart, calendar: calendar)
        XCTAssertEqual(week.xp, summary.totalXP)
        XCTAssertEqual(week.workouts, 1)
        let lastWeek = ArenaWeekStats(
            summary: summary, weekStart: ArenaCalendar.previousWeekStart(before: now, calendar: calendar), calendar: calendar
        )
        XCTAssertEqual(lastWeek.xp, 0)
    }

    func testStreakComesFromTheOverallStreakRow() {
        XCTAssertEqual(ArenaXPLedger.streakDays(in: context), 0)
        context.insert(Streak(type: .overall, currentCount: 6, longestCount: 9))
        try? context.save()
        XCTAssertEqual(ArenaXPLedger.streakDays(in: context), 6)
    }

    // MARK: - Achievements

    func testTenthWorkoutUnlocksIronNoviceAndPaysItsXPOnce() throws {
        try AchievementLibrary.loadIfNeeded(context: context)
        for offset in -9 ... 0 {
            _ = finishedWorkout(on: day(offset))
        }
        try context.save()

        let novice = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Achievement>()).first { $0.badgeID == "iron_novice" }
        )
        XCTAssertFalse(novice.isEarned)
        let first = sync()
        XCTAssertTrue(novice.isEarned)
        XCTAssertTrue(first.newlyEarned.contains(novice.name))
        let reward = xpRows().filter { $0.source == .achievement }.reduce(0) { $0 + $1.amount }
        // Ten days in a row also earn the badges that count those days; every unlocked badge pays once.
        let earned = try context.fetch(FetchDescriptor<Achievement>()).filter(\.isEarned)
        XCTAssertGreaterThanOrEqual(earned.count, 1)
        XCTAssertEqual(reward, earned.reduce(0) { $0 + $1.effectiveXPReward })

        let again = sync()
        XCTAssertEqual(again.totalXP, first.totalXP, "the reward is not paid twice")
        XCTAssertTrue(again.newlyEarned.isEmpty)
    }

    func testNineWorkoutsAreNotEnough() throws {
        try AchievementLibrary.loadIfNeeded(context: context)
        for offset in -8 ... 0 {
            _ = finishedWorkout(on: day(offset))
        }
        try context.save()
        _ = sync()
        let novice = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Achievement>()).first { $0.badgeID == "iron_novice" }
        )
        XCTAssertFalse(novice.isEarned)
        XCTAssertEqual(novice.progressValue, 9)
    }

    func testUntrackedAchievementsStayLocked() throws {
        try AchievementLibrary.loadIfNeeded(context: context)
        _ = finishedWorkout(on: day(0))
        try context.save()
        _ = sync()
        let untracked = try (context.fetch(FetchDescriptor<Achievement>()))
            .filter { !ArenaAchievementTracker.isTracked($0.badgeID) }
        XCTAssertFalse(untracked.isEmpty)
        XCTAssertTrue(untracked.allSatisfy { !$0.isEarned })
    }
}
