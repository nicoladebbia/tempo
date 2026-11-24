//
// ScenarioSeedTests.swift
// Tempo
//
// `sim.sh qa --scenario` starting states and the local test-server hooks.
// A scenario that silently seeds nothing (a model init changed, a save path
// moved) would make every QA run on it meaningless, so each one is checked
// for the rows it promises.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ScenarioSeedTests: XCTestCase {
    private let onboardingKey = "tempo.onboarding.complete"
    private var savedOnboarding: Any?
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        savedOnboarding = UserDefaults.standard.object(forKey: onboardingKey)
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedOnboarding, forKey: onboardingKey)
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func count<T: PersistentModel>(_: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    func testFuelReadyCompletesTheFuelProfile() throws {
        ScenarioSeed.seed("fuel-ready", context: context)

        XCTAssertTrue(UserDefaults.standard.bool(forKey: onboardingKey))
        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<DietaryProfile>()).first)
        XCTAssertEqual(profile.currentWeightKg, 82)
        XCTAssertEqual(profile.primaryGoal, .leanGain)
        let daily = try XCTUnwrap(UserDailyPlanProfile.current(in: context))
        XCTAssertEqual(daily.weeklyRoutine?.typicalWakeMinutes, 7 * 60)
        XCTAssertEqual(daily.weeklyRoutine?.trainingDaysPerWeek, 4)
        XCTAssertEqual(count(PantryItem.self), 8)
        XCTAssertEqual(count(UserSettings.self), 1)
    }

    func testEatenBeforeUpdateHasEatenMealsWithoutUndoDetail() throws {
        ScenarioSeed.seed("eaten-before-update", context: context)

        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let eaten = meals.filter { $0.status == .eaten }
        XCTAssertEqual(eaten.count, 2)
        XCTAssertTrue(eaten.allSatisfy { $0.didDecrementPantry && $0.decrementDetailJSON == nil })
        let chicken = try XCTUnwrap(context.fetch(FetchDescriptor<PantryItem>()).first { $0.canonicalName == "chicken breast" })
        XCTAssertEqual(chicken.quantity, 1200 - 180)
    }

    func testCoachScenarioHasAMatchInThreeHoursAndAFreshCoachStore() throws {
        RecoveryCoachStore.shared.recordQuickAnswer(sessionID: "stale", bottles: 1)
        let now = Date()
        ScenarioSeed.seed("coach", context: context, now: now)

        XCTAssertTrue(UserDefaults.standard.bool(forKey: onboardingKey))
        let match = try XCTUnwrap(context.fetch(FetchDescriptor<Match>()).first)
        XCTAssertEqual(match.kickoff.timeIntervalSince(now), 3 * 3600, accuracy: 1)
        XCTAssertTrue(RecoveryCoachStore.shared.read().quickAnswers.isEmpty)
        let reminders = PreMatchWeighInPlan.reminders(kickoffs: [match.kickoff], now: now, lastWeighIn: nil)
        XCTAssertEqual(reminders.first?.fireDate.timeIntervalSince(now) ?? 0, 2 * 3600, accuracy: 1)
    }

    func testUsualMealsHasARealHabitYesterdayAndAFavourite() throws {
        ScenarioSeed.seed("usual-meals", context: context)

        let entries = UsualMeals.entries(in: context)
        let breakfasts = UsualMeals.ranked(entries, type: .breakfast)
        XCTAssertEqual(breakfasts.first?.days, 4)
        XCTAssertEqual(breakfasts.first?.title, "Oats, banana")
        let lunches = UsualMeals.ranked(entries, type: .lunch)
        XCTAssertEqual(lunches.map(\.days), [3], "the one-off tuna lunch is not a habit")
        XCTAssertEqual(UsualMeals.ranked(entries, type: .dinner).first?.days, 2)
        XCTAssertEqual(UsualMeals.yesterday(entries, type: .breakfast)?.foods.map(\.name), ["oats", "banana"])
        let favourite = try XCTUnwrap(context.fetch(FetchDescriptor<MealPreset>()).first)
        XCTAssertEqual(favourite.name, "Pre-training toast")
        XCTAssertTrue(favourite.isPinned)
    }

    func testGroceriesAndTrainingReuseTheirUITestSeeds() {
        ScenarioSeed.seed("groceries", context: context)
        XCTAssertGreaterThan(count(GroceryListItem.self), 0)

        ScenarioSeed.seed("training", context: context)
        XCTAssertEqual(count(TrainerProgram.self), 1)
    }

    func testTrainerFullFillsEverySectionOfTheTrainerPage() throws {
        let now = Date()
        ScenarioSeed.seed("trainer-full", context: context, now: now)

        let programs = try context.fetch(FetchDescriptor<TrainerProgram>())
        XCTAssertEqual(programs.count, 4)
        let active = try XCTUnwrap(programs.first { $0.isActive })
        XCTAssertEqual(active.changeLog.count, 3)
        XCTAssertEqual(active.changeLog.flatMap { $0.undoneSummaries ?? [] }.count, 1)
        XCTAssertEqual(active.skippedSessions.count, 1)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(active.skippedSessions.first).date, Calendar.current.startOfDay(for: now))
        XCTAssertEqual(programs.filter { !$0.isActive && $0.queuedActivationDate != nil }.count, 1)
        XCTAssertEqual(programs.filter { !$0.isActive && $0.queuedActivationDate == nil }.count, 2)

        // Every program has a believable completion, never 0 and never 100 percent.
        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>())
        for program in programs where program.queuedActivationDate == nil {
            let stats = TrainerProgramHistoryStats.stats(for: program, plans: plans, today: now)
            XCTAssertGreaterThan(stats.scheduled, 0, program.name)
            XCTAssertGreaterThan(stats.done, 0, program.name)
            XCTAssertLessThan(stats.done, stats.scheduled, program.name)
        }
    }

    func testEdgeSeedsExtremeValues() throws {
        ScenarioSeed.seed("edge", context: context)
        let items = try context.fetch(FetchDescriptor<PantryItem>())
        XCTAssertTrue(items.contains { $0.quantity == 0 })
        XCTAssertTrue(items.contains { $0.quantity == 99999 })
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlannedMeal>()).contains { $0.foods.isEmpty })
    }

    func testFreshAndUnknownSeedNothing() {
        UserDefaults.standard.set(false, forKey: onboardingKey)
        ScenarioSeed.seed("fresh", context: context)
        ScenarioSeed.seed("no-such-scenario", context: context)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: onboardingKey))
        XCTAssertEqual(count(PantryItem.self), 0)
        XCTAssertEqual(count(DietaryProfile.self), 0)
    }

    // MARK: - Personas ("people with history")

    private let personaNames = ["athlete", "picky-vegan", "exam-week", "injured", "lapsed-pro"]
    private var cal: Calendar {
        Calendar.current
    }

    private func today() -> Date {
        cal.startOfDay(for: Date())
    }

    private func daysAgo(_ date: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: date), to: today()).day ?? 0
    }

    private func fetchAll<T: PersistentModel>(_: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Every persona, seeded as if today were each of the seven weekdays, saves
    /// cleanly (unique constraints on DailyRecovery/DailyAccountability/…) and
    /// is never empty.
    func testEveryPersonaSeedsOnEveryWeekday() throws {
        for name in personaNames {
            for offset in 0 ..< 7 {
                let now = try XCTUnwrap(cal.date(byAdding: .day, value: offset, to: Date()))
                let freshContainer = try TempoModelContainer.create(inMemory: true)
                let ctx = freshContainer.mainContext
                ScenarioSeed.seed(name, context: ctx, now: now)
                XCTAssertNoThrow(try ctx.save(), "\(name) +\(offset)d did not save")
                XCTAssertGreaterThanOrEqual(try ctx.fetchCount(FetchDescriptor<WorkoutPlan>()), 8, "\(name) +\(offset)d: no workouts")
                XCTAssertGreaterThan(try ctx.fetchCount(FetchDescriptor<PlannedMeal>()), 50, "\(name) +\(offset)d: no meals")
                XCTAssertGreaterThan(try ctx.fetchCount(FetchDescriptor<DailyRecovery>()), 14, "\(name) +\(offset)d: no recovery")
            }
        }
    }

    func testPersonasAreDeterministic() throws {
        let now = Date()
        func digest(_ name: String) throws -> [Double] {
            let container = try TempoModelContainer.create(inMemory: true)
            let ctx = container.mainContext
            defer { withExtendedLifetime(container) {} }
            ScenarioSeed.seed(name, context: ctx, now: now)
            let recovery = try ctx.fetch(FetchDescriptor<DailyRecovery>(sortBy: [SortDescriptor(\.date)]))
            let meals = try ctx.fetch(FetchDescriptor<PlannedMeal>())
            return recovery.map(\.recoveryScore) + [meals.reduce(0) { $0 + $1.totalCalories }]
        }
        for name in personaNames {
            XCTAssertEqual(try digest(name), try digest(name), "\(name) is not deterministic")
        }
    }

    func testAthleteHasEightWeeksOfProgressiveTraining() throws {
        ScenarioSeed.seed("athlete", context: context)

        let workouts = fetchAll(WorkoutPlan.self).filter { $0.status == .completed }
        let oldest = try XCTUnwrap(workouts.map(\.date).min())
        XCTAssertGreaterThanOrEqual(daysAgo(oldest), 8 * 7, "history must span 8 weeks")
        // 8 full weeks (Mon/Tue/Thu/Fri) = 32, plus this week's sessions before today (0-4, by weekday).
        XCTAssertTrue((32 ... 36).contains(workouts.count), "4 sessions a week for 8 weeks, got \(workouts.count)")
        XCTAssertTrue(workouts.allSatisfy { $0.date < today() }, "today's session is left for the app to plan")

        // Every session wrote the same history row the app writes on finish.
        let history = fetchAll(ExerciseHistory.self)
        for plan in workouts {
            XCTAssertTrue(history.contains { $0.workoutPlanID == plan.id }, "no ExerciseHistory for \(plan.date)")
            XCTAssertGreaterThan(plan.totalVolume, 2000)
        }

        // Progressive overload: bench e1RM climbs; PRs exist and agree with history.
        let bench = try XCTUnwrap(fetchAll(Exercise.self).first { $0.name == "Barbell Bench Press" })
        let benchHistory = (bench.history ?? []).sorted { $0.date < $1.date }
        XCTAssertGreaterThanOrEqual(benchHistory.count, 8)
        let early = try XCTUnwrap(benchHistory.first?.estimated1RM)
        let late = try XCTUnwrap(benchHistory.last?.estimated1RM)
        XCTAssertGreaterThan(late, early + 5)
        XCTAssertGreaterThan(count(PersonalRecord.self), 20)
        for exercise in fetchAll(Exercise.self) where exercise.allTimePR != nil {
            let bestHistory = (exercise.history ?? []).compactMap(\.estimated1RM).max() ?? 0
            XCTAssertEqual(exercise.allTimePR ?? 0, bestHistory, accuracy: 0.01, "PR list and history disagree for \(exercise.name)")
        }
    }

    func testAthleteBodyweightTrendsUpAboutAQuarterKiloAWeek() throws {
        ScenarioSeed.seed("athlete", context: context)
        let weighIns = fetchAll(BodyComposition.self).compactMap { row -> AdaptiveExpenditure.WeighIn? in
            row.weightKg.map { AdaptiveExpenditure.WeighIn(date: row.date, kg: $0) }
        }
        let trend = try XCTUnwrap(AdaptiveExpenditure.weightTrend(weighIns))
        XCTAssertEqual(trend.kgPerDay * 7, 0.25, accuracy: 0.06)
        let profile = try XCTUnwrap(fetchAll(DietaryProfile.self).first)
        let latest = try XCTUnwrap(weighIns.max { $0.date < $1.date })
        XCTAssertEqual(profile.currentWeightKg, latest.kg, accuracy: 0.001, "Fuel profile weight must match the latest weigh-in")
    }

    func testBodyProgressHasWeighInsWithBodyFatSleepStagesAndThreePhotos() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "scenario-photos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let photoStore = ProgressPhotoStore(folder: folder)
        ScenarioSeed.seed("body-progress", context: context, photoStore: photoStore)

        // Weigh-ins: all three readings, one real measurement a day, trending up.
        let snapshots = fetchAll(BodyComposition.self).map(BodySnapshot.init)
        let measurements = BodyProgress.measurements(from: snapshots)
        XCTAssertGreaterThan(measurements.count, 20)
        XCTAssertTrue(measurements.allSatisfy { $0.weightKg != nil && $0.bodyFatPercent != nil && $0.leanMassKg != nil })
        let weight = BodyProgress.series(.weight, from: measurements, days: nil, now: Date())
        let trend = try XCTUnwrap(BodyProgress.trend(of: weight))
        XCTAssertEqual(trend.weeklyRate ?? 0, 0.25, accuracy: 0.08)

        // The Body page's sleep stages and week of recovery.
        let recovery = fetchAll(DailyRecovery.self)
        let todayRow = try XCTUnwrap(recovery.first { cal.isDate($0.date, inSameDayAs: today()) })
        XCTAssertNotNil(SleepStageMinutes(
            deep: todayRow.deepSleepMin, rem: todayRow.remSleepMin, light: todayRow.lightSleepMin, awake: todayRow.awakeMin
        ))
        XCTAssertGreaterThanOrEqual(
            RecoveryWindow.select(recovery.map(RecoveryViewModel.reading(from:)), days: 7, endingOn: Date()).count, 6
        )

        // Photos: three, oldest 8 weeks ago, newest today.
        let photos = photoStore.photos()
        XCTAssertEqual(photos.count, 3)
        XCTAssertTrue(try cal.isDate(XCTUnwrap(photos.first).date, inSameDayAs: today()))
        let oldest = try XCTUnwrap(photos.last).date
        XCTAssertEqual(cal.dateComponents([.day], from: oldest, to: Date()).day, 56)

        // Seeding again must not double the photos.
        ScenarioSeed.seed("body-progress", context: context, photoStore: photoStore)
        XCTAssertEqual(photoStore.photos().count, 3)
    }

    func testAthleteMealsHitTheirTargetsAndFeedTheAdaptiveEstimate() throws {
        ScenarioSeed.seed("athlete", context: context)
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: today()))
        let totals = EatenNutritionHistory.dailyTotals(in: context, days: 56, endingOn: yesterday)
        XCTAssertGreaterThanOrEqual(totals.filter(\.hasData).count, 54, "meals logged on ~95%+ of days")

        // Per-day target = the plan's own baselines; eaten stays within 10% on full days.
        let meals = fetchAll(PlannedMeal.self)
        var checked = 0
        for day in totals where day.mealsEaten == 4 {
            let planned = meals.filter { cal.isDate($0.dayDate, inSameDayAs: day.date) }.reduce(0.0) { $0 + $1.planBaseline.calories }
            XCTAssertEqual(Double(day.calories), planned, accuracy: planned * 0.10, "\(day.date) off target")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 45)

        // Dashboard Fuel target (via the shared calculator) is today's plan.
        let todayMeals = meals.filter { cal.isDate($0.dayDate, inSameDayAs: today()) }
        XCTAssertEqual(todayMeals.count, 4)
        let target = NutritionTargetCalculator.targetsForToday(in: context)
        XCTAssertEqual(Double(target.calories), todayMeals.reduce(0.0) { $0 + $1.planBaseline.calories }, accuracy: 1)
        XCTAssertEqual(todayMeals.filter { $0.status == .eaten }.count, 2)

        // Lean-gain intake plus +0.25 kg/week reads as a believable maintenance level.
        let observation = try XCTUnwrap(AdaptiveExpenditure.observe(in: context))
        XCTAssertTrue((2400 ... 3600).contains(observation.kcal), "observed maintenance \(observation.kcal)")
        XCTAssertEqual(observation.trendKgPerWeek, 0.25, accuracy: 0.1)
    }

    func testAthleteRecoveryIsMostlyGreenAndStreakIsLongAndConsistent() throws {
        ScenarioSeed.seed("athlete", context: context)
        let recovery = fetchAll(DailyRecovery.self)
        XCTAssertGreaterThanOrEqual(recovery.count, 57)
        XCTAssertTrue(recovery.contains { cal.isDate($0.date, inSameDayAs: today()) }, "the Recovery tab must not invent a 0% day")
        let green = recovery.filter { $0.recoveryZone == .green }.count
        XCTAssertGreaterThan(Double(green) / Double(recovery.count), 0.65)
        XCTAssertLessThan(Double(recovery.filter { $0.recoveryZone == .red }.count) / Double(recovery.count), 0.06)
        XCTAssertTrue(recovery.allSatisfy { (35 ... 110).contains($0.hrvRmssd ?? 0) && (44 ... 70).contains($0.restingHR ?? 0) })

        // Streak the Lockdown screen shows == trailing run of complete days.
        let days = fetchAll(DailyAccountability.self).filter { $0.date < today() }.sorted { $0.date > $1.date }
        var run = 0
        for day in days {
            guard day.allComplete else {
                break
            }
            run += 1
        }
        let streak = try XCTUnwrap(fetchAll(Streak.self).first { $0.type == .overall })
        XCTAssertEqual(streak.currentCount, run)
        XCTAssertGreaterThanOrEqual(run, 45)
        XCTAssertGreaterThanOrEqual(streak.longestCount, streak.currentCount)
        XCTAssertTrue(streak.isActive)

        // Same days across modules: a completed Training non-negotiable <=> a completed workout.
        let trainedDays = Set(fetchAll(WorkoutPlan.self).filter { $0.status == .completed }.map(\.date))
        for day in days {
            for row in day.nonNegotiableProgress ?? [] where row.nonNegotiable?.type == .train {
                XCTAssertEqual(row.isCompleted, trainedDays.contains(day.date), "training NN vs workout on \(day.date)")
            }
            // Study sessions add up to the day's study minutes.
            XCTAssertEqual((day.studySessions ?? []).reduce(0) { $0 + $1.durationMinutes }, day.totalStudyMinutes)
        }
    }

    func testAthleteScoreTrendAndWeeklyPlansArePresent() {
        ScenarioSeed.seed("athlete", context: context)
        XCTAssertGreaterThanOrEqual(count(DailyScoreEntry.self), 7)
        let plans = fetchAll(WeeklyMealPlan.self)
        XCTAssertEqual(plans.filter(\.isActive).count, 1, "only this week's plan is live")
        XCTAssertGreaterThanOrEqual(plans.count, 9)
        XCTAssertTrue(plans.filter(\.isActive).allSatisfy(\.coversToday))
    }

    func testPickyVeganMealsAndPantryRespectEveryRestriction() throws {
        ScenarioSeed.seed("picky-vegan", context: context)
        let profile = try XCTUnwrap(fetchAll(DietaryProfile.self).first)
        XCTAssertTrue(profile.isVegan)
        XCTAssertTrue(profile.isNutFree)
        XCTAssertTrue(profile.allergies.contains("peanuts"))
        for disliked in ["soy", "mushrooms", "cilantro"] {
            XCTAssertTrue(profile.dislikedFoods.contains(disliked))
        }

        let meals = fetchAll(PlannedMeal.self)
        let eaten = meals.filter { $0.status == .eaten }
        let span = try XCTUnwrap(eaten.map(\.dayDate).min())
        XCTAssertGreaterThanOrEqual(daysAgo(span), 21)
        XCTAssertGreaterThan(eaten.count, 60)
        let names = meals.flatMap(\.foods).map(\.name) + fetchAll(PantryItem.self).flatMap { [$0.canonicalName, $0.displayName] }
        for name in names {
            for banned in PersonaFoods.veganForbidden {
                XCTAssertFalse(name.lowercased().contains(banned), "'\(name)' breaks a restriction ('\(banned)')")
            }
        }
        XCTAssertGreaterThanOrEqual(count(PantryItem.self), 15)
    }

    func testExamWeekSleepDropsRecoveryTurnsAndWorkoutsThinOut() throws {
        ScenarioSeed.seed("exam-week", context: context)
        let recovery = fetchAll(DailyRecovery.self)
        func rows(_ range: ClosedRange<Int>) -> [DailyRecovery] {
            recovery.filter { range.contains(daysAgo($0.date)) }
        }
        func mean(_ values: [Double]) -> Double {
            values.reduce(0, +) / Double(max(values.count, 1))
        }
        let crunch = rows(0 ... 5)
        let before = rows(6 ... 27)
        XCTAssertEqual(crunch.count, 6)
        XCTAssertLessThan(mean(crunch.compactMap(\.sleepHours)), mean(before.compactMap(\.sleepHours)) - 1.25)
        XCTAssertLessThan(mean(crunch.map(\.recoveryScore)), mean(before.map(\.recoveryScore)) - 20)
        XCTAssertLessThan(mean(crunch.compactMap(\.hrvRmssd)), mean(before.compactMap(\.hrvRmssd)) * 0.8)
        XCTAssertGreaterThan(mean(crunch.compactMap(\.restingHR)), mean(before.compactMap(\.restingHR)) + 3)
        XCTAssertGreaterThanOrEqual(crunch.filter { $0.recoveryZone != .green }.count, 5)
        XCTAssertTrue(rows(0 ... 0).allSatisfy { $0.recoveryZone == .red }, "today is a red day")
        XCTAssertGreaterThan(before.filter { $0.recoveryZone == .green }.count, before.count / 2)

        let workouts = fetchAll(WorkoutPlan.self).filter { $0.status == .completed }
        XCTAssertEqual(workouts.filter { daysAgo($0.date) <= 3 }.count, 0)
        XCTAssertGreaterThanOrEqual(workouts.filter { daysAgo($0.date) > 5 }.count, 9)

        // Study went up while everything else went down; the sessions add up.
        let accountability = fetchAll(DailyAccountability.self)
        let crunchStudy = accountability.filter { (1 ... 5).contains(daysAgo($0.date)) }.map { Double($0.totalStudyMinutes) }
        let earlierStudy = accountability.filter { daysAgo($0.date) > 5 }.map { Double($0.totalStudyMinutes) }
        XCTAssertGreaterThan(mean(crunchStudy), mean(earlierStudy) * 1.4)
        XCTAssertGreaterThan(count(StudySession.self), 60)
        for day in accountability {
            XCTAssertEqual((day.studySessions ?? []).reduce(0) { $0 + $1.durationMinutes }, day.totalStudyMinutes)
        }
        let settings = try XCTUnwrap(fetchAll(UserSettings.self).first)
        XCTAssertTrue(settings.examMode)
        XCTAssertEqual(try daysAgo(XCTUnwrap(settings.examModeEndDate)), -4)
        // The training and overall streaks broke when the workouts stopped; study didn't.
        let streaks = Dictionary(uniqueKeysWithValues: fetchAll(Streak.self).map { ($0.type, $0) })
        XCTAssertEqual(streaks[.overall]?.currentCount, 0)
        XCTAssertGreaterThanOrEqual(streaks[.study]?.currentCount ?? 0, 10)
    }

    func testInjuredHasSixWeeksThenAPauseAndAKneeReportFourDaysAgo() throws {
        ScenarioSeed.seed("injured", context: context)
        let workouts = fetchAll(WorkoutPlan.self).filter { $0.status == .completed }.sorted { $0.date < $1.date }
        XCTAssertGreaterThanOrEqual(try daysAgo(XCTUnwrap(workouts.first).date), 6 * 7)
        XCTAssertGreaterThanOrEqual(workouts.count, 21)
        XCTAssertEqual(workouts.filter { daysAgo($0.date) < 4 }.count, 0, "nothing trained since the injury")

        // The cut-short session: 2 working squat sets logged, the rest pain-skipped.
        let last = try XCTUnwrap(workouts.last)
        XCTAssertEqual(daysAgo(last.date), 4)
        XCTAssertEqual(last.completedSets, 2)
        XCTAssertGreaterThan(last.totalSets, last.completedSets)

        let pauses = fetchAll(TrainingPause.self)
        let covering = try XCTUnwrap(TrainingPauseSchedule.coveringPause(pauses, on: Date()))
        XCTAssertEqual(covering.reason, .injured)
        XCTAssertEqual(daysAgo(covering.startDate), 4)
        XCTAssertNotNil(covering.plannedEndDate)

        let reports = fetchAll(PainReport.self)
        XCTAssertTrue(reports.contains { $0.bodyArea == .knee && daysAgo($0.date) == 4 && $0.severity >= 6 })
        let squat = try XCTUnwrap(fetchAll(Exercise.self).first { $0.name == "Barbell Back Squat" })
        XCTAssertNotNil(PainCaution.recentReport(for: squat.id, in: reports), "the squat must carry a pain caution")

        let streaks = Dictionary(uniqueKeysWithValues: fetchAll(Streak.self).map { ($0.type, $0) })
        XCTAssertEqual(streaks[.training]?.currentCount, 0)
        XCTAssertGreaterThan(streaks[.training]?.longestCount ?? 0, 10)
        XCTAssertGreaterThan(streaks[.meals]?.currentCount ?? 0, 10, "eating carried on through the pause")
    }

    func testLapsedProHasTenWeeksThatStopThreeWeeksAgo() throws {
        ScenarioSeed.seed("lapsed-pro", context: context)
        func newest(_ dates: [Date], _ what: String) throws -> Int {
            try daysAgo(XCTUnwrap(dates.max(), "no \(what)"))
        }
        func oldest(_ dates: [Date]) -> Int {
            daysAgo(dates.min() ?? Date())
        }
        let workouts = fetchAll(WorkoutPlan.self).map(\.date)
        let eaten = fetchAll(PlannedMeal.self).filter { $0.status == .eaten }.map(\.dayDate)
        let recovery = fetchAll(DailyRecovery.self).map(\.date)
        let weights = fetchAll(BodyComposition.self).map(\.date)
        let days = fetchAll(DailyAccountability.self).map(\.date)
        let studies = fetchAll(StudySession.self).map(\.startTime)
        let history = fetchAll(ExerciseHistory.self).map(\.date)
        let records = fetchAll(PersonalRecord.self).map(\.date)
        for (what, dates) in [
            ("workouts", workouts), ("meals", eaten), ("recovery", recovery), ("weigh-ins", weights),
            ("accountability", days), ("study", studies), ("exercise history", history), ("PRs", records),
        ] {
            XCTAssertGreaterThanOrEqual(try newest(dates, what), 22, "\(what) logged inside the last 21 days")
            XCTAssertGreaterThanOrEqual(oldest(dates), 9 * 7, "\(what) should span ~10 weeks")
        }
        XCTAssertTrue(fetchAll(DailyScoreEntry.self).allSatisfy { daysAgo($0.date) >= 22 })
        XCTAssertGreaterThan(workouts.count, 30)

        // Nothing live: no active plan, no pause, no pain; the streak is broken but remembers its best.
        XCTAssertTrue(fetchAll(WeeklyMealPlan.self).allSatisfy { !$0.isActive })
        XCTAssertEqual(count(TrainingPause.self), 0)
        XCTAssertEqual(count(PainReport.self), 0)
        let overall = try XCTUnwrap(fetchAll(Streak.self).first { $0.type == .overall })
        XCTAssertEqual(overall.currentCount, 0)
        XCTAssertGreaterThan(overall.longestCount, 30)
        XCTAssertFalse(overall.isActive)
        XCTAssertGreaterThanOrEqual(try daysAgo(XCTUnwrap(overall.lastCompletedDate)), 22)
        // The fresh food in the pantry went off while they were away.
        XCTAssertTrue(fetchAll(PantryItem.self).contains { ($0.useBy ?? .distantFuture) < Date() })
    }

    // MARK: - TestServer

    func testTestServerOnlyAcceptsLoopbackURLs() {
        XCTAssertEqual(TestServer.loopbackURL("http://127.0.0.1:58080")?.port, 58080)
        XCTAssertNotNil(TestServer.loopbackURL("http://localhost:58080"))
        XCTAssertNil(TestServer.loopbackURL("https://api.tempo.app"))
        XCTAssertNil(TestServer.loopbackURL("http://127.0.0.1.evil.com"))
        XCTAssertNil(TestServer.loopbackURL("off"))
        XCTAssertNil(TestServer.loopbackURL(nil))
    }

    func testTestServerReadsTheValueAfterAFlag() {
        let args = ["Tempo", "-tempoAPIBaseURL", "http://127.0.0.1:58080", "-tempoTestUserID"]
        XCTAssertEqual(TestServer.argument("-tempoAPIBaseURL", in: args), "http://127.0.0.1:58080")
        XCTAssertNil(TestServer.argument("-tempoTestUserID", in: args))
        XCTAssertNil(TestServer.argument("-missing", in: args))
    }
}
