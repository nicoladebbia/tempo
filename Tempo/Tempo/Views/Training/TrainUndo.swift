//
// TrainUndo.swift
// Tempo
//
// What it takes to put back something just deleted in Train, for the few
// seconds the shared Undo toast (`ToastData` with an "Undo" action) is up:
// a routine, an exercise taken out of a routine, and a workout waiting to be
// purged. Kept apart from the views so the rules are unit-tested.
//
// A routine and a routine item are plain values, so they are copied before the
// delete and put back as they were. A workout is a web of sets, feedback and
// records, so it is not copied: it is hidden, purged only once its Undo window
// has passed (`PendingUndo`), and simply un-hidden by Undo.
//

import Foundation
import SwiftData

// MARK: - RoutineSnapshot

/// A routine as it was the moment it was deleted. Copied before the delete:
/// reading a deleted model afterwards is not safe.
struct RoutineSnapshot: Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let lastUsedAt: Date?
    let items: [RoutineItem]

    init(_ routine: WorkoutRoutine) {
        id = routine.id
        name = routine.name
        createdAt = routine.createdAt
        lastUsedAt = routine.lastUsedAt
        items = routine.items
    }

    /// Puts the routine back with its old id, date and exercises, so it lands
    /// in the same place in the list. Does nothing if it is already back (a
    /// double tap on Undo). The caller saves.
    @MainActor
    @discardableResult
    func restore(in context: ModelContext) -> WorkoutRoutine {
        let wanted = id
        let existing = try? context.fetch(
            FetchDescriptor<WorkoutRoutine>(predicate: #Predicate { $0.id == wanted })
        ).first
        if let existing {
            return existing
        }
        let routine = WorkoutRoutine(id: id, name: name, items: items, createdAt: createdAt)
        routine.lastUsedAt = lastUsedAt
        context.insert(routine)
        return routine
    }
}

// MARK: - RoutineItemRemoval

/// Exercises taken out of a routine while it is being edited, remembered with
/// the place each one had so Undo puts them back where they were.
struct RoutineItemRemoval: Equatable {
    struct Removed: Equatable {
        let index: Int
        let item: RoutineItem
    }

    let removed: [Removed]

    /// Reads what is about to go (`offsets` as the list reports them).
    init(offsets: IndexSet, in items: [RoutineItem]) {
        removed = offsets
            .filter { items.indices.contains($0) }
            .sorted()
            .map { Removed(index: $0, item: items[$0]) }
    }

    var isEmpty: Bool {
        removed.isEmpty
    }

    /// "Removed Barbell Row" or "Removed 2 exercises".
    var message: String {
        if removed.count == 1, let only = removed.first {
            return "Removed \(only.item.exerciseName)"
        }
        return "Removed \(TrainCount.text(removed.count, "exercise"))"
    }

    /// Puts each item back at its old place (or at the end if the list has
    /// since got shorter). An exercise that is already in the list is left
    /// alone, so a second Undo changes nothing.
    func restore(into items: inout [RoutineItem]) {
        for entry in removed where !items.contains(where: { $0.id == entry.item.id }) {
            items.insert(entry.item, at: min(entry.index, items.count))
        }
    }
}

// MARK: - PendingUndo

/// One deletion waiting out its Undo window. Only one can wait at a time: a
/// new deletion makes the earlier one final straight away, so two never
/// overlap. The window outlasts the toast, so Undo can never be tapped after
/// the deletion has gone through; Undo after that does nothing.
@MainActor
final class PendingUndo<Item: Equatable> {
    private(set) var item: Item?
    private var token = UUID()

    /// How long a deletion waits. A little longer than the toast's 5 seconds.
    nonisolated static var window: Duration {
        .seconds(6)
    }

    var isPending: Bool {
        item != nil
    }

    /// Starts waiting on `new`. Whatever was waiting before is committed first.
    /// Returns a token for this wait: hand it back to `commitIfCurrent` when the
    /// timer ends, so an old timer cannot finish a newer deletion.
    @discardableResult
    func begin(_ new: Item, commitPrevious: (Item) -> Void) -> UUID {
        if let previous = item {
            commitPrevious(previous)
        }
        item = new
        token = UUID()
        return token
    }

    /// The Undo button: gives back the waiting item and forgets it.
    func undo() -> Item? {
        defer { item = nil }
        return item
    }

    /// The timer ended. Commits only if this is still the same wait.
    func commitIfCurrent(_ expected: UUID, commit: (Item) -> Void) {
        guard token == expected, let waiting = item else {
            return
        }
        item = nil
        commit(waiting)
    }

    /// The screen is going away or the app is leaving the foreground: make
    /// whatever is waiting final now.
    func commitNow(commit: (Item) -> Void) {
        guard let waiting = item else {
            return
        }
        item = nil
        commit(waiting)
    }
}
