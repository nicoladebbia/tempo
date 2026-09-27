//
// ConditioningBaselineProvider.swift
// Tempo
//
// trainer-feedback-tests — a run/sprint TEST's logged result
// (`ConditioningBlockResult.isBaselineTest`) becomes a baseline later
// conditioning blocks with the SAME distance shape can be shown against
// (e.g. "test 30m" today → "your best 30m: 4.30″" on a future 30m block).
// Matches on the parsed distance shape (distance + unit) via
// `ConditioningTargetParser` — the same distance written two different ways
// ("30m" vs "30 meters") still resolves to the same numeric shape, and
// EITHER distance-carrying kind counts:
//   - `.repsDistance` ("4 reps of 25y…", or a single-rep "1 rep 30m") — the
//     time is the best of `repTimesSeconds` (`ConditioningLogSheet`'s
//     per-rep time grid, built exactly for a short sprint time).
//   - `.distance` (a bare "test 30m", no rep count at all — the literal
//     phrasing a trainer is just as likely to write) — the time is
//     `durationSeconds` (`ConditioningLogSheet`'s "Duration (min)" field;
//     workable, if not ideal UX, for a sub-minute sprint).
// Pure and side-effect free, like the parser/evaluator it builds on.
//

import Foundation

enum ConditioningBaselineProvider {
    /// Best (lowest — fastest) time in seconds among TRUSTED baseline
    /// results whose block parses to a distance shape of this exact
    /// distance + unit. nil when nothing matches (no baseline test of this
    /// shape has ever been logged, or none of them had a time logged).
    static func bestTime(
        distance: Double,
        unit: ConditioningDistanceUnit,
        in results: [ConditioningBlockResult],
        program: TrainerProgram
    ) -> Double? {
        var best: Double?
        for result in results where result.isBaselineTest {
            guard let detail = detail(for: result, program: program),
                  let candidate = time(for: result, detail: detail, matching: distance, unit: unit)
            else {
                continue
            }
            if best == nil || candidate < best! {
                best = candidate
            }
        }
        return best
    }

    /// "Your best 30m: 4.30″" for a block whose OWN prescription is a
    /// distance shape — nil when that block isn't distance-shaped, or no
    /// baseline of that shape has been logged yet (including for the
    /// baseline block itself, on the day it's first logged — nothing to
    /// compare it to yet).
    static func displayLine(
        forDetail detail: String?,
        results: [ConditioningBlockResult],
        program: TrainerProgram
    ) -> String? {
        guard let (distance, unit) = distanceShape(of: ConditioningTargetParser.parse(detail: detail).kind) else {
            return nil
        }
        guard let best = bestTime(distance: distance, unit: unit, in: results, program: program) else {
            return nil
        }
        let distanceLabel = distance == distance.rounded() ? "\(Int(distance))" : String(format: "%.1f", distance)
        return "Your best \(distanceLabel)\(unit.shortLabel): \(formattedSeconds(best))"
    }

    static func formattedSeconds(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds))″" : String(format: "%.2f″", seconds)
    }

    /// This logged `result`'s own time, but ONLY if its prescription
    /// (`detail`) is a distance shape matching `distance`/`unit` exactly.
    private static func time(
        for result: ConditioningBlockResult,
        detail: String,
        matching distance: Double,
        unit: ConditioningDistanceUnit
    ) -> Double? {
        let target = ConditioningTargetParser.parse(detail: detail)
        guard let (targetDistance, targetUnit) = distanceShape(of: target.kind),
              targetUnit == unit, abs(targetDistance - distance) < 0.5
        else {
            return nil
        }
        switch target.kind {
        case .repsDistance:
            return result.repTimesSeconds?.min()
        case .distance:
            return result.durationSeconds
        default:
            return nil
        }
    }

    /// The distance + unit either distance-carrying `ConditioningTargetKind`
    /// carries, or nil for a shape with no distance at all (`.duration`,
    /// `.intervalSets`, `.freeform`).
    private static func distanceShape(of kind: ConditioningTargetKind) -> (distance: Double, unit: ConditioningDistanceUnit)? {
        switch kind {
        case let .repsDistance(_, distance, unit, _):
            (distance, unit)
        case let .distance(distance, unit):
            (distance, unit)
        default:
            nil
        }
    }

    /// The `ProgramExercise.detail` text a logged block came from, resolved
    /// via its `programSessionKey`/`blockID` — the parser needs the trainer's
    /// own written prescription, not anything from the logged result.
    private static func detail(for result: ConditioningBlockResult, program: TrainerProgram) -> String? {
        guard let key = result.programSessionKey, let blockID = result.blockID,
              let day = program.day(forSessionKey: key)
        else {
            return nil
        }
        return day.exercises.first { $0.id == blockID }?.detail
    }
}
