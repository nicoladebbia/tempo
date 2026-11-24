//
// StudySessionRemovalTests.swift
// TempoTests
//
// Deleting a focus session takes its minutes off the day total and the Study
// task together, so Today, Lockdown and the Study page keep agreeing.
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

    /// Today with a 60-minute Study task and one 40-minute session already counted.
    private func loadStudyDay(minutes: Int = 40) -> (task: NonNegotiableProgress, day: DailyAccountability, session: StudySession) {
        context.insert(NonNegotiable(name: "Study", type: .study, targetValue: 60, order: 0))
        try? context.save()
        viewModel.loadToday(modelContext: context)
        let task = viewModel.progressItems.first { $0.nonNegotiable?.type == .study }!
        let day = viewModel.accountability!
        let session = StudySession(
            startTime: Date(), durationMinutes: minutes, subject: "Maths", dailyAccountability: day
        )
        context.insert(session)
        day.totalStudyMinutes = minutes
        task.currentValue = Double(minutes)
        try? context.save()
        return (task, day, session)
    }

    func testMinutesLeftNeverGoesBelowZero() {
        XCTAssertEqual(StudySessionRemoval.minutesLeft(current: 50, removing: 20), 30)
        XCTAssertEqual(StudySessionRemoval.minutesLeft(current: 10, removing: 25), 0)
        XCTAssertEqual(StudySessionRemoval.minutesLeft(current: 10, removing: -5), 10)
    }

    func testRemovingASessionTakesItsMinutesOffTheDayAndTheTask() {
        let (task, day, session) = loadStudyDay(minutes: 40)
        StudySessionRemoval.remove(session, modelContext: context)

        XCTAssertEqual(day.totalStudyMinutes, 0)
        XCTAssertEqual(task.currentValue, 0)
        XCTAssertTrue((try? context.fetch(FetchDescriptor<StudySession>()))?.isEmpty ?? false)
    }

    func testRemovingTheMinutesThatCompletedTheTaskReopensIt() {
        let (task, day, session) = loadStudyDay(minutes: 70)
        viewModel.completeItem(task, modelContext: context)
        XCTAssertTrue(task.isCompleted)
        task.currentValue = 70
        day.totalStudyMinutes = 70

        StudySessionRemoval.remove(session, modelContext: context)

        XCTAssertEqual(task.currentValue, 0)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
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

    func testOtherSessionsOnTheDayKeepTheirMinutes() {
        let (task, day, first) = loadStudyDay(minutes: 40)
        let second = StudySession(startTime: Date(), durationMinutes: 30, dailyAccountability: day)
        context.insert(second)
        day.totalStudyMinutes = 70
        task.currentValue = 70

        StudySessionRemoval.remove(first, modelContext: context)

        XCTAssertEqual(day.totalStudyMinutes, 30)
        XCTAssertEqual(task.currentValue, 30)
        XCTAssertEqual((try? context.fetch(FetchDescriptor<StudySession>()))?.count, 1)
    }
}
