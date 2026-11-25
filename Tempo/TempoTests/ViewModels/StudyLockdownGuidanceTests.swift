//
// StudyLockdownGuidanceTests.swift
// Tempo
//
// Round 3, guidance pass, Study and Lockdown: Undo for a progress tap and for
// added tasks restores exactly what was there, and "Stop & Discard" on the focus
// timer really discards.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class StudyLockdownGuidanceTests: XCTestCase {
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

    private func loadStudy(target: Double = 3) -> NonNegotiableProgress {
        context.insert(NonNegotiable(name: "Study", type: .study, targetValue: target, order: 0))
        context.insert(NonNegotiable(name: "Train", type: .train, targetValue: 1, order: 1))
        try? context.save()
        viewModel.loadToday(modelContext: context)
        return viewModel.progressItems.first { $0.nonNegotiable?.type == .study }!
    }

    // MARK: Progress tap

    func testUndoOfAProgressTapPutsTheValueBack() {
        let study = loadStudy()
        let undo = viewModel.updateItemProgress(study, value: 1, modelContext: context)
        XCTAssertEqual(study.currentValue, 1)
        XCTAssertFalse(study.isCompleted)

        viewModel.undo(undo, modelContext: context)
        XCTAssertEqual(study.currentValue, 0)
        XCTAssertFalse(study.isCompleted)
    }

    func testUndoOfTheTapThatFinishesATaskReopensItAndRewindsTheStreak() {
        let study = loadStudy(target: 2)
        viewModel.updateItemProgress(study, value: 1, modelContext: context)
        XCTAssertEqual(viewModel.habitStreakCount(for: .study), 0)

        let undo = viewModel.updateItemProgress(study, value: 2, modelContext: context)
        XCTAssertTrue(study.isCompleted)
        XCTAssertEqual(viewModel.habitStreakCount(for: .study), 1)

        viewModel.undo(undo, modelContext: context)
        XCTAssertFalse(study.isCompleted)
        XCTAssertNil(study.completedAt)
        // Back to the first tap, not to zero.
        XCTAssertEqual(study.currentValue, 1)
        XCTAssertEqual(viewModel.habitStreakCount(for: .study), 0)
    }

    // MARK: Added tasks

    func testUndoOfAddedTasksRemovesOnlyThoseAndKeepsTheRest() throws {
        let keep = NonNegotiable(name: "Read", type: .custom, targetValue: 1, order: 0)
        let first = NonNegotiable(name: "Study", type: .study, targetValue: 120, order: 1)
        let second = NonNegotiable(name: "Sleep", type: .sleep, targetValue: 7, order: 2)
        [keep, first, second].forEach { context.insert($0) }
        try context.save()

        let removed = NonNegotiableAddUndo.remove(ids: [first.id, second.id], from: context)
        XCTAssertEqual(removed, 2)

        let left = try context.fetch(FetchDescriptor<NonNegotiable>())
        XCTAssertEqual(left.map(\.name), ["Read"])
    }

    func testUndoOfAddedTasksIgnoresIdsThatAreAlreadyGone() throws {
        let item = NonNegotiable(name: "Study", type: .study, targetValue: 120, order: 0)
        context.insert(item)
        try context.save()

        XCTAssertEqual(NonNegotiableAddUndo.remove(ids: [UUID()], from: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NonNegotiable>()).count, 1)
    }

    // MARK: Stop and discard

    private func startSession() -> StudySession {
        _ = loadStudy()
        viewModel.startFocusSession(modelContext: context)
        return viewModel.currentStudySession!
    }

    func testStopAndDiscardDeletesASessionThatRanLongerThanFiveMinutes() throws {
        _ = startSession()
        viewModel.cancelFocus(
            modelContext: context, keepingPartial: false, now: Date().addingTimeInterval(12 * 60)
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudySession>()).isEmpty)
    }

    func testTheWatchStopStillKeepsASessionThatRanLongerThanFiveMinutes() throws {
        _ = startSession()
        viewModel.cancelFocus(modelContext: context, now: Date().addingTimeInterval(12 * 60))
        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions.first?.endTime)
        XCTAssertEqual(sessions.first?.durationMinutes, 12)
    }

    func testDiscardingTheRunningPomodoroKeepsOneThatAlreadyFinished() throws {
        let session = startSession()
        // A pomodoro that finished was saved and counted when it ended.
        session.completedPomodoros = 1
        session.durationMinutes = 25
        session.endTime = Date()
        try context.save()

        viewModel.cancelFocus(
            modelContext: context, keepingPartial: false, now: Date().addingTimeInterval(8 * 60)
        )
        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.durationMinutes, 25)
    }
}
