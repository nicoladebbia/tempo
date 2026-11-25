//
// TrainingViewModel+DiscardUndo.swift
// Tempo
//
// Undo for throwing a whole workout away. Discarding rolls the plan back to
// "planned": logged sets are cleared, their feedback rows and this session's
// personal records are deleted, the clock is dropped. Everything that goes is
// copied first, so Undo can bring the session back on the set it was on.
//
// The session is brought back through the crash-recovery path
// (`resumeFromCrash`), which already knows how to rebuild the cursor, the
// timers, the call monitor and the Live Activity from a plan with logged sets.
// Nothing outside the app's own database changes when a workout is discarded
// (HealthKit and the server are written only when a workout is saved), so
// nothing outside it needs putting back.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// A discarded workout, kept for the few seconds Undo is offered.
    struct DiscardedWorkoutUndo: Identifiable {
        let id = UUID()
        let discardedAt = Date()
        let planID: UUID
        /// How many sets were logged, for the toast and for deciding whether
        /// there is anything worth offering Undo for.
        let loggedSets: Int

        fileprivate let status: WorkoutStatus
        fileprivate let startedAt: Date?
        fileprivate let pausedSeconds: Double
        fileprivate let pausedAt: Date?
        fileprivate let crashRecoveredAt: Date?
        fileprivate let loggedValues: [UUID: SetValues]
        fileprivate let painSkippedExercises: Set<UUID>
        fileprivate let feedback: [FeedbackCopy]
        fileprivate let records: [RecordCopy]
        fileprivate let detectedRecordIDs: [UUID]
    }

    /// A `SetFeedback` row as a plain value.
    fileprivate struct FeedbackCopy {
        let id: UUID
        let capturedAt: Date
        let setID: UUID
        let exerciseID: UUID?
        let rpe: Int
        let breathDifficultyRaw: String
        let formQualityRaw: String
        let note: String?
        let userProvidedFeedback: Bool
        let rpeProvided: Bool
        let breathProvided: Bool
        let formProvided: Bool
        let perFieldFlagsRecorded: Bool

        init(_ row: SetFeedback) {
            id = row.id
            capturedAt = row.capturedAt
            setID = row.setID
            exerciseID = row.exerciseID
            rpe = row.rpe
            breathDifficultyRaw = row.breathDifficultyRaw
            formQualityRaw = row.formQualityRaw
            note = row.note
            userProvidedFeedback = row.userProvidedFeedback
            rpeProvided = row.rpeProvided
            breathProvided = row.breathProvided
            formProvided = row.formProvided
            perFieldFlagsRecorded = row.perFieldFlagsRecorded
        }

        @MainActor
        func rebuild(attachedTo set: PlannedSet?) -> SetFeedback {
            let row = SetFeedback(
                id: id,
                capturedAt: capturedAt,
                plannedSet: set,
                setID: setID,
                exerciseID: exerciseID,
                rpe: rpe,
                note: note
            )
            row.breathDifficultyRaw = breathDifficultyRaw
            row.formQualityRaw = formQualityRaw
            row.userProvidedFeedback = userProvidedFeedback
            row.rpeProvided = rpeProvided
            row.breathProvided = breathProvided
            row.formProvided = formProvided
            row.perFieldFlagsRecorded = perFieldFlagsRecorded
            return row
        }
    }

    /// A `PersonalRecord` row as a plain value.
    fileprivate struct RecordCopy {
        let id: UUID
        let typeRaw: String
        let value: Double
        let date: Date
        let workoutPlanID: UUID?
        let context: String?
        let contextWeightKg: Double?
        let contextReps: Int?
        let exerciseNameSnapshot: String?
        let exerciseID: UUID?

        init(_ record: PersonalRecord) {
            id = record.id
            typeRaw = record.typeRaw
            value = record.value
            date = record.date
            workoutPlanID = record.workoutPlanID
            context = record.context
            contextWeightKg = record.contextWeightKg
            contextReps = record.contextReps
            exerciseNameSnapshot = record.exerciseNameSnapshot
            exerciseID = record.exercise?.id
        }

        @MainActor
        func rebuild(exercise: Exercise?) -> PersonalRecord {
            let record = PersonalRecord(
                id: id,
                type: PRType(rawValue: typeRaw) ?? .oneRepMax,
                value: value,
                date: date,
                workoutPlanID: workoutPlanID,
                context: context,
                contextWeightKg: contextWeightKg,
                contextReps: contextReps,
                exercise: exercise
            )
            record.exerciseNameSnapshot = exerciseNameSnapshot
            return record
        }
    }

    // MARK: - Discard

    /// `discardActiveWorkout`, plus what Undo needs. Returns nil when there
    /// was nothing to discard, or when the session had logged nothing (no work
    /// is lost then, so there is nothing to offer Undo for).
    @discardableResult
    func discardActiveWorkoutCapturingUndo(modelContext: ModelContext) -> DiscardedWorkoutUndo? {
        let capture = captureBeforeDiscarding(modelContext: modelContext)
        discardActiveWorkout(modelContext: modelContext)
        guard let capture, capture.loggedSets > 0, sessionState == .discarded || sessionState == .idle else {
            return nil
        }
        discardUndo = capture
        return capture
    }

    /// Reads the plan before the discard clears it.
    private func captureBeforeDiscarding(modelContext: ModelContext) -> DiscardedWorkoutUndo? {
        switch sessionState {
        case .warmup,
             .exercise,
             .cooldown,
             .paused,
             .interruptedCall,
             .crashedRecovery:
            break
        default:
            return nil
        }
        guard let plan = todayPlan else {
            return nil
        }
        var values: [UUID: SetValues] = [:]
        var painSkipped: Set<UUID> = []
        for slot in plan.orderedExercises {
            if slot.painSkipped {
                painSkipped.insert(slot.id)
            }
            for set in slot.orderedSets where set.completed {
                values[set.id] = SetValues(set)
            }
        }
        let setIDs = Set(values.keys)
        let feedback = ((try? modelContext.fetch(FetchDescriptor<SetFeedback>())) ?? [])
            .filter { setIDs.contains($0.setID) }
            .map(FeedbackCopy.init)
        let planID = plan.id
        let records = ((try? modelContext.fetch(
            FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.workoutPlanID == planID })
        )) ?? []).map(RecordCopy.init)
        return DiscardedWorkoutUndo(
            planID: plan.id,
            loggedSets: values.count,
            status: plan.status,
            startedAt: plan.startedAt,
            pausedSeconds: plan.pausedSeconds,
            pausedAt: plan.pausedAt,
            crashRecoveredAt: plan.crashRecoveredAt,
            loggedValues: values,
            painSkippedExercises: painSkipped,
            feedback: feedback,
            records: records,
            detectedRecordIDs: detectedPRs.map(\.id)
        )
    }

    /// Brings a discarded workout back: its logged sets, feedback and records
    /// are written again, the plan is in progress again and the session resumes
    /// on the first set still open. False (and nothing changed) when the plan
    /// is no longer the one that was discarded, or another session has started.
    @discardableResult
    func undoDiscardedWorkout(_ undo: DiscardedWorkoutUndo, modelContext: ModelContext) -> Bool {
        guard canUndoDiscardedWorkout(undo), let plan = todayPlan else {
            return false
        }

        for slot in plan.orderedExercises {
            slot.painSkipped = undo.painSkippedExercises.contains(slot.id)
            for set in slot.orderedSets {
                if let values = undo.loggedValues[set.id] {
                    values.apply(to: set)
                }
            }
        }
        plan.status = undo.status
        plan.startedAt = undo.startedAt
        plan.pausedSeconds = undo.pausedSeconds
        plan.pausedAt = undo.pausedAt
        plan.crashRecoveredAt = undo.crashRecoveredAt

        let sets = Dictionary(
            plan.orderedExercises.flatMap(\.orderedSets).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingFeedback = Set(
            ((try? modelContext.fetch(FetchDescriptor<SetFeedback>())) ?? []).map(\.id)
        )
        for copy in undo.feedback where !existingFeedback.contains(copy.id) {
            modelContext.insert(copy.rebuild(attachedTo: sets[copy.setID]))
        }

        let exercises = Dictionary(
            plan.orderedExercises.compactMap(\.exercise).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingRecords = Set(
            ((try? modelContext.fetch(FetchDescriptor<PersonalRecord>())) ?? []).map(\.id)
        )
        var restored: [PersonalRecord] = []
        for copy in undo.records where !existingRecords.contains(copy.id) {
            let record = copy.rebuild(exercise: copy.exerciseID.flatMap { exercises[$0] })
            modelContext.insert(record)
            restored.append(record)
        }

        saveGuarded(modelContext, operation: String(localized: "restored workout"))

        // Back into the session through the crash-recovery path.
        discardUndo = nil
        sessionState = .crashedRecovery
        resumeFromCrash()
        // The crash path guesses how long the app was dead and counts a long
        // idle stretch as paused. Here nothing was dead: put the clock back as
        // it was, and count only the time the workout really sat discarded (and
        // any pause that was open when it was discarded) as paused.
        let now = Date()
        let openPause = undo.pausedAt.map { max(0, undo.discardedAt.timeIntervalSince($0)) } ?? 0
        let paused = undo.pausedSeconds + openPause + max(0, now.timeIntervalSince(undo.discardedAt))
        plan.pausedSeconds = paused
        plan.pausedAt = nil
        plan.crashRecoveredAt = undo.crashRecoveredAt
        totalPauseDuration = paused
        if let startedAt = plan.startedAt {
            elapsedSeconds = max(0, now.timeIntervalSince(startedAt) - paused)
        }
        saveGuarded(modelContext, operation: String(localized: "restored workout"))
        detectedPRs = restored.filter { undo.detectedRecordIDs.contains($0.id) }
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        HapticManager.selection()
        return true
    }

    /// True while the plan that was discarded is still today's plan, open to
    /// redo and with no session running.
    func canUndoDiscardedWorkout(_ undo: DiscardedWorkoutUndo) -> Bool {
        guard let plan = todayPlan,
              plan.id == undo.planID,
              plan.status == .planned
        else {
            return false
        }
        // Reloading the day can rebuild a still-planned workout from scratch.
        // If any set that was logged is gone, there is nothing to put the
        // numbers back on: refuse instead of resuming an empty session.
        let present = Set(plan.orderedExercises.flatMap(\.orderedSets).map(\.id))
        guard undo.loggedValues.keys.allSatisfy(present.contains) else {
            return false
        }
        // `.discarded` is the moment before the day reloads and settles on
        // `.idle`; undoing inside it would be overwritten by that settle.
        return sessionState == .idle
    }

    /// The Undo button: waits (up to six seconds) for the day to finish
    /// reloading after the discard, then brings the workout back.
    @discardableResult
    func undoDiscardedWorkoutWhenSettled(_ undo: DiscardedWorkoutUndo, modelContext: ModelContext) async -> Bool {
        var waited = 0
        while sessionState == .discarded, waited < 60 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        return undoDiscardedWorkout(undo, modelContext: modelContext)
    }

    /// Makes the discard final: the Undo window has passed.
    func forgetDiscardedWorkout() {
        discardUndo = nil
    }
}
