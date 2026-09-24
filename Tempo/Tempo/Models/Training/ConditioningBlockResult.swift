//
// ConditioningBlockResult.swift
// Tempo
//
// Fix #7 — how a trainer-program conditioning block actually went: each
// shuttle's time against the trainer's cap, a run's duration/distance, drill
// rounds, effort. One row per logged block (ProgramExercise), keyed back to
// the WorkoutPlan and the program session it belongs to so both Today's card
// and Workout History can show it grouped under the day it happened.
//
// Every metric is optional — a block is loggable with whatever the athlete
// actually has (a time, a duration, a round count, or just RPE + notes), and
// `ConditioningTargetEvaluator` reads whichever fields its parsed target
// shape needs.
//

import Foundation
import SwiftData

@Model
final class ConditioningBlockResult {
    @Attribute(.unique)
    var id: UUID

    /// Scalar back-reference to the WorkoutPlan this result belongs to — same
    /// convention as `ActivitySession.workoutPlanID` (must outlive plan churn,
    /// never a cascading relationship).
    var workoutPlanID: UUID?

    /// The trainer-program session this block came from (`TrainerProgram
    /// .sessionKey`) — the plan's `programSessionKey` for a primary
    /// conditioning day, or `programSecondaryKey` for a two-a-day's second
    /// session. Used to resolve the block's prescription text back to
    /// `ProgramExercise.detail` for re-parsing/display.
    var programSessionKey: String?

    /// `ProgramExercise.id` this result logs.
    var blockID: UUID?

    /// Day-normalized (start of day), for date-bucket queries — mirrors
    /// `ActivitySession.date`.
    var date: Date

    /// Per-rep time in seconds, in rep order — the shuttle/interval shape
    /// ("4 reps of 25y ... < 65\"").
    var repTimesSeconds: [Double]?

    /// Whole-block duration — the "35'" run/effort shape.
    var durationSeconds: Double?

    /// Whole-block distance — the "5 km" / "800m" shape.
    var distanceMeters: Double?

    /// Drill/interval rounds actually completed — the "2 x 10times" shape.
    var roundsCompleted: Int?

    /// 1–10 perceived effort for this block.
    var rpe: Double?

    var notes: String?

    /// Result of `ConditioningTargetEvaluator.targetMet(...)` at log time, so
    /// the card/history don't need the parser + evaluator + raw detail text
    /// on hand to render a ✓/✗. nil when the target shape can't judge it
    /// (freeform, or a cap-less repsDistance).
    var targetMet: Bool?

    /// "manual" | "whoop" | "healthkit" — where duration/distance/HR came
    /// from. Rep times, rounds, RPE and notes are always athlete-entered.
    var source: String

    var createdAt: Date

    init(
        id: UUID = UUID(),
        workoutPlanID: UUID? = nil,
        programSessionKey: String? = nil,
        blockID: UUID? = nil,
        date: Date = Date(),
        repTimesSeconds: [Double]? = nil,
        durationSeconds: Double? = nil,
        distanceMeters: Double? = nil,
        roundsCompleted: Int? = nil,
        rpe: Double? = nil,
        notes: String? = nil,
        targetMet: Bool? = nil,
        source: String = "manual",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workoutPlanID = workoutPlanID
        self.programSessionKey = programSessionKey
        self.blockID = blockID
        self.date = Calendar.current.startOfDay(for: date)
        self.repTimesSeconds = repTimesSeconds
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.roundsCompleted = roundsCompleted
        self.rpe = rpe
        self.notes = notes
        self.targetMet = targetMet
        self.source = source
        self.createdAt = createdAt
    }
}
