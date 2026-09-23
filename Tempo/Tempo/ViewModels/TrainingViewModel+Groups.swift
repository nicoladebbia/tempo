//
// TrainingViewModel+Groups.swift
// Tempo
//
// Superset/circuit membership and rotation (§6.1-6.3), drop-set logging
// (§6.4/§7.7) and manual group control (§6.5). Split out of
// TrainingViewModel.swift to keep it under the SwiftLint length caps.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Circuit Membership & Rotation (§6.1-6.3)

    /// All exercise indices in the CONTIGUOUS run sharing `index`'s
    /// (non-nil) supersetGroup — generalizes the old adjacent-PAIR lookup to
    /// circuits of 2..N members. A lone exercise (no group, or a group of
    /// one after a manual "Break Group") returns just itself, so `.count > 1`
    /// is the caller's "is this actually grouped" check. Order matches the
    /// physical exercise order (A, B, C, … rotation order).
    func circuitMembers(of index: Int) -> [Int] {
        guard let exercises = todayPlan?.orderedExercises,
              index >= 0, index < exercises.count,
              let group = exercises[index].supersetGroup
        else {
            return [index]
        }
        var lower = index
        while lower - 1 >= 0, exercises[lower - 1].supersetGroup == group {
            lower -= 1
        }
        var upper = index
        while upper + 1 < exercises.count, exercises[upper + 1].supersetGroup == group {
            upper += 1
        }
        return Array(lower ... upper)
    }

    /// Whether `index` is the LAST member (in rotation order) of its circuit —
    /// the position whose transition to the next round carries the group's
    /// one shared rest, exactly like the second lift of a pair.
    func isLastOfCircuitRotation(_ index: Int) -> Bool {
        let members = circuitMembers(of: index)
        guard let pos = members.firstIndex(of: index) else {
            return true
        }
        return pos == members.count - 1
    }

    /// The next OTHER circuit member (rotation order, wrapping once) that
    /// still has an uncompleted set — never `index` itself. This is the
    /// single generalized lookup both `logSet` and `advanceAfterSkip` use;
    /// for a 2-member group it reduces to exactly the old pair-partner
    /// lookup (there is only one "other" member to find).
    func nextCircuitMemberWithWork(after index: Int) -> (exerciseIndex: Int, setIndex: Int)? {
        guard let exercises = todayPlan?.orderedExercises else {
            return nil
        }
        let members = circuitMembers(of: index)
        guard members.count > 1, let pos = members.firstIndex(of: index) else {
            return nil
        }
        for offset in 1 ..< members.count {
            let candidate = members[(pos + offset) % members.count]
            if let setIdx = firstUncompletedSetIndex(in: exercises[candidate]) {
                return (candidate, setIdx)
            }
        }
        return nil
    }

    /// Chip text for the active screen's group banner — "Superset: X" for a
    /// pair, "Circuit: X, Y" for 3+. nil when the current exercise isn't
    /// grouped.
    var currentSupersetPartnerName: String? {
        guard let exercises = todayPlan?.orderedExercises else {
            return nil
        }
        let members = circuitMembers(of: currentExerciseIndex)
        guard members.count > 1 else {
            return nil
        }
        let others = members
            .filter { $0 != currentExerciseIndex }
            .compactMap { exercises[$0].exercise?.name }
        guard !others.isEmpty else {
            return nil
        }
        return others.joined(separator: ", ")
    }

    /// Whether the active screen's group banner should read "Circuit" (3+
    /// members) instead of "Superset" (exactly 2).
    var currentGroupIsCircuit: Bool {
        circuitMembers(of: currentExerciseIndex).count > 2
    }

    // MARK: - Drop Sets (§6.4 / §7.7)

    /// Whether the CURRENT set already has a pending (uncompleted) drop step
    /// queued immediately after it — drives the active-workout "+ Drop /
    /// Remove Drop" toggle.
    var currentSetHasPendingDrop: Bool {
        guard let plan = todayPlan else {
            return false
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return false
        }
        let sets = exercises[currentExerciseIndex].orderedSets
        guard currentSetIndex + 1 < sets.count else {
            return false
        }
        let next = sets[currentSetIndex + 1]
        return next.isDropStep && !next.completed
    }

    /// Turn the CURRENT set into a drop set / chain another drop step onto
    /// it: insert a new set immediately after the current one, at ~20% less
    /// than the current set's weight (snapped to a loadable value for the
    /// user's unit/equipment), logged with no rest between drops. Works
    /// whether the current set is a normal working set (starts a new
    /// sequence) or itself already a drop step (chains a further one) —
    /// either way the new row reduces off THIS set's weight.
    func addDropSet(modelContext: ModelContext) {
        guard let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return
        }
        let plannedExercise = exercises[currentExerciseIndex]
        let sets = plannedExercise.orderedSets
        guard currentSetIndex < sets.count else {
            return
        }
        let current = sets[currentSetIndex]
        guard !current.isWarmup else {
            return // drop sets only make sense on a working set
        }

        let equipment = plannedExercise.exercise?.equipment ?? .none
        let baseKg = current.actualWeight ?? current.targetWeight ?? 0
        let reducedKg = baseKg > 0
            ? WeightConverter.loadableKg(baseKg * 0.8, equipment: equipment, unit: weightUnit)
            : baseKg

        let newIndex = (current.dropStepIndex ?? 0) + 1
        // Make room right after `current`: every following set number shifts
        // up by one so the new row sorts directly next to it.
        let insertionSetNumber = current.setNumber + 1
        for set in sets where set.setNumber >= insertionSetNumber {
            set.setNumber += 1
        }

        let dropSet = PlannedSet(
            setNumber: insertionSetNumber,
            // Reps target is a placeholder only — a drop step is logged to
            // failure, whatever the user actually hits.
            targetReps: current.actualReps ?? current.targetReps,
            targetWeight: reducedKg > 0 ? reducedKg : nil,
            dropStepIndex: newIndex,
            plannedExercise: plannedExercise
        )

        if plannedExercise.sets != nil {
            plannedExercise.sets?.append(dropSet)
        } else {
            plannedExercise.sets = [dropSet]
        }

        try? modelContext.save()
        HapticManager.selection()
    }

    /// Undo an accidentally queued drop step: remove the set immediately
    /// after the current one, IF it's an uncompleted drop step.
    func removeTrailingDropSet(modelContext: ModelContext) {
        guard let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return
        }
        let plannedExercise = exercises[currentExerciseIndex]
        let sets = plannedExercise.orderedSets
        guard currentSetIndex + 1 < sets.count else {
            return
        }
        let trailing = sets[currentSetIndex + 1]
        guard trailing.isDropStep, !trailing.completed else {
            return
        }
        plannedExercise.sets?.removeAll { $0.id == trailing.id }
        modelContext.delete(trailing)
        try? modelContext.save()
        HapticManager.selection()
    }

    // MARK: - Manual Superset/Circuit Control (§6.5)

    /// Extend (or start) a superset/circuit by joining `exercise` to the very
    /// next exercise in today's plan order. Auto-assignment
    /// (`assignSupersetGroups`) still runs by default when a workout is
    /// generated — this is the manual override: grow a pair into a circuit
    /// by repeating it on a third exercise, or start a fresh pairing between
    /// two exercises the auto-assignment left independent.
    func groupWithNext(_ exercise: PlannedExercise, modelContext: ModelContext) {
        guard let plan = exercise.workoutPlan ?? todayPlan,
              plan.status == .planned || plan.status == .inProgress
        else {
            return
        }
        let exercises = plan.orderedExercises
        guard let idx = exercises.firstIndex(where: { $0.id == exercise.id }),
              idx + 1 < exercises.count
        else {
            return
        }
        let next = exercises[idx + 1]
        guard exercise.supersetGroup == nil || exercise.supersetGroup != next.supersetGroup else {
            return // already grouped together
        }

        let groupID = exercise.supersetGroup
            ?? next.supersetGroup
            ?? ((exercises.compactMap(\.supersetGroup).max() ?? 0) + 1)

        exercise.supersetGroup = groupID
        next.supersetGroup = groupID
        try? modelContext.save()
        HapticManager.selection()
    }

    /// Remove `exercise` from whatever superset/circuit it's currently in.
    /// Grouping is read by CONTIGUOUS run (see `circuitMembers`), not by the
    /// raw Int id, so breaking the MIDDLE of a 3-exercise circuit correctly
    /// leaves two independent groups/singles on either side.
    func breakGroup(_ exercise: PlannedExercise, modelContext: ModelContext) {
        guard exercise.supersetGroup != nil else {
            return
        }
        exercise.supersetGroup = nil
        try? modelContext.save()
        HapticManager.selection()
    }
}
