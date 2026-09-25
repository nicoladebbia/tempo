//
// GuidedRunPlanBuilder.swift
// Tempo
//
// Guided run mode — turns a conditioning `ProgramDay` into an ordered
// `GuidedRunPlan`. Pure and side-effect free (GuidedRunPlanBuilderTests,
// exercised against the real sample program in TrainerProgramImportView):
//
// - repsDistance ("4 reps of 25y ... < 65\"") -> N timed reps + rests
//   (N x block.sets when the trainer wrote multiple sets of the same
//   shuttle).
// - duration ("35'") -> one continuous step (x block.sets if >1, with a
//   rest between).
// - intervalSets ("2 x 10times") -> sets*reps counted rounds + rests.
// - distance ("5 km") -> one continuous distance step (x block.sets).
// - freeform -> one open timer step showing the trainer's text (x
//   block.sets).
//
// Rest between reps/rounds/sets: the trainer's own `restSeconds` field wins
// (it's the structured value the review screen already edits); else a
// rest mined from the free text (GuidedRunRestParser); else a sensible
// default — 90s for shuttle reps, 60s for everything else — editable before
// starting (GuidedRunView's pre-start rest stepper).
//

import Foundation

enum GuidedRunPlanBuilder {
    /// Only a conditioning day (`!day.isStrength`) has anything to guide — a
    /// lift day returns an empty plan. `restOverrides` (blockID -> seconds)
    /// lets the pre-start screen edit a DEFAULT rest before `start()` —
    /// only ever offered for blocks where `resolveRest` found no trainer
    /// rest (structured or parsed); a trainer-specified rest is never
    /// overridden here.
    static func build(day: ProgramDay, restOverrides: [UUID: Double] = [:]) -> GuidedRunPlan {
        guard !day.isStrength else {
            return GuidedRunPlan(blocks: [], steps: [])
        }

        var blocks: [GuidedRunBlock] = []
        var steps: [GuidedRunStep] = []
        let blockCount = day.exercises.count

        for (blockIndex, block) in day.exercises.enumerated() {
            let target = ConditioningTargetParser.parse(detail: block.detail)
            let resolved = resolveRest(for: block, target: target)
            let restSeconds = resolved.isDefault ? (restOverrides[block.id] ?? resolved.seconds) : resolved.seconds
            let blockSteps = buildSteps(
                block: block,
                blockIndex: blockIndex,
                blockCount: blockCount,
                target: target,
                restSeconds: restSeconds
            )
            steps.append(contentsOf: blockSteps)
            blocks.append(GuidedRunBlock(
                id: block.id,
                name: block.name,
                trainerText: trainerText(for: block),
                rawDetail: block.detail,
                target: target,
                restSeconds: restSeconds,
                restIsDefault: resolved.isDefault
            ))
        }

        return GuidedRunPlan(blocks: blocks, steps: steps)
    }

    // MARK: - Rest resolution

    /// 90s default for shuttle-style capped reps (anaerobic), 60s for
    /// everything else (drills, easy continuous efforts between sets).
    /// `isDefault` is false whenever the trainer's OWN rest was found
    /// (structured `restSeconds` field, or mined from the free text).
    static func resolveRest(for block: ProgramExercise, target: ConditioningTarget) -> (seconds: Double, isDefault: Bool) {
        if let structured = block.restSeconds, structured > 0 {
            return (Double(structured), false)
        }
        if let parsed = GuidedRunRestParser.parseSeconds(block.detail) {
            return (parsed, false)
        }
        switch target.kind {
        case .repsDistance: return (90, true)
        default: return (60, true)
        }
    }

    private static func trainerText(for block: ProgramExercise) -> String {
        if let detail = block.detail, !detail.isEmpty {
            return detail
        }
        return block.name
    }

    // MARK: - Per-block step building

    private static func buildSteps(
        block: ProgramExercise,
        blockIndex: Int,
        blockCount: Int,
        target: ConditioningTarget,
        restSeconds: Double
    ) -> [GuidedRunStep] {
        func makeStep(_ kind: GuidedRunStepKind) -> GuidedRunStep {
            GuidedRunStep(
                blockID: block.id,
                blockIndex: blockIndex,
                blockCount: blockCount,
                blockName: block.name,
                blockTrainerText: trainerText(for: block),
                kind: kind
            )
        }

        switch target.kind {
        case let .repsDistance(reps, distance, unit, capSeconds):
            let groups = max(1, block.sets)
            let repsPerGroup = max(1, reps)
            let total = groups * repsPerGroup
            var result: [GuidedRunStep] = []
            for globalIndex in 0 ..< total {
                result.append(makeStep(.work(.timedRep(GuidedRunTimedRep(
                    index: globalIndex,
                    of: total,
                    capSeconds: capSeconds,
                    distanceMeters: unit.meters(distance),
                    distanceLabel: distanceLabel(distance, unit)
                )))))
                if globalIndex < total - 1 {
                    result.append(makeStep(.rest(seconds: restSeconds)))
                }
            }
            return result

        case let .duration(minutes):
            return repeatedContinuous(
                groups: max(1, block.sets),
                restSeconds: restSeconds,
                makeStep: makeStep
            ) { .continuousDuration(targetSeconds: minutes * 60) }

        case let .intervalSets(sets, reps):
            let total = max(1, sets * reps)
            var result: [GuidedRunStep] = []
            for index in 0 ..< total {
                result.append(makeStep(.work(.round(index: index, of: total))))
                if index < total - 1 {
                    result.append(makeStep(.rest(seconds: restSeconds)))
                }
            }
            return result

        case let .distance(value, unit):
            return repeatedContinuous(
                groups: max(1, block.sets),
                restSeconds: restSeconds,
                makeStep: makeStep
            ) { .continuousDistance(targetMeters: unit.meters(value), targetLabel: distanceLabel(value, unit)) }

        case .freeform:
            let text = trainerText(for: block)
            return repeatedContinuous(
                groups: max(1, block.sets),
                restSeconds: restSeconds,
                makeStep: makeStep
            ) { .freeform(text: text) }
        }
    }

    /// Shared "repeat this single continuous work kind `groups` times, with
    /// a rest between" builder used by duration/distance/freeform.
    private static func repeatedContinuous(
        groups: Int,
        restSeconds: Double,
        makeStep: (GuidedRunStepKind) -> GuidedRunStep,
        workKind: () -> GuidedRunWorkKind
    ) -> [GuidedRunStep] {
        var result: [GuidedRunStep] = []
        for group in 0 ..< groups {
            result.append(makeStep(.work(workKind())))
            if group < groups - 1 {
                result.append(makeStep(.rest(seconds: restSeconds)))
            }
        }
        return result
    }

    static func distanceLabel(_ value: Double, _ unit: ConditioningDistanceUnit) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))\(unit.shortLabel)"
    }
}
