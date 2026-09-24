//
// ActivitySession.swift
// Tempo
//

import Foundation
import SwiftData

// MARK: - ActivitySession

/// Permanent record of a non-gym training session (football, sprint,
/// conditioning, or any Whoop-tracked activity that isn't a barbell workout or
/// a distance run). It is the strain/HR sibling of `ExerciseHistory` (gym) and
/// `RunSession` (distance running): one row per completed non-gym session,
/// sport-tagged and date-stamped, queryable as a long-term personalization
/// dataset (training/nutrition/recovery tuning read it by date).
///
/// Like ExerciseHistory, it holds a SCALAR `workoutPlanID` back-reference, NOT
/// a SwiftData relationship — the record must outlive the ephemeral daily
/// WorkoutPlan and never be cascade-deleted by plan churn.
///
/// Every metric is OPTIONAL on purpose: a session can be saved by manual
/// attestation ("I played football today") with no Whoop activity attached, in
/// which case the metrics are nil but `sportID`/`workoutType`/`date`/`source`
/// still record that it happened.
@Model
final class ActivitySession {
    @Attribute(.unique)
    var id: UUID

    /// Day-normalized (start of day) for date-bucket queries.
    var date: Date

    /// Actual activity start (from Whoop), or the confirmation time for a
    /// manually-attested session.
    var startTime: Date

    /// The Tempo workout type this session represents (e.g. "football",
    /// "sprint", "conditioning"), raw value of `WorkoutType`.
    var workoutType: String

    /// Whoop sport id as reported by the activity (1 == soccer). Kept even when
    /// the user re-labels an untagged activity as football, so the data stays
    /// honest and correctable. -1 when there is no Whoop activity (manual).
    var sportID: Int

    /// "whoop" when derived from a fetched Whoop activity, "manual" when the
    /// user attested it with no Whoop data.
    var source: String

    /// Scalar back-reference to the WorkoutPlan this session completed. Enables
    /// exact idempotent dedup on save and exact cleanup on workout deletion.
    var workoutPlanID: UUID?

    // MARK: Whoop metrics (all optional — nil for manual attestation)

    var strain: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var caloriesBurned: Double?
    var durationMinutes: Double?

    // HR-zone minutes (Z1–Z5). Source: the Whoop export's zone percentages ×
    // duration (importer); the live API path doesn't carry zones yet. Additive
    // optionals per the §10 migration rule.
    var zone1Min: Double?
    var zone2Min: Double?
    var zone3Min: Double?
    var zone4Min: Double?
    var zone5Min: Double?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        startTime: Date,
        workoutType: String,
        sportID: Int,
        source: String,
        workoutPlanID: UUID? = nil,
        strain: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        caloriesBurned: Double? = nil,
        durationMinutes: Double? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.startTime = startTime
        self.workoutType = workoutType
        self.sportID = sportID
        self.source = source
        self.workoutPlanID = workoutPlanID
        self.strain = strain
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.caloriesBurned = caloriesBurned
        self.durationMinutes = durationMinutes
    }

    /// Minutes at high intensity (Z4+Z5) — the cleanest "how hard was it
    /// really" signal, sharper than whole-session strain. nil = no zone data.
    @Transient
    var hardMinutes: Double? {
        guard let z4 = zone4Min, let z5 = zone5Min else {
            return nil
        }
        return z4 + z5
    }
}
