//
// TrainUndoTests.swift
// Tempo
//
// The Undo that follows a delete in Train: a routine is copied before it goes
// and put back as it was, an exercise taken out of a routine goes back where it
// was, and a workout waiting to be purged follows a single-slot window.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainUndoTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([WorkoutRoutine.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func item(_ name: String, sets: Int = 3, group: Int? = nil) -> RoutineItem {
        RoutineItem(exerciseID: UUID(), exerciseName: name, workingSets: sets, group: group)
    }

    // MARK: Routine

    func testDeletedRoutineComesBackWithItsIdDateAndExercises() throws {
        let context = try makeContext()
        let items = [item("Bench Press", group: 1), item("Barbell Row", sets: 4, group: 1), item("Curl")]
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let routine = WorkoutRoutine(name: "Upper A", items: items, createdAt: created)
        let used = Date(timeIntervalSince1970: 1_700_500_000)
        routine.lastUsedAt = used
        context.insert(routine)
        try context.save()

        let snapshot = RoutineSnapshot(routine)
        context.delete(routine)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutRoutine>()).isEmpty)

        snapshot.restore(in: context)
        try context.save()
        let back = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutRoutine>()).first)
        XCTAssertEqual(back.id, snapshot.id)
        XCTAssertEqual(back.name, "Upper A")
        XCTAssertEqual(back.createdAt, created)
        XCTAssertEqual(back.lastUsedAt, used)
        XCTAssertEqual(back.items, items)
    }

    func testRestoringARoutineTwiceDoesNotDuplicateIt() throws {
        let context = try makeContext()
        let routine = WorkoutRoutine(name: "Legs", items: [item("Squat")])
        context.insert(routine)
        try context.save()
        let snapshot = RoutineSnapshot(routine)
        context.delete(routine)
        try context.save()

        snapshot.restore(in: context)
        try context.save()
        snapshot.restore(in: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutRoutine>()).count, 1)
    }

    func testARestoredRoutineKeepsItsPlaceInTheList() throws {
        let context = try makeContext()
        let newest = WorkoutRoutine(name: "C", items: [item("Squat")], createdAt: Date(timeIntervalSince1970: 300))
        let middle = WorkoutRoutine(name: "B", items: [item("Squat")], createdAt: Date(timeIntervalSince1970: 200))
        let oldest = WorkoutRoutine(name: "A", items: [item("Squat")], createdAt: Date(timeIntervalSince1970: 100))
        [newest, middle, oldest].forEach(context.insert)
        try context.save()

        let snapshot = RoutineSnapshot(middle)
        context.delete(middle)
        try context.save()
        snapshot.restore(in: context)
        try context.save()

        let sorted = try context.fetch(FetchDescriptor<WorkoutRoutine>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        XCTAssertEqual(sorted.map(\.name), ["C", "B", "A"])
    }

    // MARK: Routine item

    func testAnExerciseGoesBackWhereItWas() {
        var items = [item("Bench"), item("Row"), item("Curl"), item("Dip")]
        let original = items
        let removal = RoutineItemRemoval(offsets: IndexSet(integer: 1), in: items)
        items.remove(atOffsets: IndexSet(integer: 1))
        XCTAssertEqual(items.map(\.exerciseName), ["Bench", "Curl", "Dip"])

        removal.restore(into: &items)
        XCTAssertEqual(items, original)
    }

    func testSeveralExercisesGoBackInTheirOldOrder() {
        var items = [item("A"), item("B"), item("C"), item("D"), item("E")]
        let original = items
        let offsets = IndexSet([1, 3])
        let removal = RoutineItemRemoval(offsets: offsets, in: items)
        items.remove(atOffsets: offsets)
        removal.restore(into: &items)
        XCTAssertEqual(items, original)
        XCTAssertEqual(removal.message, "Removed 2 exercises")
    }

    func testARemovedExerciseKeepsItsSupersetGroup() {
        var items = [item("A", group: 1), item("B", group: 1), item("C")]
        let removal = RoutineItemRemoval(offsets: IndexSet(integer: 0), in: items)
        items.remove(atOffsets: IndexSet(integer: 0))
        removal.restore(into: &items)
        XCTAssertEqual(items.first?.group, 1)
        XCTAssertEqual(items.first?.exerciseName, "A")
    }

    func testRestoreWhenTheListGotShorterPutsItAtTheEnd() {
        var items = [item("A"), item("B"), item("C")]
        let removal = RoutineItemRemoval(offsets: IndexSet(integer: 2), in: items)
        items.remove(atOffsets: IndexSet([1, 2]))
        removal.restore(into: &items)
        XCTAssertEqual(items.map(\.exerciseName), ["A", "C"])
    }

    func testRestoringAnExerciseTwiceAddsItOnce() {
        var items = [item("A"), item("B")]
        let removal = RoutineItemRemoval(offsets: IndexSet(integer: 0), in: items)
        items.remove(atOffsets: IndexSet(integer: 0))
        removal.restore(into: &items)
        removal.restore(into: &items)
        XCTAssertEqual(items.map(\.exerciseName), ["A", "B"])
    }

    func testRemovalMessageNamesASingleExercise() {
        let items = [item("Barbell Row"), item("Curl")]
        XCTAssertEqual(RoutineItemRemoval(offsets: IndexSet(integer: 0), in: items).message, "Removed Barbell Row")
    }

    func testRemovalIgnoresOffsetsOutsideTheList() {
        let items = [item("A")]
        XCTAssertTrue(RoutineItemRemoval(offsets: IndexSet(integer: 5), in: items).isEmpty)
    }

    // MARK: PendingUndo

    func testUndoGivesBackTheWaitingItemOnce() {
        let pending = PendingUndo<Int>()
        pending.begin(7) { _ in XCTFail("nothing was waiting") }
        XCTAssertTrue(pending.isPending)
        XCTAssertEqual(pending.undo(), 7)
        XCTAssertFalse(pending.isPending)
        XCTAssertNil(pending.undo())
    }

    func testANewDeletionCommitsTheEarlierOneRightAway() {
        let pending = PendingUndo<Int>()
        var committed: [Int] = []
        pending.begin(1) { committed.append($0) }
        pending.begin(2) { committed.append($0) }
        XCTAssertEqual(committed, [1])
        XCTAssertEqual(pending.item, 2)
    }

    func testTheTimerCommitsTheItemOnce() {
        let pending = PendingUndo<Int>()
        let token = pending.begin(1) { _ in }
        var committed: [Int] = []
        pending.commitIfCurrent(token) { committed.append($0) }
        pending.commitIfCurrent(token) { committed.append($0) }
        XCTAssertEqual(committed, [1])
        XCTAssertFalse(pending.isPending)
    }

    func testAnOldTimerCannotFinishANewerDeletion() {
        let pending = PendingUndo<Int>()
        let first = pending.begin(1) { _ in }
        pending.begin(2) { _ in }
        var committed: [Int] = []
        pending.commitIfCurrent(first) { committed.append($0) }
        XCTAssertTrue(committed.isEmpty)
        XCTAssertEqual(pending.item, 2)
    }

    func testUndoAfterTheCommitDoesNothing() {
        let pending = PendingUndo<Int>()
        let token = pending.begin(1) { _ in }
        pending.commitIfCurrent(token) { _ in }
        XCTAssertNil(pending.undo())
    }

    func testATimerForAnUndoneDeletionDoesNothing() {
        let pending = PendingUndo<Int>()
        let token = pending.begin(1) { _ in }
        _ = pending.undo()
        var committed: [Int] = []
        pending.commitIfCurrent(token) { committed.append($0) }
        XCTAssertTrue(committed.isEmpty)
    }

    func testLeavingTheScreenCommitsWhatIsWaiting() {
        let pending = PendingUndo<Int>()
        pending.begin(3) { _ in }
        var committed: [Int] = []
        pending.commitNow { committed.append($0) }
        pending.commitNow { committed.append($0) }
        XCTAssertEqual(committed, [3])
    }

    func testTheWindowOutlastsTheToast() {
        // ToastData.duration is 5 s for a toast with an action.
        XCTAssertGreaterThan(PendingUndo<Int>.window, .seconds(5))
    }
}
