//
// TravelSwapEngine.swift
// Tempo
//
// "Limited equipment today/this week" (pause/travel-pain feature) — finds the
// closest library exercise with the SAME movement pattern and muscle group,
// built on equipment that's actually available (hotel room = bodyweight,
// hotel gym = dumbbells only, ...). Pure/decoupled from SwiftData, following
// `ExerciseMatcher`'s exact pattern (its own header: "Pure functions ... so
// the matching logic is unit-testable ... the caller supplies the current
// library as `[Candidate]`") — same file-neighborhood, same testing story.
//
// Used by `TrainingViewModel.populateFromTrainerProgram`
// (`TrainingViewModel+TrainerProgram.swift`) at generation time, so a swap
// never touches a set that's already been logged.
//

import Foundation

// MARK: - TravelSwapEngine

enum TravelSwapEngine {
    /// The only fields the engine needs — decoupled from the `Exercise`
    /// SwiftData model, same shape convention as `ExerciseMatcher.Candidate`.
    struct Candidate: Hashable {
        let id: UUID
        let name: String
        let equipment: Equipment
        let movementPattern: MovementPattern
        let muscleGroup: MuscleGroup
        let isCompound: Bool
    }

    /// Bodyweight/none never need "equipment" in the ordinary sense — always
    /// treated as available so a hotel-room athlete always has SOMETHING to
    /// fall back to for a pattern the library covers bodyweight-only.
    private static let alwaysAvailable: Set<Equipment> = [.bodyweight, .none]

    /// True when `equipment` is usable given `available` — bodyweight/none
    /// are always fine; anything else must be explicitly in the set.
    static func isUsable(_ equipment: Equipment, available: Set<Equipment>) -> Bool {
        alwaysAvailable.contains(equipment) || available.contains(equipment)
    }

    /// The closest replacement for `source` given what's available, or nil
    /// when nothing in the library covers this movement pattern + muscle
    /// group on the available gear (the caller then leaves the trainer's own
    /// exercise in place and the athlete does their best with it — never a
    /// crash, never a silently-dropped exercise).
    ///
    /// Ranking, best first:
    /// 1. Same movement pattern AND same primary muscle group (an exact
    ///    substitute — "Barbell RDL" -> "Dumbbell RDL").
    /// 2. Same movement pattern, different muscle group (rare — a pattern the
    ///    library only builds for one muscle group's variant).
    /// Within a tier: compound-ness matches source first, then shortest name
    /// (mirrors `ExerciseMatcher.tokenOverlapMatch`'s own tie-break), for a
    /// deterministic pick every time (no test flakiness, no "which one did it
    /// pick this run" surprises for the athlete).
    static func pickReplacement(
        for source: Candidate,
        in library: [Candidate],
        available: Set<Equipment>,
        excluding excludedIDs: Set<UUID> = []
    ) -> Candidate? {
        let pool = library.filter {
            $0.id != source.id && !excludedIDs.contains($0.id)
                && isUsable($0.equipment, available: available)
                && $0.movementPattern == source.movementPattern
        }
        guard !pool.isEmpty else {
            return nil
        }
        let sameMuscle = pool.filter { $0.muscleGroup == source.muscleGroup }
        let tier = sameMuscle.isEmpty ? pool : sameMuscle
        return tier.min { a, b in
            let aCompound = a.isCompound == source.isCompound
            let bCompound = b.isCompound == source.isCompound
            if aCompound != bCompound {
                return aCompound
            }
            if a.name.count != b.name.count {
                return a.name.count < b.name.count
            }
            return a.name < b.name
        }
    }
}
