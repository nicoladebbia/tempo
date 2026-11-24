//
// StudySessionRemovalTests.swift
// TempoTests
//
// Deleting a focus session takes its minutes off the day total and the Study
// task together, so Today, Lockdown and the Study page keep agreeing. When it
// undoes a Study task finished today, the day's unlock goes back too.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class StudySessionRemovalTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: AccountabilityViewModel!

    override func setUp() async throws {
        let schema = Schema([
            DailyAccountability.self, NonNegotiableProgress.self, NonNegotiable.self,
            StudySession.self, Streak.self,
        ])
        container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        viewModel = AccountabilityViewModel()
    }

    /// Today with a 60-minute Study task and one deep-work session already counted.
    private func loadStudyDay(minutes: Int = 40) -> (task: NonNegotiableProgress, day: DailyAccountability, session: StudySession) {
        context.insert(NonNegotiable(name: "Study", type: .study, targetValue: 60, order: 0))
        try? context.save()
        viewModel.loadToday(modelContext: context)
        let task = viewModel.progressItems.first { $0.nonNegotiable?.type == .study }!
        let day = viewModel.accountability!
        let session = deepWork(minutes: minutes, on: day)
        day.totalStudyMinutes = minutes
        task.currentValue = Double(minutes)
        try? context.save()
        return (task, day, session)
    }

    @discardableResult
    private func deepWork(minutes: Int, on day: DailyAccountability) -> StudySession {
        let session = StudySession(
            startTime: Date(), durationMinutes: minutes, subject: "Maths", sessionType: .deepWork,
            dailyAccountability: day
        )
        context.insert(session)
        return session
    }

    private func sessionCount() -> Int {
        (try? context.fetch(FetchDescriptor<StudySession>()))?.count ?? 0
    }

    // MARK: Maths

    func testMinutesLeftNeverGoesBelowZero() {
        XCTAssertEqual(StudySessionRemoval.minutesLeft(current: 50, removing: 20), 30)
        XCTAssertEqual(StudySessionRemoval.minutesLeft(current: 10, removing: 25), 0)
        XCTAssertEqual(StudySessionRemoval.minutesLeft(current: 10, removing: -5), 10)
    }

    func testTheCreditedMinutesAreWhatTheTimerAdded() {
        // Two finished pomodoros ran 55 minutes with a break, and were credited 50.
        XCTAssertEqual(
            StudySessionRemoval.creditedMinutes(durationMinutes: 55, completedPomodoros: 2, sessionType: .pomodoro), 50
        )
        // A 50-minute pomodoro length: two pomodoros ran 105 minutes, credited 100.
        XCTAssertEqual(
            StudySessionRemoval.creditedMinutes(durationMinutes: 105, completedPomodoros: 2, sessionType: .pomodoro), 100
        )
        // Never more than the session ran.
        XCTAssertEqual(
            StudySessionRemoval.creditedMinutes(durationMinutes: 20, completedPomodoros: 1, sessionType: .pomodoro), 20
        )
        // A cancelled pomodoro session was never credited.
        XCTAssertEqual(
            StudySessionRemoval.creditedMinutes(durationMinutes: 12, completedPomodoros: 0, sessionType: .pomodoro), 0
        )
        // Deep work counts what it ran.
        XCTAssertEqual(
            StudySessionRemoval.creditedMinutes(durationMinutes: 90, completedPomodoros: 0, sessionType: .deepWork), 90
        )
    }

    // MARK: Removal

    func testRemovingASessionTakesItsMinutesOffTheDayAndTheTask() {
        let (task, day, session) = loadStudyDay(minutes: 40)
        StudySessionRemoval.remove(session, modelContext: context)

        XCTAssertEqual(day.totalStudyMinutes, 0)
        XCTAssertEqual(task.currentValue, 0)
        XCTAssertEqual(sessionCount(), 0)
    }

    func testOtherSessionsOnTheDayKeepTheirMinutes() {
        let (task, day, first) = loadStudyDay(minutes: 40)
        deepWork(minutes: 30, on: day)
        day.totalStudyMinutes = 70
        task.currentValue = 70

        StudySessionRemoval.remove(first, modelContext: context)

        XCTAssertEqual(day.totalStudyMinutes, 30)
        XCTAssertEqual(task.currentValue, 30)
        XCTAssertEqual(sessionCount(), 1)
    }

    func testDeletingACancelledSessionTakesNothingOffTheDay() {
        let (task, day, _) = loadStudyDay(minutes: 40)
        let cancelled = StudySession(
            startTime: Date(), durationMinutes: 12, sessionType: .pomodoro, completedPomodoros: 0, dailyAccountability: day
        )
        context.insert(cancelled)

        StudySessionRemoval.remove(cancelled, modelContext: context)

        XCTAssertEqual(day.totalStudyMinutes, 40)
        XCTAssertEqual(task.currentValue, 40)
    }

    func testRemovingTheMinutesThatCompletedTheTaskReopensItAndTakesTheUnlockBack() {
        let (task, day, session) = loadStudyDay(minutes: 70)
        viewModel.updateItemProgress(task, value: 70, modelContext: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(day.leisureUnlocked)

        StudySessionRemoval.remove(session, modelContext: context)

        XCTAssertEqual(task.currentValue, 0)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
        XCTAssertFalse(day.leisureUnlocked)
        XCTAssertNil(day.unlockedAt)
    }

    func testATaskTickedByHandIsNotReopenedByDeletingASmallSession() {
        // 25 minutes of sessions, but the task was ticked done by hand (60 of 60).
        let (task, day, session) = loadStudyDay(minutes: 25)
        viewModel.completeItem(task, modelContext: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(day.leisureUnlocked)

        StudySessionRemoval.remove(session, modelContext: context)

        XCTAssertEqual(day.totalStudyMinutes, 0, "the minutes still come off the day")
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.currentValue, 60)
        XCTAssertTrue(day.leisureUnlocked)
    }

    func testATaskThatStaysCompleteKeepsTheUnlock() {
        // Two sessions finished the task; deleting the short one leaves it above the target.
        let (task, day, first) = loadStudyDay(minutes: 20)
        deepWork(minutes: 70, on: day)
        viewModel.updateItemProgress(task, value: 90, modelContext: context)
        day.totalStudyMinutes = 90
        XCTAssertTrue(day.leisureUnlocked)

        StudySessionRemoval.remove(first, modelContext: context)

        XCTAssertEqual(task.currentValue, 70)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(day.leisureUnlocked)
    }

    func testASkippedStudyTaskIsLeftAlone() {
        let (task, day, session) = loadStudyDay(minutes: 40)
        task.isCompleted = true
        task.wasSkipped = true
        task.currentValue = 40

        StudySessionRemoval.remove(session, modelContext: context)

        XCTAssertEqual(day.totalStudyMinutes, 0)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(task.wasSkipped)
        XCTAssertEqual(task.currentValue, 40)
    }

    func testAnEarlierDaysRecordIsNotReopenedOrUnlockedAgain() throws {
        context.insert(NonNegotiable(name: "Study", type: .study, targetValue: 60, order: 0))
        try context.save()
        viewModel.loadToday(modelContext: context)
        let task = try XCTUnwrap(viewModel.progressItems.first { $0.nonNegotiable?.type == .study })
        let today = try XCTUnwrap(viewModel.accountability)
        let yesterdayDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today.date))
        let yesterday = DailyAccountability(date: yesterdayDate, leisureUnlocked: true, totalStudyMinutes: 70)
        context.insert(yesterday)
        let oldTask = NonNegotiableProgress(
            date: yesterdayDate, currentValue: 70, targetValue: 60, isCompleted: true,
            nonNegotiable: task.nonNegotiable, dailyAccountability: yesterday
        )
        context.insert(oldTask)
        let session = deepWork(minutes: 70, on: yesterday)
        try context.save()

        StudySessionRemoval.remove(session, modelContext: context)

        XCTAssertEqual(yesterday.totalStudyMinutes, 0)
        XCTAssertEqual(oldTask.currentValue, 0)
        XCTAssertTrue(oldTask.isCompleted, "a closed day keeps its record")
        XCTAssertTrue(yesterday.leisureUnlocked)
    }
}
