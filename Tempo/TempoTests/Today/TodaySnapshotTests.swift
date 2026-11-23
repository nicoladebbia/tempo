//
// TodaySnapshotTests.swift
// TempoTests
//
// The Today screen's pure rules: what the status line says, which single
// action is offered, and that a saved snapshot is always drawn in place of
// the loading state.
//

import XCTest
@testable import Tempo

final class TodaySnapshotTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    private func snapshot(
        score: Int? = 70,
        workout: TodaySnapshot.Workout.Status = .none,
        workoutName: String? = nil,
        inProgress: Bool = false,
        recovery: Int? = 78,
        tasks: [Bool] = [],
        studyMinutes: Int = 0,
        studyTarget: Int = 0,
        meal: TodaySnapshot.Meal? = nil
    ) -> TodaySnapshot {
        TodaySnapshot(
            day: day,
            firstName: "Nicola Debbia",
            score: score,
            workout: .init(status: workout, name: workoutName, inProgress: inProgress, durationMinutes: nil),
            recovery: .init(
                score: recovery, sleepHours: 7.9, sleepPerformance: 88, hrv: 74, restingHR: 52, hasSource: true
            ),
            fuel: .init(
                calories: 1747, calorieTarget: 3130, protein: 129, proteinTarget: 233,
                carbs: 176, carbsTarget: 333, fat: 58, fatTarget: 96, waterMl: 500, waterTargetMl: 3292
            ),
            tasks: tasks.enumerated().map { .init(id: UUID(), title: "Task \($0.offset)", done: $0.element) },
            study: .init(minutes: studyMinutes, targetMinutes: studyTarget, nextExam: nil),
            streakDays: 57,
            steps: 4200,
            stepsTarget: 10000,
            moveConnected: true,
            nextMeal: meal
        )
    }

    private func meal(imminent: Bool = false) -> TodaySnapshot.Meal {
        .init(id: UUID(), name: "Chicken rice bowl", time: "20:30", calories: 780, protein: 62, imminent: imminent)
    }

    // MARK: Status wording

    func testStatusListsWhatIsLeft() {
        let line = TodayStatus.line(for: snapshot(
            workout: .planned, workoutName: "Push", tasks: [false, false, true], studyMinutes: 50, studyTarget: 60
        ))
        XCTAssertEqual(line, "Still to do: Push session, 2 tasks and 10 min of study.")
    }

    func testStatusUsesSingularForOneTask() {
        XCTAssertEqual(TodayStatus.line(for: snapshot(tasks: [false])), "Still to do: 1 task.")
    }

    func testStatusWhenEverythingIsDone() {
        let line = TodayStatus.line(for: snapshot(workout: .completed, workoutName: "Push", tasks: [true]))
        XCTAssertEqual(line, "Everything on the list is done.")
    }

    func testStatusOnAClearedRestDay() {
        XCTAssertEqual(
            TodayStatus.line(for: snapshot(workout: .rest, tasks: [true])),
            "Rest day, list cleared. Eat and sleep well."
        )
    }

    func testStatusWarnsOnLowRecoveryOnlyWithASessionPlanned() {
        XCTAssertEqual(
            TodayStatus.line(for: snapshot(workout: .planned, workoutName: "Push", recovery: 28)),
            "Recovery is low at 28%. Go lighter today."
        )
        XCTAssertFalse(TodayStatus.line(for: snapshot(workout: .rest, recovery: 28)).contains("Recovery is low"))
    }

    /// A new user has no score and no recovery: no alarm, just what to do.
    func testStatusForANewUserRaisesNoAlarm() {
        let line = TodayStatus.line(for: snapshot(score: nil, recovery: nil))
        XCTAssertEqual(line, "Log a meal or a session and your score appears here.")
        XCTAssertFalse(line.lowercased().contains("recovery"))
    }

    func testStatusNamesASessionInProgress() {
        let line = TodayStatus.line(for: snapshot(workout: .planned, workoutName: "Legs", inProgress: true))
        XCTAssertEqual(line, "Still to do: Legs in progress.")
    }

    // MARK: Next action

    func testPlannedSessionIsTheNextAction() {
        let action = TodayNextAction.choose(
            for: snapshot(workout: .planned, workoutName: "Push", tasks: [false], meal: meal()), hour: 10
        )
        XCTAssertEqual(action, .workout(name: "Push", resume: false))
    }

    func testStartedSessionOffersResumeEvenLate() {
        let action = TodayNextAction.choose(
            for: snapshot(workout: .planned, workoutName: "Push", inProgress: true, meal: meal()), hour: 22
        )
        XCTAssertEqual(action, .workout(name: "Push", resume: true))
    }

    func testLateInTheDayTheNextMealReplacesAnUnstartedSession() {
        let next = meal()
        let action = TodayNextAction.choose(
            for: snapshot(workout: .planned, workoutName: "Push", meal: next), hour: TodayNextAction.lateHour
        )
        XCTAssertEqual(action, .meal(next))
    }

    func testLateWithNoMealStillOffersTheSession() {
        let action = TodayNextAction.choose(for: snapshot(workout: .planned, workoutName: "Push"), hour: 22)
        XCTAssertEqual(action, .workout(name: "Push", resume: false))
    }

    func testRestDayOffersRecoveryUnlessAMealIsDueNow() {
        XCTAssertEqual(TodayNextAction.choose(for: snapshot(workout: .rest, meal: meal()), hour: 10), .rest)
        let due = meal(imminent: true)
        XCTAssertEqual(TodayNextAction.choose(for: snapshot(workout: .rest, meal: due), hour: 10), .meal(due))
    }

    func testAfterTheSessionTheNextMealComesFirst() {
        let next = meal()
        let action = TodayNextAction.choose(
            for: snapshot(workout: .completed, workoutName: "Push", tasks: [false], meal: next), hour: 15
        )
        XCTAssertEqual(action, .meal(next))
    }

    func testThenStudyThenTasksThenDone() {
        XCTAssertEqual(
            TodayNextAction.choose(
                for: snapshot(workout: .completed, tasks: [false], studyMinutes: 20, studyTarget: 60), hour: 15
            ),
            .focus(minutesLeft: 40)
        )
        XCTAssertEqual(
            TodayNextAction.choose(for: snapshot(workout: .completed, tasks: [false, true]), hour: 15),
            .tasks(left: 1)
        )
        XCTAssertEqual(TodayNextAction.choose(for: snapshot(workout: .completed, tasks: [true]), hour: 15), .allDone)
    }

    func testNoTasksYetOffersSettingThemUp() {
        XCTAssertEqual(TodayNextAction.choose(for: snapshot(workout: .none), hour: 9), .setUpTasks)
    }

    // MARK: Cache and first frame

    private func temporaryCache() -> TodayCache {
        TodayCache(url: FileManager.default.temporaryDirectory.appending(path: "today-\(UUID().uuidString).json"))
    }

    func testCacheRoundTripsOnTheSameDay() {
        let cache = temporaryCache()
        defer { cache.clear() }
        let saved = snapshot(workout: .planned, workoutName: "Push", tasks: [true, false], meal: meal())
        cache.save(saved)
        XCTAssertEqual(cache.load(now: day.addingTimeInterval(3600)), saved)
    }

    func testCacheIsEmptyBeforeAnythingWasSavedAndAfterClear() {
        let cache = temporaryCache()
        XCTAssertNil(cache.load())
        cache.save(snapshot())
        cache.clear()
        XCTAssertNil(cache.load())
    }

    /// Yesterday's progress must never be drawn as today's.
    func testCacheLoadedOnALaterDayDropsDayProgressButKeepsIdentity() throws {
        let cache = temporaryCache()
        defer { cache.clear() }
        cache.save(snapshot(workout: .completed, workoutName: "Push", tasks: [true, true], studyMinutes: 60, studyTarget: 60))
        let nextDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: day))
        let loaded = try XCTUnwrap(cache.load(now: nextDay.addingTimeInterval(8 * 3600)))

        XCTAssertEqual(loaded.day, nextDay)
        XCTAssertNil(loaded.score)
        XCTAssertNil(loaded.recovery.score)
        XCTAssertEqual(loaded.workout.status, .none)
        XCTAssertNil(loaded.fuel.calories)
        XCTAssertEqual(loaded.fuel.waterMl, 0)
        XCTAssertEqual(loaded.tasksDone, 0)
        XCTAssertEqual(loaded.study.minutes, 0)
        // Still you, same targets, same streak.
        XCTAssertEqual(loaded.firstName, "Nicola Debbia")
        XCTAssertEqual(loaded.fuel.calorieTarget, 3130)
        XCTAssertEqual(loaded.tasks.count, 2)
        XCTAssertEqual(loaded.streakDays, 57)
    }

    func testACorruptCacheFileIsIgnored() throws {
        let cache = temporaryCache()
        defer { cache.clear() }
        try Data("not json".utf8).write(to: cache.url)
        XCTAssertNil(cache.load())
    }

    /// The rule behind the instant first frame: with a saved snapshot, Today
    /// never shows its loading state, whatever the live load is doing.
    func testTodayNeverShowsLoadingWhenACachedStateExists() {
        let cached = snapshot()
        let whileLoading = TodayPhase.resolve(live: nil, cached: cached, error: nil)
        XCTAssertFalse(whileLoading.isLoading)
        XCTAssertEqual(whileLoading, .content(cached, isLive: false))

        let whenSyncFails = TodayPhase.resolve(live: nil, cached: cached, error: "Sync failed")
        XCTAssertEqual(whenSyncFails, .content(cached, isLive: false))
    }

    func testLiveDataReplacesTheCachedState() {
        let live = snapshot(score: 82)
        XCTAssertEqual(
            TodayPhase.resolve(live: live, cached: snapshot(), error: nil),
            .content(live, isLive: true)
        )
    }

    func testLoadingOnlyOnAFirstEverLaunch() {
        XCTAssertTrue(TodayPhase.resolve(live: nil, cached: nil, error: nil).isLoading)
        XCTAssertEqual(TodayPhase.resolve(live: nil, cached: nil, error: "Offline"), .failed("Offline"))
    }

    // MARK: Greeting and recovery

    func testGreetingUsesTheFirstNameAndTimeOfDay() {
        XCTAssertEqual(TodayGreeting.text(hour: 8, name: "Nicola Debbia"), "Good morning, Nicola")
        XCTAssertEqual(TodayGreeting.text(hour: 14, name: "Nicola"), "Good afternoon, Nicola")
        XCTAssertEqual(TodayGreeting.text(hour: 20, name: "Nicola"), "Good evening, Nicola")
        XCTAssertEqual(TodayGreeting.text(hour: 2, name: "Nicola"), "Still up, Nicola")
    }

    func testGreetingDropsThePlaceholderName() {
        XCTAssertEqual(TodayGreeting.text(hour: 8, name: "Athlete"), "Good morning")
        XCTAssertEqual(TodayGreeting.text(hour: 8, name: nil), "Good morning")
        XCTAssertEqual(TodayGreeting.text(hour: 8, name: "  "), "Good morning")
    }

    /// A zero score is "no reading": a new user must not see "0%".
    func testZeroRecoveryIsShownAsNoReading() {
        var body = BodyQuadrantData.empty
        body.recoveryScore = 0
        let none = TodaySnapshot.recovery(body: body, owned: .init(), whoopConnected: false)
        XCTAssertNil(none.score)
        XCTAssertFalse(none.hasSource)
    }

    /// The Recovery page's saved score is used when the Dashboard feed has none,
    /// so Today never says "connect" while Recovery shows a number.
    func testRecoveryFallsBackToTheSavedRow() {
        let fromRow = TodaySnapshot.recovery(
            body: .empty,
            owned: .init(recoveryScore: 78, sleepHours: 7.5, hrv: 74, restingHR: 52),
            whoopConnected: false
        )
        XCTAssertEqual(fromRow.score, 78)
        XCTAssertEqual(fromRow.hrv, 74)
        XCTAssertTrue(fromRow.hasSource)
    }
}
