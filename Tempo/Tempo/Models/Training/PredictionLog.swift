//
// PredictionLog.swift
// Tempo
//
// Step 1 (measurement spine) of the realistic-intelligence rebuild. The
// training engine is a thermostat with no thermometer: it adapts prescriptions
// but never records what it predicted vs. what actually happened, so "is it
// getting more accurate for this user?" is unanswerable. This model IS the
// thermometer.
//
// One row per prescribed working exercise: written at PRESCRIBE time
// (populateExercises) with what the engine predicted, then backfilled at SAVE
// time (persistCompletion) with what the user actually did. The
// prediction↔outcome pair is the raw material for prediction error (Step 2) —
// the only honest basis for "adapts correctly / measurably right over time."
//
// Deliberately a passive LEDGER: nothing reads it to change prescriptions yet.
// Writing it is decoupled from acting on it so the spine can be verified before
// anything depends on it.
//

import Foundation
import SwiftData

@Model
final class PredictionLog {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    /// When the prediction was made (prescribe time, start-of-day normalized).
    var date: Date

    // MARK: - Scope (matched the same way ExerciseHistory dedups)

    /// The exercise this prediction is for. Denormalized scalar IDs below are
    /// the stable join keys — the prediction must outlive the ephemeral plan.
    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    /// Stable `Exercise.id` at prescribe time (survives plan pruning).
    var exerciseID: UUID

    /// Stable `WorkoutPlan.id` the prediction belongs to. With `exerciseID`,
    /// this is the exact pair `persistCompletion` uses to find the row and
    /// backfill its outcome — same key as ExerciseHistory.workoutPlanID.
    var workoutPlanID: UUID

    // MARK: - Prediction (written at prescribe time)

    /// Prescribed working weight (kg, post recovery/deload adjustment + rounding).
    var predictedWeight: Double

    /// Prescribed working reps target.
    var predictedReps: Int

    /// The RPE the engine IMPLICITLY targets for a working set. The progression
    /// rule holds at avgRPE ≥ 9 and accelerates at ≤ 6.5, so the intended
    /// landing zone is ~8. Prediction error in Step 2 = actualRPE − this.
    var predictedRPE: Double

    /// Which decision path produced the prescription
    /// (`ProgressionReason.rawValue`) — the "signal used", for attributing error
    /// to a cause later.
    var signalUsedRaw: String

    /// The learned increment in play at prescribe time (nil = equipment
    /// default). Lets Step 2 see whether personalization was active.
    var learnedIncrementUsed: Double?

    // MARK: - Outcome (backfilled at save time; nil until the session is logged)

    /// Best-set reps actually achieved this session.
    var actualReps: Int?

    /// Mean entered RPE this session (nil = no entered feedback).
    var actualRPE: Double?

    /// Worst entered form (`FormQuality.rawValue`, nil = none).
    var actualFormRaw: String?

    /// Best-set weight actually used (kg) — may differ from predicted if the
    /// user overrode the load mid-session.
    var actualWeight: Double?

    /// True once the outcome has been backfilled — distinguishes "trained, no
    /// feedback entered" (resolved, actuals may be nil) from "never trained"
    /// (unresolved). Step 2 scores only resolved rows with an actualRPE.
    var outcomeResolved: Bool = false

    // MARK: - Typed accessors

    @Transient
    var signalUsed: ProgressionReason? {
        ProgressionReason(rawValue: signalUsedRaw)
    }

    /// Signed RPE prediction error (actual − predicted), or nil if unresolved /
    /// no entered RPE. Positive = harder than intended (over-prescribed);
    /// negative = easier (under-prescribed). The core Step-2 signal.
    @Transient
    var rpeError: Double? {
        guard outcomeResolved, let actualRPE else { return nil }
        return actualRPE - predictedRPE
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        exercise: Exercise? = nil,
        exerciseID: UUID,
        workoutPlanID: UUID,
        predictedWeight: Double,
        predictedReps: Int,
        predictedRPE: Double = 8.0,
        signalUsedRaw: String,
        learnedIncrementUsed: Double? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.exercise = exercise
        self.exerciseID = exerciseID
        self.workoutPlanID = workoutPlanID
        self.predictedWeight = predictedWeight
        self.predictedReps = predictedReps
        self.predictedRPE = predictedRPE
        self.signalUsedRaw = signalUsedRaw
        self.learnedIncrementUsed = learnedIncrementUsed
    }
}
