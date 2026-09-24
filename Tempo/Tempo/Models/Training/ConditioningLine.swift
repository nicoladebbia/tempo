//
// ConditioningLine.swift
// Tempo
//
// Fix #8 (trainer report) — display-ready line for one logged conditioning
// block/result, independent of how it's actually stored. The real model,
// `ConditioningBlockResult` (workoutPlanID, programSessionKey, blockID,
// repTimesSeconds, durationSeconds, distanceMeters, roundsCompleted, rpe,
// notes, targetMet), is being added by another agent in parallel and is NOT
// part of this build.
//
// Once it lands: add ONE mapping function `ConditioningBlockResult ->
// ConditioningLine` and a `ConditioningResultProviding` conformance that
// fetches results by `programSessionKey` (the trainer's stable session
// identity — see `TrainerProgram.sessionKey`). Nothing else in the report
// pipeline (`TrainerReportBuilder`, `TrainerReportTextFormatter`,
// `TrainerReportPDFRenderer`) needs to change.
//

import Foundation

// MARK: - ConditioningLine

/// One logged conditioning result, already shaped for display. Times/
/// distances/rounds are all optional since a block may report only some of
/// them (a timed circuit has `durationSeconds`; an interval run has
/// `repTimesSeconds`; a row/run for distance has `distanceMeters`).
struct ConditioningLine: Identifiable, Hashable, Sendable {
    var id: UUID = .init()
    /// Which block within the session this result is for — the trainer's
    /// label/order, e.g. "Block 1", or the exercise name for a conditioning
    /// circuit the trainer wrote as free text (`ProgramExercise.detail`).
    var blockLabel: String
    var repTimesSeconds: [Double] = []
    var durationSeconds: Double?
    var distanceMeters: Double?
    var roundsCompleted: Int?
    var rpe: Int?
    var notes: String?
    var targetMet: Bool?
}

// MARK: - ConditioningResultProviding

/// Supplies logged conditioning results for a trainer-program session, keyed
/// by `TrainerProgram.sessionKey`. Let the report builder depend on this
/// protocol rather than a concrete model — the concrete `ConditioningBlockResult`
/// model can be wired in later without touching the builder.
protocol ConditioningResultProviding {
    func conditioningLines(forSessionKey sessionKey: String) -> [ConditioningLine]
}

// MARK: - EmptyConditioningResultProvider

/// Default provider used until `ConditioningBlockResult` is wired in — no
/// conditioning results available, which the report handles gracefully
/// (sessions simply show no conditioning block).
struct EmptyConditioningResultProvider: ConditioningResultProviding {
    func conditioningLines(forSessionKey sessionKey: String) -> [ConditioningLine] {
        []
    }
}
