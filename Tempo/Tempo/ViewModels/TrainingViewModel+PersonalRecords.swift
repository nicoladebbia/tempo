//
// TrainingViewModel+PersonalRecords.swift
// Tempo
//
// One place that turns a logged working set into a personal record, shared
// by the phone (`logSet`) and the watch (`applyWatchSetLog`). The engine
// decides WHETHER the set beats everything before today's session; this
// keeps today's session to one row per (lift, record type) and one toast
// per lift.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    enum PersonalRecordOutcome: Equatable {
        case none
        /// A new record row — announce it (toast + haptic) once per lift.
        case new
        /// Today's row for this lift/type got a better set — no new toast.
        case upgraded
    }

    @discardableResult
    func recordPersonalRecordIfAny(
        exercise: Exercise,
        weight: Double,
        reps: Int,
        rir: Int,
        plan: WorkoutPlan,
        modelContext: ModelContext
    ) -> PersonalRecordOutcome {
        guard let candidate = trainingEngine.detectPersonalRecord(
            exercise: exercise, weight: weight, reps: reps, rir: rir, workoutPlanID: plan.id
        ) else {
            return .none
        }
        let planID = plan.id
        let candidateID = candidate.id
        // Linking to the (managed) exercise may already have inserted the
        // candidate — look past it for today's existing row.
        let existing = (exercise.personalRecords ?? []).first {
            $0.id != candidateID && $0.workoutPlanID == planID && $0.typeRaw == candidate.typeRaw
        }
        if let existing {
            let better = candidate.value > existing.value + TrainingEngine.personalRecordEpsilon
            if better {
                existing.value = candidate.value
                existing.date = candidate.date
                existing.context = candidate.context
                existing.contextWeightKg = candidate.contextWeightKg
                existing.contextReps = candidate.contextReps
            }
            modelContext.delete(candidate)
            return better ? .upgraded : .none
        }
        modelContext.insert(candidate)
        // One announcement per lift per session: a second record type on the
        // same lift replaces its summary line instead of firing another toast.
        if let index = detectedPRs.firstIndex(where: { $0.exercise?.id == exercise.id }) {
            detectedPRs[index] = candidate
            return .upgraded
        }
        detectedPRs.append(candidate)
        return .new
    }
}
