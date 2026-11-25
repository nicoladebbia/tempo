//
// GoalUndoTests.swift
// TempoTests
//
// Removing the goal and taking it back leaves exactly what was there.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GoalUndoTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        var count = 0
    }

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TempoModelContainer.create(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    private func makeGoal() -> Goal {
        let goal = Goal(
            kind: .liftE1RM, targetValue: 100, targetDate: Date(timeIntervalSince1970: 1_900_000_000),
            startValue: 80, startDate: Date(timeIntervalSince1970: 1_800_000_000), exerciseName: "Barbell Bench Press"
        )
        context.insert(goal)
        try? context.save()
        return goal
    }

    func testRemoveHidesTheGoalFromEveryReader() {
        let goal = makeGoal()
        XCTAssertNotNil(GoalReader.activeGoal(in: context))
        _ = GoalUndo.remove(goal, in: context)
        XCTAssertNil(GoalReader.activeGoal(in: context))
    }

    func testUndoBringsBackTheSameGoalWithItsStartPoint() throws {
        let goal = makeGoal()
        let state = GoalUndo.remove(goal, in: context)
        XCTAssertTrue(GoalUndo.restore(state, in: context))
        let back = try XCTUnwrap(GoalReader.activeGoal(in: context))
        XCTAssertEqual(back.id, goal.id)
        XCTAssertEqual(back.startValue, 80)
        XCTAssertEqual(back.targetValue, 100)
        XCTAssertEqual(back.exerciseName, "Barbell Bench Press")
        XCTAssertEqual(back.startDate, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testRemoveAndUndoTellTheScreensTheGoalChanged() {
        let goal = makeGoal()
        let posts = Counter()
        let token = NotificationCenter.default.addObserver(forName: .tempoGoalChanged, object: nil, queue: nil) { _ in
            posts.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let state = GoalUndo.remove(goal, in: context)
        GoalUndo.restore(state, in: context)
        XCTAssertEqual(posts.count, 2, "Today and the chips reload on both")
    }

    func testUndoNeverLeavesTwoActiveGoals() throws {
        let first = makeGoal()
        let state = GoalUndo.remove(first, in: context)
        let second = Goal(kind: .bodyWeight, targetValue: 70, targetDate: Date(timeIntervalSince1970: 1_900_000_000))
        context.insert(second)
        try context.save()
        XCTAssertFalse(GoalUndo.restore(state, in: context))
        XCTAssertEqual(GoalReader.activeGoal(in: context)?.id, second.id)
        let active = try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.isActive == true }))
        XCTAssertEqual(active.count, 1)
    }

    func testUndoOfAGoneGoalDoesNothing() {
        let goal = makeGoal()
        let state = GoalUndo.remove(goal, in: context)
        context.delete(goal)
        try? context.save()
        XCTAssertFalse(GoalUndo.restore(state, in: context))
    }
}
