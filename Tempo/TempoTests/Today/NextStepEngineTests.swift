//
// NextStepEngineTests.swift
// TempoTests
//
// The one next-step engine: what it picks on Today, and that every place that
// shows it (workout summary, after a meal, after focus, end of Recovery,
// Lockdown all done) never offers the thing that was just done.
//

@testable import Tempo
import XCTest

// MARK: - NextStepEngineTests

final class NextStepEngineTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    private func snapshot(
        workout: TodaySnapshot.Workout.Status = .none,
        name: String? = nil,
        inProgress: Bool = false,
        hasSource: Bool = true,
        calories: Int? = 1200,
        tasks: [Bool] = [],
        studyMinutes: Int = 0,
        studyTarget: Int = 0,
        meal: TodaySnapshot.Meal? = nil
    ) -> TodaySnapshot {
        TodaySnapshot(
            day: day,
            firstName: "Nicola",
            score: 70,
            workout: .init(status: workout, name: name, inProgress: inProgress, durationMinutes: nil),
            recovery: .init(
                score: 78, sleepHours: 7.9, sleepPerformance: 88, hrv: 74, restingHR: 52, hasSource: hasSource
            ),
            fuel: .init(
                calories: calories, calorieTarget: 3000, protein: 100, proteinTarget: 200,
                carbs: 100, carbsTarget: 300, fat: 40, fatTarget: 90, waterMl: 500, waterTargetMl: 3000
            ),
            tasks: tasks.enumerated().map { .init(id: UUID(), title: "Task \($0.offset)", done: $0.element) },
            study: .init(minutes: studyMinutes, targetMinutes: studyTarget, nextExam: nil),
            streakDays: 3,
            steps: 4000,
            stepsTarget: 10000,
            moveConnected: true,
            nextMeal: meal
        )
    }

    private func lunch(imminent: Bool = false) -> TodaySnapshot.Meal {
        .init(id: UUID(), name: "Lunch", time: "12:30", calories: 700, protein: 50, imminent: imminent)
    }

    // MARK: Today

    func testPlannedSessionComesFirstInTheDay() {
        let step = NextStepEngine.next(for: snapshot(workout: .planned, name: "Push", meal: lunch()), hour: 10)
        XCTAssertEqual(step?.action, .workout(name: "Push", resume: false))
        XCTAssertEqual(step?.buttonTitle, "Start session")
        XCTAssertEqual(step?.line, "Next: Push session.")
    }

    func testLateInTheDayTheMealBeatsAnUnstartedSession() {
        let meal = lunch()
        let step = NextStepEngine.next(for: snapshot(workout: .planned, name: "Push", meal: meal), hour: 22)
        XCTAssertEqual(step?.action, .meal(meal))
    }

    func testAStartedSessionAlwaysWins() {
        let step = NextStepEngine.next(
            for: snapshot(workout: .planned, name: "Push", inProgress: true, meal: lunch()), hour: 23
        )
        XCTAssertEqual(step?.action, .workout(name: "Push", resume: true))
        XCTAssertEqual(step?.buttonTitle, "Resume session")
    }

    func testRestDayWithATrackerOpensRecovery() {
        let step = NextStepEngine.next(for: snapshot(workout: .rest, tasks: [true]), hour: 10)
        XCTAssertEqual(step?.action, .rest)
        XCTAssertEqual(step?.buttonTitle, "Open recovery")
    }

    func testDayOneWithNoTrackerAndNothingEatenAsksForAFirstMeal() {
        let step = NextStepEngine.next(for: snapshot(workout: .none, hasSource: false, calories: 0), hour: 9)
        XCTAssertEqual(step?.action, .firstMeal)
    }

    func testStudyThenTasksThenAllDone() {
        XCTAssertEqual(
            NextStepEngine.next(for: snapshot(workout: .completed, tasks: [true], studyMinutes: 10, studyTarget: 60), hour: 15)?.action,
            .focus(minutesLeft: 50)
        )
        XCTAssertEqual(
            NextStepEngine.next(for: snapshot(workout: .completed, tasks: [true, false]), hour: 15)?.action,
            .tasks(left: 1)
        )
        let done = NextStepEngine.next(for: snapshot(workout: .completed, tasks: [true]), hour: 15)
        XCTAssertEqual(done?.action, .allDone)
        XCTAssertNil(done?.buttonTitle)
    }

    func testNoTasksAtAllOffersToSetThemUp() {
        XCTAssertEqual(
            NextStepEngine.next(for: snapshot(workout: .completed, tasks: []), hour: 15)?.action,
            .setUpTasks
        )
    }

    func testTodayNeverReturnsNil() {
        for hour in [0, 6, 12, 18, 21, 23] {
            XCTAssertNotNil(NextStepEngine.next(for: snapshot(workout: .completed, tasks: [true]), hour: hour))
        }
    }

    // MARK: Other places

    func testAfterAWorkoutTheSessionIsNotOfferedAgain() {
        let step = NextStepEngine.next(
            for: snapshot(workout: .planned, name: "Push", tasks: [false], meal: lunch()), hour: 10, place: .workoutSummary
        )
        guard case .meal = step?.action else {
            return XCTFail("expected the next meal, got \(String(describing: step?.action))")
        }
    }

    func testAfterAMealTheMealIsNotOfferedAgain() {
        let step = NextStepEngine.next(
            for: snapshot(workout: .completed, tasks: [false, false], meal: lunch(imminent: true)), hour: 12, place: .afterMeal
        )
        XCTAssertEqual(step?.action, .tasks(left: 2))
    }

    func testAfterFocusTheStudyBlockIsNotOfferedAgain() {
        let step = NextStepEngine.next(
            for: snapshot(workout: .completed, tasks: [false], studyMinutes: 0, studyTarget: 60), hour: 16, place: .afterFocus
        )
        XCTAssertEqual(step?.action, .tasks(left: 1))
    }

    func testAtTheEndOfRecoveryRestIsNotOfferedAgain() {
        let step = NextStepEngine.next(for: snapshot(workout: .rest, tasks: [false]), hour: 9, place: .recoveryEnd)
        XCTAssertEqual(step?.action, .tasks(left: 1))
    }

    func testWhenAllTasksAreDoneLockdownDoesNotOfferTasks() {
        let step = NextStepEngine.next(
            for: snapshot(workout: .planned, name: "Pull", tasks: [false, false]), hour: 9, place: .lockdownDone
        )
        XCTAssertEqual(step?.action, .workout(name: "Pull", resume: false))
    }

    func testPlacesSayNothingWhenTheDayIsFinished() {
        let done = snapshot(workout: .completed, tasks: [true])
        for place in NextStepPlace.allCases where place != .today {
            XCTAssertNil(NextStepEngine.next(for: done, hour: 20, place: place), "\(place)")
        }
    }

    func testTheOldChooseWrapperAgreesWithTheEngine() {
        let snap = snapshot(workout: .planned, name: "Legs", meal: lunch())
        XCTAssertEqual(TodayNextAction.choose(for: snap, hour: 10), NextStepEngine.choose(for: snap, hour: 10))
    }

    func testEveryActionHasWordsAndAButtonUnlessDone() {
        let actions: [TodayNextAction] = [
            .workout(name: "Push", resume: false), .workout(name: "Push", resume: true), .meal(lunch()), .rest,
            .firstMeal, .focus(minutesLeft: 30), .tasks(left: 1), .tasks(left: 3), .setUpTasks, .allDone,
        ]
        for action in actions {
            XCTAssertFalse(NextStepEngine.title(for: action).isEmpty)
            XCTAssertFalse(NextStepEngine.detail(for: action).isEmpty)
            XCTAssertFalse(NextStepEngine.line(for: action).isEmpty)
            XCTAssertEqual(NextStepEngine.button(for: action) == nil, action == .allDone)
        }
    }
}
