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
import SwiftUI

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

// MARK: - MatchSnapshot

/// A scheduled match as it was the moment it was deleted. A match is plain
/// values, so it is copied before the delete and put back as it was.
struct MatchSnapshot: Equatable {
    let id: UUID
    let kickoff: Date
    let opponent: String?
    let isCompetitive: Bool
    let createdAt: Date

    init(_ match: Match) {
        id = match.id
        kickoff = match.kickoff
        opponent = match.opponent
        isCompetitive = match.isCompetitive
        createdAt = match.createdAt
    }

    /// "Deleted the match vs Inter" or "Deleted the match".
    var message: String {
        opponent.map { String(localized: "Deleted the match vs \($0)") } ?? String(localized: "Deleted the match")
    }

    /// Puts the match back with its old id, so it lands in the same place in
    /// the list. Does nothing if it is already back (a double tap on Undo).
    /// The caller saves.
    @MainActor
    @discardableResult
    func restore(in context: ModelContext) -> Match {
        let wanted = id
        let existing = try? context.fetch(
            FetchDescriptor<Match>(predicate: #Predicate { $0.id == wanted })
        ).first
        if let existing {
            return existing
        }
        let match = Match(kickoff: kickoff, opponent: opponent, isCompetitive: isCompetitive, createdAt: createdAt)
        match.id = id
        context.insert(match)
        return match
    }
}

// MARK: - TrainerProgramSnapshot

/// A trainer program as it was the moment it was deleted. A program is plain
/// stored fields (no relationships), so every one is copied before the delete
/// and put back with the same id.
struct TrainerProgramSnapshot {
    let id: UUID
    let name: String
    let createdAt: Date
    let startDate: Date
    let weeks: [ProgramWeek]
    let repeats: Bool
    let isActive: Bool
    let sourceKind: String
    let sourceText: String?
    let autoWarmups: Bool?
    let scheduleModeRaw: String?
    let queuedActivationDate: Date?
    let endedAt: Date?
    let cadenceRaw: String?
    let changeLog: [TrainerProgramChangeLogEntry]
    let skippedSessions: [TrainerProgramSkip]

    init(_ program: TrainerProgram) {
        id = program.id
        name = program.name
        createdAt = program.createdAt
        startDate = program.startDate
        weeks = program.weeks
        repeats = program.repeats
        isActive = program.isActive
        sourceKind = program.sourceKind
        sourceText = program.sourceText
        autoWarmups = program.autoWarmups
        scheduleModeRaw = program.scheduleModeRaw
        queuedActivationDate = program.queuedActivationDate
        endedAt = program.endedAt
        cadenceRaw = program.cadenceRaw
        changeLog = program.changeLog
        skippedSessions = program.skippedSessions
    }

    /// Puts the program back as it was. Does nothing if it is already back (a
    /// double tap on Undo). At most one program is active: if another one took
    /// over in the meantime, this one comes back as a saved, inactive program
    /// instead of fighting it. The caller saves and tells the plan to rebuild.
    @MainActor
    @discardableResult
    func restore(in context: ModelContext) -> TrainerProgram {
        let wanted = id
        if let existing = try? context.fetch(
            FetchDescriptor<TrainerProgram>(predicate: #Predicate { $0.id == wanted })
        ).first {
            return existing
        }
        let anotherIsActive = ((try? context.fetch(FetchDescriptor<TrainerProgram>())) ?? []).contains { $0.isActive }
        let program = TrainerProgram(
            id: id,
            name: name,
            startDate: startDate,
            weeks: weeks,
            repeats: repeats,
            isActive: isActive && !anotherIsActive,
            sourceKind: sourceKind,
            sourceText: sourceText,
            autoWarmups: autoWarmups,
            queuedActivationDate: queuedActivationDate,
            changeLog: changeLog,
            createdAt: createdAt
        )
        program.startDate = startDate
        program.scheduleModeRaw = scheduleModeRaw
        program.cadenceRaw = cadenceRaw
        program.endedAt = endedAt
        program.skippedSessions = skippedSessions
        context.insert(program)
        return program
    }
}

// MARK: - ExerciseSnapshot

/// A custom exercise as it was the moment it was deleted, with the rows that
/// pointed at it. Deleting an exercise only detaches those rows (they keep
/// their logged sets and their own copy of the name), so Undo creates the
/// exercise again with its old id and points them back at it.
struct ExerciseSnapshot {
    let id: UUID
    let name: String
    let muscleGroupRaw: String
    let secondaryMusclesJSON: Data?
    let equipmentRaw: String
    let movementPatternRaw: String
    let isCompound: Bool
    let isCustom: Bool
    let demoAsset: String?
    let instructions: String?
    let cuesJSON: Data?
    let preferredRestSeconds: Int?
    let importBatchID: UUID?
    let plannedExerciseIDs: [UUID]
    let historyIDs: [UUID]
    let recordIDs: [UUID]

    init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        muscleGroupRaw = exercise.muscleGroupRaw
        secondaryMusclesJSON = exercise.secondaryMusclesJSON
        equipmentRaw = exercise.equipmentRaw
        movementPatternRaw = exercise.movementPatternRaw
        isCompound = exercise.isCompound
        isCustom = exercise.isCustom
        demoAsset = exercise.demoAsset
        instructions = exercise.instructions
        cuesJSON = exercise.cuesJSON
        preferredRestSeconds = exercise.preferredRestSeconds
        importBatchID = exercise.importBatchID
        plannedExerciseIDs = (exercise.plannedExercises ?? []).map(\.id)
        historyIDs = (exercise.history ?? []).map(\.id)
        recordIDs = (exercise.personalRecords ?? []).map(\.id)
    }

    /// Creates the exercise again with its old id and fields, and points its
    /// old sessions, history rows and records back at it. Does nothing if it
    /// is already back (a double tap on Undo). The caller saves.
    @MainActor
    @discardableResult
    func restore(in context: ModelContext) -> Exercise {
        let wanted = id
        if let existing = try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == wanted })
        ).first {
            return existing
        }
        let exercise = Exercise(
            id: id,
            name: name,
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: isCompound,
            isCustom: isCustom,
            demoAsset: demoAsset,
            instructions: instructions
        )
        exercise.muscleGroupRaw = muscleGroupRaw
        exercise.secondaryMusclesJSON = secondaryMusclesJSON
        exercise.equipmentRaw = equipmentRaw
        exercise.movementPatternRaw = movementPatternRaw
        exercise.cuesJSON = cuesJSON
        exercise.preferredRestSeconds = preferredRestSeconds
        exercise.importBatchID = importBatchID
        context.insert(exercise)

        let plannedIDs = plannedExerciseIDs
        for row in (try? context.fetch(
            FetchDescriptor<PlannedExercise>(predicate: #Predicate { plannedIDs.contains($0.id) })
        )) ?? [] {
            row.exercise = exercise
        }
        let historyIDs = historyIDs
        for row in (try? context.fetch(
            FetchDescriptor<ExerciseHistory>(predicate: #Predicate { historyIDs.contains($0.id) })
        )) ?? [] {
            row.exercise = exercise
        }
        let recordIDs = recordIDs
        for row in (try? context.fetch(
            FetchDescriptor<PersonalRecord>(predicate: #Predicate { recordIDs.contains($0.id) })
        )) ?? [] {
            row.exercise = exercise
        }
        return exercise
    }
}

extension EnvironmentValues {
    /// Set by the Train tab: shows the Undo toast for a custom exercise that was
    /// just deleted. Nil where there is nowhere to show it, and the delete then
    /// goes through without Undo.
    @Entry var offerExerciseUndo: (@MainActor (ExerciseSnapshot) -> Void)?
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
            return String(localized: "Removed \(only.item.exerciseName)")
        }
        return String(localized: "Removed \(removed.count) exercises")
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
