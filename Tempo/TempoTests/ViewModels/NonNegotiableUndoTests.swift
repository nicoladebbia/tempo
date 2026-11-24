//
// NonNegotiableUndoTests.swift
// Tempo
//
// Undo after completing or skipping a non-negotiable puts back the task, the
// day's unlock and the habit streak, exactly as they were.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class NonNegotiableUndoTests: XCTestCase {
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

    /// One study task and one training task, loaded for today.
    private func loadTwoTasks() -> (study: NonNegotiableProgress, train: NonNegotiableProgress) {
        context.insert(NonNegotiable(name: "Study", type: .study, targetValue: 60, order: 0))
        context.insert(NonNegotiable(name: "Train", type: .train, targetValue: 1, order: 1))
        try? context.save()
        viewModel.loadToday(modelContext: context)
        let study = viewModel.progressItems.first { $0.nonNegotiable?.type == .study }!
        let train = viewModel.progressItems.first { $0.nonNegotiable?.type == .train }!
        return (study, train)
    }

    func testUndoCompleteReopensTheTaskAndRewindsTheHabitStreak() {
        let (study, _) = loadTwoTasks()
        XCTAssertEqual(viewModel.habitStreakCount(for: .study), 0)

        let undo = viewModel.completeItem(study, modelContext: context)
        XCTAssertTrue(study.isCompleted)
        XCTAssertEqual(study.currentValue, 60)
        XCTAssertEqual(viewModel.habitStreakCount(for: .study), 1)

        viewModel.undo(undo, modelContext: context)
        XCTAssertFalse(study.isCompleted)
        XCTAssertNil(study.completedAt)
        XCTAssertEqual(study.currentValue, 0)
        XCTAssertEqual(viewModel.habitStreakCount(for: .study), 0)
        XCTAssertNil(viewModel.habitStreaks[.study]?.lastCompletedDate)
        XCTAssertEqual(viewModel.completedCount, 0)
    }

    func testUndoSkipReopensTheTask() {
        let (_, train) = loadTwoTasks()

        let undo = viewModel.skipItem(train, modelContext: context)
        XCTAssertTrue(train.isCompleted)
        XCTAssertTrue(train.wasSkipped)

        viewModel.undo(undo, modelContext: context)
        XCTAssertFalse(train.isCompleted)
        XCTAssertFalse(train.wasSkipped)
        XCTAssertNil(train.completedAt)
    }

    func testUndoOfTheLastTaskTakesTheUnlockBack() {
        let (study, train) = loadTwoTasks()
        viewModel.completeItem(study, modelContext: context)
        XCTAssertFalse(viewModel.isLeisureUnlocked)

        let undo = viewModel.completeItem(train, modelContext: context)
        XCTAssertTrue(viewModel.isLeisureUnlocked)
        XCTAssertNotNil(viewModel.accountability?.unlockedAt)

        viewModel.undo(undo, modelContext: context)
        XCTAssertFalse(viewModel.isLeisureUnlocked)
        XCTAssertNil(viewModel.accountability?.unlockedAt)
        XCTAssertFalse(train.isCompleted)
        // The other task keeps what it had.
        XCTAssertTrue(study.isCompleted)
        XCTAssertEqual(viewModel.completedCount, 1)
    }

    func testUndoKeepsALongerStreakIntact() {
        let (study, _) = loadTwoTasks()
        let streak = viewModel.habitStreaks[.study]
        streak?.currentCount = 4
        streak?.longestCount = 9
        // Done yesterday, so completing today would extend the run.
        streak?.lastCompletedDate = Calendar.current.date(
            byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())
        )

        let undo = viewModel.completeItem(study, modelContext: context)
        XCTAssertEqual(streak?.currentCount, 5)

        viewModel.undo(undo, modelContext: context)
        XCTAssertEqual(streak?.currentCount, 4)
        XCTAssertEqual(streak?.longestCount, 9)
    }
}
