//
// GuidedRunPlan.swift
// Tempo
//
// Guided run mode — turns a trainer-program conditioning session (its blocks
// + each block's parsed ConditioningTarget) into an ordered list of live-coach
// steps: a shuttle's timed reps, a drill's counted rounds, a continuous
// duration/distance run, or an open freeform timer. Pure data, built by
// `GuidedRunPlanBuilder` — no UI, no timers, no side effects. Everything here
// is Equatable and unit-tested (GuidedRunPlanBuilderTests) against the real
// sample program in TrainerProgramImportView.
//

import Foundation

// MARK: - GuidedRunTimedRep

/// A single timed rep against an optional cap — the shuttle-run shape ("4
/// reps of 25y ... < 65\""). `index`/`of` are 0-based / total across every
/// rep this block will ever ask for (all sets included). Grouped into a
/// struct (rather than 5 associated values on the enum case) per
/// SwiftLint's `enum_case_associated_values_count`.
struct GuidedRunTimedRep: Equatable {
    let index: Int
    let of: Int
    let capSeconds: Double?
    let distanceMeters: Double?
    let distanceLabel: String?
}

// MARK: - GuidedRunWorkKind

/// What one WORK step asks the athlete to do.
enum GuidedRunWorkKind: Equatable {
    case timedRep(GuidedRunTimedRep)
    /// A single counted round with no timing/cap — the drill/interval-sets
    /// shape ("2 x 10times").
    case round(index: Int, of: Int)
    /// One continuous block timed against a target duration — "35'".
    case continuousDuration(targetSeconds: Double)
    /// One continuous block measured against a target distance — "5 km".
    case continuousDistance(targetMeters: Double, targetLabel: String)
    /// Anything that didn't parse into a known shape — an open timer, the
    /// trainer's text shown verbatim, no target-met check.
    case freeform(text: String)
}

// MARK: - GuidedRunStepKind

enum GuidedRunStepKind: Equatable {
    case work(GuidedRunWorkKind)
    /// A rest between reps/rounds/sets. `seconds` is the trainer's rest if
    /// parseable, else a sensible default (GuidedRunPlanBuilder).
    case rest(seconds: Double)
}

// MARK: - GuidedRunStep

/// One entry in the flattened session order. `blockIndex`/`blockCount` are
/// the block's position in the day (for "block 1/2" UI), independent of
/// `GuidedRunWorkKind`'s own rep/round counters.
struct GuidedRunStep: Identifiable, Equatable {
    let id: UUID
    let blockID: UUID
    let blockIndex: Int
    let blockCount: Int
    let blockName: String
    /// The trainer's own text for this block, shown verbatim under the step
    /// name (block.detail, falling back to the block's name).
    let blockTrainerText: String
    let kind: GuidedRunStepKind

    init(
        id: UUID = UUID(),
        blockID: UUID,
        blockIndex: Int,
        blockCount: Int,
        blockName: String,
        blockTrainerText: String,
        kind: GuidedRunStepKind
    ) {
        self.id = id
        self.blockID = blockID
        self.blockIndex = blockIndex
        self.blockCount = blockCount
        self.blockName = blockName
        self.blockTrainerText = blockTrainerText
        self.kind = kind
    }

    /// Equatable ignoring `id` — steps built independently (e.g. expected
    /// fixtures in tests, or a rep cloned by "add a rep") should compare
    /// equal on content.
    static func == (lhs: GuidedRunStep, rhs: GuidedRunStep) -> Bool {
        lhs.blockID == rhs.blockID
            && lhs.blockIndex == rhs.blockIndex
            && lhs.blockCount == rhs.blockCount
            && lhs.blockName == rhs.blockName
            && lhs.blockTrainerText == rhs.blockTrainerText
            && lhs.kind == rhs.kind
    }

    var isWork: Bool {
        if case .work = kind {
            return true
        }
        return false
    }
}

// MARK: - GuidedRunBlock

/// One block's plan metadata — the summary screen and the "block 1/2"
/// progress row read this rather than re-deriving it from `steps`.
struct GuidedRunBlock: Identifiable, Equatable {
    /// = the source `ProgramExercise.id`.
    let id: UUID
    let name: String
    /// Display text — `rawDetail`, falling back to `name` so the UI never
    /// shows a blank line.
    let trainerText: String
    /// The source `ProgramExercise.detail` verbatim (may be nil) — this,
    /// not `trainerText`, is what `logConditioningBlock` re-parses, so
    /// guided-run logging matches the manual `ConditioningLogSheet` path
    /// exactly.
    let rawDetail: String?
    let target: ConditioningTarget
    /// Rest used between this block's own reps/rounds/sets.
    let restSeconds: Double
    /// False when this rest came from the trainer (structured or parsed) —
    /// true when it's Tempo's own default, the only case the pre-start
    /// screen offers a stepper for.
    let restIsDefault: Bool
}

// MARK: - GuidedRunPlan

struct GuidedRunPlan: Equatable {
    let blocks: [GuidedRunBlock]
    let steps: [GuidedRunStep]

    var isEmpty: Bool {
        steps.isEmpty
    }
}
