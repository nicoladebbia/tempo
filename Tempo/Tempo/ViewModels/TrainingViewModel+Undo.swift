//
// TrainingViewModel+Undo.swift
// Tempo
//
// Undo for the two things that change a live workout in one tap: logging a
// set and skipping one. Each captures what it needs BEFORE the change, and
// puts the session back exactly where it was: the set, its feedback row, the
// cursor, the rest timer.
//
// Undo is offered only where it can be exact. A log that set a personal record
// is not undoable (the record code can replace or upgrade older rows, and
// deleting the new one would not bring them back), nor is a calibration set
// (its weight already set the targets of the sets after it), nor a log that
// ended the workout. Those cases return nil, so no Undo is shown for them.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Logged set

    /// What a logged set changed, kept so Undo can reverse it.
    struct LoggedSetUndo {
        let setID: UUID
        let exerciseIndex: Int
        let weightKg: Double
        let reps: Int
        /// The signed added load for a bodyweight lift, so Undo can put the
        /// typed numbers back in the entry fields.
        let addedLoadKg: Double?
        /// The two sides of a per-side set logged separately, so Undo can
        /// bring the split back, not just one count.
        let leftReps: Int?
        let rightReps: Int?

        fileprivate let before: SetValues
        fileprivate let previousLastCompletedSet: PlannedSet?
        fileprivate let previousFeedback: SetFeedback?
    }

    /// The fields `logSet` writes on a set.
    struct SetValues {
        let actualWeight: Double?
        let actualReps: Int?
        let actualRepsLeft: Int?
        let actualRepsRight: Int?
        let addedLoadKg: Double?
        let rpe: Int?
        let completed: Bool
        let completedAt: Date?

        init(_ set: PlannedSet) {
            actualWeight = set.actualWeight
            actualReps = set.actualReps
            actualRepsLeft = set.actualRepsLeft
            actualRepsRight = set.actualRepsRight
            addedLoadKg = set.addedLoadKg
            rpe = set.rpe
            completed = set.completed
            completedAt = set.completedAt
        }

        func apply(to set: PlannedSet) {
            set.actualWeight = actualWeight
            set.actualReps = actualReps
            set.actualRepsLeft = actualRepsLeft
            set.actualRepsRight = actualRepsRight
            set.addedLoadKg = addedLoadKg
            set.rpe = rpe
            set.completed = completed
            set.completedAt = completedAt
        }
    }

    /// `logSet`, plus what Undo needs. Returns nil when this log cannot be
    /// undone exactly (see the file header) or did not log anything.
    @discardableResult
    func logSetCapturingUndo(
        weight: Double,
        reps: Int,
        addedLoadKg: Double? = nil,
        leftReps: Int? = nil,
        rightReps: Int? = nil,
        modelContext: ModelContext
    ) -> LoggedSetUndo? {
        let capture = captureBeforeLogging()
        logSet(
            weight: weight,
            reps: reps,
            addedLoadKg: addedLoadKg,
            leftReps: leftReps,
            rightReps: rightReps,
            modelContext: modelContext
        )
        guard let capture else {
            return nil
        }
        return capture.undoIfExact(
            in: self, weight: weight, reps: reps, addedLoadKg: addedLoadKg,
            leftReps: leftReps, rightReps: rightReps
        )
    }

    /// Reverses the last logged set: the set is open again with its old
    /// numbers, its feedback row is gone, the rest timer is stopped and the
    /// session is back on that set. False (and nothing changed) when it is no
    /// longer the last set logged or the session has moved on.
    @discardableResult
    func undoLoggedSet(_ undo: LoggedSetUndo, modelContext: ModelContext) -> Bool {
        guard canUndoLoggedSet(undo), let plan = todayPlan else {
            return false
        }
        let slot = plan.orderedExercises[undo.exerciseIndex]
        guard let set = slot.orderedSets.first(where: { $0.id == undo.setID }),
              let position = slot.orderedSets.firstIndex(where: { $0.id == undo.setID })
        else {
            return false
        }

        // The rest that the log started (same call Skip Rest makes).
        stopRestTimer()
        pendingRestAction = .nextSet

        undo.before.apply(to: set)

        let doomed = set.id
        let feedbackRows = (try? modelContext.fetch(
            FetchDescriptor<SetFeedback>(predicate: #Predicate { $0.setID == doomed })
        )) ?? []
        for row in feedbackRows {
            modelContext.delete(row)
        }

        currentExerciseIndex = undo.exerciseIndex
        currentSetIndex = position
        sessionState = .exercise(.setActive(exerciseIndex: undo.exerciseIndex, setIndex: position))
        lastCompletedSet = undo.previousLastCompletedSet
        currentFeedback = undo.previousFeedback

        saveGuarded(modelContext, operation: String(localized: "undo set"))
        HapticManager.selection()
        return true
    }

    /// True while `undo` is still the last set logged and the session is live
    /// on that same plan.
    func canUndoLoggedSet(_ undo: LoggedSetUndo) -> Bool {
        guard let plan = todayPlan,
              lastCompletedSet?.id == undo.setID,
              undo.exerciseIndex < plan.orderedExercises.count,
              let set = plan.orderedExercises[undo.exerciseIndex].orderedSets.first(where: { $0.id == undo.setID }),
              set.completed
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

    // MARK: - Capture

    /// Everything read before `logSet` runs, so it can be compared afterwards.
    @MainActor
    fileprivate struct LogCapture {
        let plan: WorkoutPlan
        let exerciseIndex: Int
        let set: PlannedSet
        let values: SetValues
        let detectedPRCount: Int
        let recordFingerprint: [String]
        let lastCompletedSet: PlannedSet?
        let feedback: SetFeedback?

        /// The undo, if the log changed nothing Undo cannot put back.
        func undoIfExact(
            in vm: TrainingViewModel,
            weight: Double,
            reps: Int,
            addedLoadKg: Double?,
            leftReps: Int?,
            rightReps: Int?
        ) -> LoggedSetUndo? {
            guard set.completed,
                  !set.isCalibration,
                  vm.detectedPRs.count == detectedPRCount,
                  vm.recordFingerprint(for: plan, exerciseIndex: exerciseIndex) == recordFingerprint
            else {
                return nil
            }
            switch vm.sessionState {
            case .exercise(.setActive),
                 .exercise(.resting),
                 .exercise(.betweenExercises):
                break
            default:
                return nil
            }
            return LoggedSetUndo(
                setID: set.id,
                exerciseIndex: exerciseIndex,
                weightKg: weight,
                reps: reps,
                addedLoadKg: addedLoadKg,
                leftReps: leftReps,
                rightReps: rightReps,
                before: values,
                previousLastCompletedSet: lastCompletedSet,
                previousFeedback: feedback
            )
        }
    }

    /// nil when there is no set to log (the log itself will do nothing).
    private func captureBeforeLogging() -> LogCapture? {
        guard let plan = todayPlan else {
            return nil
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return nil
        }
        let slot = exercises[currentExerciseIndex]
        let sets = slot.orderedSets
        guard currentSetIndex < sets.count, !sets[currentSetIndex].completed else {
            return nil
        }
        let set = sets[currentSetIndex]
        return LogCapture(
            plan: plan,
            exerciseIndex: currentExerciseIndex,
            set: set,
            values: SetValues(set),
            detectedPRCount: detectedPRs.count,
            recordFingerprint: recordFingerprint(for: plan, exerciseIndex: currentExerciseIndex),
            lastCompletedSet: lastCompletedSet,
            feedback: currentFeedback
        )
    }

    /// This session's records for one lift as "id|value" lines. A log that
    /// adds, replaces or upgrades a record changes it.
    private func recordFingerprint(for plan: WorkoutPlan, exerciseIndex: Int) -> [String] {
        let exercises = plan.orderedExercises
        guard exerciseIndex < exercises.count, let exercise = exercises[exerciseIndex].exercise else {
            return []
        }
        let planID = plan.id
        return (exercise.personalRecords ?? [])
            .filter { $0.workoutPlanID == planID }
            .map { "\($0.id.uuidString)|\($0.value)|\($0.typeRaw)" }
            .sorted()
    }

    // MARK: - Skipped sets

    /// Sets taken out of the plan by a skip, kept so Undo can put them back.
    struct SkippedSetsUndo {
        let exerciseIndex: Int
        let sets: [SetSnapshot]
        /// The set the cursor was on, to land on again.
        let cursorSetID: UUID?
        /// The last set logged when the skip happened. If it has changed,
        /// something was logged since and the old cursor means nothing.
        let lastLoggedSetID: UUID?

        /// "Skipped a set", "Skipped a warm-up set" or "Skipped 2 warm-up
        /// sets". Short on purpose: the exercise is already on screen, and a
        /// long toast takes over the page at large text sizes.
        var message: String {
            if sets.allSatisfy(\.isWarmup) {
                return sets.count == 1 ? String(localized: "Skipped a warm-up set") : String(localized: "Skipped \(sets.count) warm-up sets")
            }
            return String(localized: "Skipped a set")
        }
    }

    /// Every stored field of a `PlannedSet`, so a deleted one can be rebuilt
    /// the way it was.
    struct SetSnapshot {
        let id: UUID
        let setNumber: Int
        let targetReps: Int
        let targetWeight: Double?
        let targetRIR: Int?
        let actualReps: Int?
        let actualWeight: Double?
        let rpe: Int?
        let completed: Bool
        let restSeconds: Int?
        let completedAt: Date?
        let isWarmup: Bool
        let isCalibration: Bool
        let addedLoadKg: Double?
        let dropStepIndex: Int?
        let actualRepsLeft: Int?
        let actualRepsRight: Int?

        init(_ set: PlannedSet) {
            id = set.id
            setNumber = set.setNumber
            targetReps = set.targetReps
            targetWeight = set.targetWeight
            targetRIR = set.targetRIR
            actualReps = set.actualReps
            actualWeight = set.actualWeight
            rpe = set.rpe
            completed = set.completed
            restSeconds = set.restSeconds
            completedAt = set.completedAt
            isWarmup = set.isWarmup
            isCalibration = set.isCalibration
            addedLoadKg = set.addedLoadKg
            dropStepIndex = set.dropStepIndex
            actualRepsLeft = set.actualRepsLeft
            actualRepsRight = set.actualRepsRight
        }

        func rebuild(in slot: PlannedExercise) -> PlannedSet {
            let set = PlannedSet(
                id: id,
                setNumber: setNumber,
                targetReps: targetReps,
                targetWeight: targetWeight,
                targetRIR: targetRIR,
                actualReps: actualReps,
                actualWeight: actualWeight,
                rpe: rpe,
                completed: completed,
                restSeconds: restSeconds,
                isWarmup: isWarmup,
                isCalibration: isCalibration,
                addedLoadKg: addedLoadKg,
                dropStepIndex: dropStepIndex,
                actualRepsLeft: actualRepsLeft,
                actualRepsRight: actualRepsRight,
                plannedExercise: slot
            )
            set.completedAt = completedAt
            return set
        }
    }

    /// `skipCurrentSet`, plus what Undo needs. Nil when nothing was skipped or
    /// the skip ended the workout.
    @discardableResult
    func skipCurrentSetCapturingUndo(modelContext: ModelContext) -> SkippedSetsUndo? {
        guard case .exercise(.setActive) = sessionState, let plan = todayPlan else {
            skipCurrentSet(modelContext: modelContext)
            return nil
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            skipCurrentSet(modelContext: modelContext)
            return nil
        }
        let slot = exercises[currentExerciseIndex]
        let sets = slot.orderedSets
        guard currentSetIndex < sets.count, !sets[currentSetIndex].completed else {
            skipCurrentSet(modelContext: modelContext)
            return nil
        }
        let doomed = sets[currentSetIndex]
        let undo = SkippedSetsUndo(
            exerciseIndex: currentExerciseIndex,
            sets: [SetSnapshot(doomed)],
            cursorSetID: doomed.id,
            lastLoggedSetID: lastCompletedSet?.id
        )
        skipCurrentSet(modelContext: modelContext)
        return undoIsOffered(after: undo) ? undo : nil
    }

    /// `skipRemainingWarmups`, plus what Undo needs.
    @discardableResult
    func skipRemainingWarmupsCapturingUndo(modelContext: ModelContext) -> SkippedSetsUndo? {
        guard case .exercise(.setActive) = sessionState, let plan = todayPlan else {
            skipRemainingWarmups(modelContext: modelContext)
            return nil
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            skipRemainingWarmups(modelContext: modelContext)
            return nil
        }
        let slot = exercises[currentExerciseIndex]
        let doomed = slot.orderedSets.filter { $0.isWarmup && !$0.completed }
        guard !doomed.isEmpty else {
            skipRemainingWarmups(modelContext: modelContext)
            return nil
        }
        let undo = SkippedSetsUndo(
            exerciseIndex: currentExerciseIndex,
            sets: doomed.map(SetSnapshot.init),
            cursorSetID: doomed.first?.id,
            lastLoggedSetID: lastCompletedSet?.id
        )
        skipRemainingWarmups(modelContext: modelContext)
        return undoIsOffered(after: undo) ? undo : nil
    }

    /// Puts the skipped sets back in their old places and the cursor back on
    /// the first of them. False if the plan has changed so they cannot go back.
    @discardableResult
    func undoSkippedSets(_ undo: SkippedSetsUndo, modelContext: ModelContext) -> Bool {
        guard canUndoSkippedSets(undo), let plan = todayPlan else {
            return false
        }
        let slot = plan.orderedExercises[undo.exerciseIndex]
        let present = Set((slot.sets ?? []).map(\.id))
        for snapshot in undo.sets.sorted(by: { $0.setNumber < $1.setNumber }) where !present.contains(snapshot.id) {
            // A set added since the skip may have taken this number (skip the
            // last set, tap "add a set"): move the later ones up one so the
            // order stays stable and the skipped set lands where it was.
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
        let ordered = slot.orderedSets
        let position = undo.cursorSetID.flatMap { id in ordered.firstIndex { $0.id == id } } ?? 0
        currentExerciseIndex = undo.exerciseIndex
        currentSetIndex = position
        sessionState = .exercise(.setActive(exerciseIndex: undo.exerciseIndex, setIndex: position))
        saveGuarded(modelContext, operation: String(localized: "undo skip"))
        HapticManager.selection()
        return true
    }

    /// The skip is undoable while the workout is live and nothing has been
    /// logged since (a logged set would make the old cursor meaningless).
    func canUndoSkippedSets(_ undo: SkippedSetsUndo) -> Bool {
        guard let plan = todayPlan,
              undo.exerciseIndex < plan.orderedExercises.count,
              lastCompletedSet?.id == undo.lastLoggedSetID
        else {
            return false
        }
        switch sessionState {
        case .exercise(.setActive),
             .exercise(.betweenExercises):
            return true
        default:
            return false
        }
    }

    /// A skip that ended the workout (or left nowhere to stand) has no Undo.
    private func undoIsOffered(after undo: SkippedSetsUndo) -> Bool {
        switch sessionState {
        case .exercise(.setActive),
             .exercise(.betweenExercises):
            true
        default:
            false
        }
    }
}
