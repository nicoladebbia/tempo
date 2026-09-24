//
// ConditioningLine.swift
// Tempo
//
// Fix #8 (trainer report) — display-ready line for one logged conditioning
// block/result, independent of how it's stored. `StoredConditioningResults`
// maps the persisted `ConditioningBlockResult` rows into these; the report
// pipeline (`TrainerReportBuilder`, `TrainerReportTextFormatter`,
// `TrainerReportPDFRenderer`) only ever sees `ConditioningLine`.
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

/// Supplies logged conditioning results for one occurrence of a
/// trainer-program session: `TrainerProgram.sessionKey` plus the WorkoutPlan
/// it was done on. The key alone isn't enough — a repeating program reuses
/// the same key every cycle, so the plan pins the occurrence.
protocol ConditioningResultProviding {
    func conditioningLines(forSessionKey sessionKey: String, workoutPlanID: UUID?) -> [ConditioningLine]
}

// MARK: - EmptyConditioningResultProvider

/// No conditioning results — the report handles it gracefully (sessions
/// simply show no conditioning block).
struct EmptyConditioningResultProvider: ConditioningResultProviding {
    func conditioningLines(forSessionKey sessionKey: String, workoutPlanID: UUID?) -> [ConditioningLine] {
        []
    }
}

// MARK: - StoredConditioningResults

/// Maps logged `ConditioningBlockResult` rows to report lines, labelled with
/// the trainer's block name and kept in the program's block order.
struct StoredConditioningResults: ConditioningResultProviding {
    let results: [ConditioningBlockResult]
    let program: TrainerProgram

    func conditioningLines(forSessionKey sessionKey: String, workoutPlanID: UUID?) -> [ConditioningLine] {
        guard let workoutPlanID else {
            return []
        }
        let blocks = program.weeks.flatMap(\.days).flatMap(\.exercises)
        let order = Dictionary(blocks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(blocks.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return results
            .filter { $0.programSessionKey == sessionKey && $0.workoutPlanID == workoutPlanID }
            .sorted { lhs, rhs in
                (lhs.blockID.flatMap { order[$0] } ?? .max) < (rhs.blockID.flatMap { order[$0] } ?? .max)
            }
            .enumerated()
            .map { index, result in
                ConditioningLine(
                    id: result.id,
                    blockLabel: result.blockID.flatMap { names[$0] } ?? "Block \(index + 1)",
                    repTimesSeconds: result.repTimesSeconds ?? [],
                    durationSeconds: result.durationSeconds,
                    distanceMeters: result.distanceMeters,
                    roundsCompleted: result.roundsCompleted,
                    rpe: result.rpe.map { Int($0.rounded()) },
                    notes: result.notes,
                    targetMet: result.targetMet
                )
            }
    }
}
