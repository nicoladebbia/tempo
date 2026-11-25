//
// TrainingViewModel+SetEditUndo.swift
// Tempo
//
// Undo for the "−" button in the logger, which takes the last open set out of
// the exercise. The set is copied before it goes and put back in its place, so
// a slip of the thumb costs nothing. Skipped sets have their own Undo
// (`TrainingViewModel+Undo.swift`); this one is for the manual removal.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// A set taken out by the "−" button, kept so Undo can put it back.
    struct RemovedSetUndo {
        let exerciseIndex: Int
        let snapshot: SetSnapshot
        /// The set the cursor was on when the removal happened (nil when the
        /// removal was on another exercise), to land on again.
        let cursorSetID: UUID?
        /// The removed set was the one on screen, so the session moved on.
        let cursorWasRemoved: Bool
        /// If something has been logged since, the old cursor means nothing.
        let lastLoggedSetID: UUID?

        var message: String {
            snapshot.isWarmup ? String(localized: "Removed a warm-up set") : String(localized: "Removed a set")
        }
    }

    /// `removeLastUncompletedSet`, plus what Undo needs. Nil when nothing was
    /// removed, or the removal left the session somewhere Undo cannot return to.
    @discardableResult
    func removeLastUncompletedSetCapturingUndo(from exerciseIndex: Int, modelContext: ModelContext) -> RemovedSetUndo? {
        guard let plan = todayPlan, exerciseIndex < plan.orderedExercises.count else {
            return nil
        }
        let slot = plan.orderedExercises[exerciseIndex]
        let sets = slot.orderedSets
        guard sets.count > 1, let doomed = sets.last(where: { !$0.completed }) else {
            removeLastUncompletedSet(from: exerciseIndex, modelContext: modelContext)
            return nil
        }
        let onCursorExercise = exerciseIndex == currentExerciseIndex
        let cursorSetID = onCursorExercise && currentSetIndex < sets.count ? sets[currentSetIndex].id : nil
        var wasSetActive = false
        if case .exercise(.setActive) = sessionState {
            wasSetActive = true
        }
        let snapshot = SetSnapshot(doomed)
        let lastLoggedSetID = lastCompletedSet?.id

        removeLastUncompletedSet(from: exerciseIndex, modelContext: modelContext)

        guard !(slot.sets ?? []).contains(where: { $0.id == snapshot.id }) else {
            return nil
        }
        switch sessionState {
        case .exercise(.setActive),
             .exercise(.resting),
             .exercise(.betweenExercises):
            break
        default:
            return nil
        }
        return RemovedSetUndo(
            exerciseIndex: exerciseIndex,
            snapshot: snapshot,
            cursorSetID: cursorSetID,
            cursorWasRemoved: wasSetActive && cursorSetID == snapshot.id,
            lastLoggedSetID: lastLoggedSetID
        )
    }

    /// Puts the removed set back in its old place. False (and nothing changed)
    /// when the session has moved on so it cannot go back.
    @discardableResult
    func undoRemovedSet(_ undo: RemovedSetUndo, modelContext: ModelContext) -> Bool {
        guard canUndoRemovedSet(undo), let plan = todayPlan else {
            return false
        }
        let slot = plan.orderedExercises[undo.exerciseIndex]
        reinsertSets([undo.snapshot], in: slot)
        let ordered = slot.orderedSets

        if undo.cursorWasRemoved, let position = ordered.firstIndex(where: { $0.id == undo.snapshot.id }) {
            currentExerciseIndex = undo.exerciseIndex
            currentSetIndex = position
            sessionState = .exercise(.setActive(exerciseIndex: undo.exerciseIndex, setIndex: position))
        } else if currentExerciseIndex == undo.exerciseIndex,
                  let cursorID = undo.cursorSetID,
                  let position = ordered.firstIndex(where: { $0.id == cursorID })
        {
            currentSetIndex = position
            if case .exercise(.setActive) = sessionState {
                sessionState = .exercise(.setActive(exerciseIndex: undo.exerciseIndex, setIndex: position))
            }
        }
        saveGuarded(modelContext, operation: String(localized: "undo remove set"))
        HapticManager.selection()
        return true
    }

    func canUndoRemovedSet(_ undo: RemovedSetUndo) -> Bool {
        guard let plan = todayPlan,
              undo.exerciseIndex < plan.orderedExercises.count,
              lastCompletedSet?.id == undo.lastLoggedSetID,
              !(plan.orderedExercises[undo.exerciseIndex].sets ?? []).contains(where: { $0.id == undo.snapshot.id })
        else {
            return false
        }
        switch sessionState {
        case .exercise(.setActive),
             .exercise(.resting),
             .exercise(.betweenExercises):
            return true
        default:
            return false
        }
    }

    /// Rebuilds sets that were taken out, in their old places. A set added in
    /// the meantime may have taken a number, so later ones move up by one to
    /// keep the order stable. A set that is already back is left alone.
    func reinsertSets(_ snapshots: [SetSnapshot], in slot: PlannedExercise) {
        let present = Set((slot.sets ?? []).map(\.id))
        for snapshot in snapshots.sorted(by: { $0.setNumber < $1.setNumber }) where !present.contains(snapshot.id) {
            let taken = (slot.sets ?? []).contains { $0.setNumber == snapshot.setNumber }
            if taken {
                for later in slot.sets ?? [] where later.setNumber >= snapshot.setNumber {
                    later.setNumber += 1
                }
            }
            let set = snapshot.rebuild(in: slot)
            if slot.sets != nil {
                slot.sets?.append(set)
            } else {
                slot.sets = [set]
            }
        }
    }
}
