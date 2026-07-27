//
// StrengthStandards.swift
// Tempo
//
// Cold-start strength estimation — the single source of truth for "what weight
// should a lift the user has NEVER done start at?".
//
// Replaces the old flat per-equipment `defaultWeight` table (barbell squat and
// barbell overhead press both getting 40 kg), which produced the "some weights
// way too high, others way too low" complaint. Everything here is expressed in
// estimated-1RM (e1RM) terms and derived DOWN to a working weight for the
// target reps via the inverse of the Epley formula the rest of the app already
// uses (`PlannedSet.estimated1RM = w * (1 + reps/30)`), so the currency is
// consistent end-to-end.
//
// DESIGN NOTES (deliberate, read before tuning):
//   • All math is in KILOGRAMS. Every stored training weight in Tempo is kg
//     internally (UI converts at the boundary only), so there is no unit
//     conversion here and none is wanted.
//   • The coefficients are ESTIMATES, biased LOW on purpose. An over-heavy
//     suggestion on a novel barbell lift is the injury case; a too-light one is
//     a single wasted set. The cost is asymmetric, so we err light and let the
//     first 1-2 logged sessions self-correct via real e1RM. Do NOT chase
//     "accurate" standards here — accuracy is the job of history, not the seed.
//   • Barbell-family compounds are bodyweight-relative (a 90 kg lifter should
//     not start a squat at the same absolute weight as a 60 kg lifter).
//     Dumbbell / cable / machine / kettlebell and all isolations get their own
//     conservative ABSOLUTE seeds — machine "weight" is a stack number with
//     leverage baked in and is not comparable to a barbell load, so it is never
//     cross-inferred from the bodyweight table.
//   • Every constant lives here, named, so tuning happens in one file.
//
enum StrengthStandards {
    // MARK: - Epley (forward + inverse)

    /// e1RM for a set of `weight × reps` — the SAME Epley form used by
    /// `PlannedSet.estimated1RM`, so estimates round-trip with stored history.
    static func epleyE1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }

    /// Working weight that should yield `reps` reps given an `e1RM`. Exact
    /// algebraic inverse of `epleyE1RM`, so a lift whose history was logged at
    /// exactly the target reps derives back to the same weight (no drift).
    static func inverseEpleyWeight(e1RM: Double, reps: Int) -> Double {
        guard reps > 0 else { return e1RM }
        if reps == 1 { return e1RM }
        return e1RM / (1 + Double(reps) / 30.0)
    }

    // MARK: - Experience

    /// Multiplier applied to the intermediate anchors. `experienceLevel` is the
    /// raw onboarding string ("Beginner"/"Intermediate"/"Advanced"); ANY unknown
    /// or nil value falls to the Beginner (lowest, safest) coefficient — never
    /// intermediate — so a missing profile biases light, not heavy.
    static func experienceMultiplier(_ experienceLevel: String?) -> Double {
        switch experienceLevel?.lowercased() {
        case "advanced": advancedMultiplier
        case "intermediate": intermediateMultiplier
        default: beginnerMultiplier // "beginner", nil, or anything unrecognized
        }
    }

    private static let beginnerMultiplier = 0.65
    private static let intermediateMultiplier = 1.0
    private static let advancedMultiplier = 1.3

    /// Global safety haircut on every cold-start estimate. Bias-low knob: raise
    /// toward 1.0 if starts feel too light across the board; lower if any start
    /// ever feels heavy. Applied on top of the experience multiplier.
    private static let safetyHaircut = 0.85

    // MARK: - Bodyweight-relative anchors (barbell-family compounds)

    /// Intermediate male e1RM as a MULTIPLE of bodyweight, per movement pattern.
    /// Conservative anchors (real intermediate norms trimmed) — the experience
    /// multiplier and safety haircut pull these further down for most users.
    private static func bodyweightMultiple(for pattern: MovementPattern) -> Double? {
        switch pattern {
        case .squat: 1.25
        case .hinge: 1.5
        case .horizontalPush: 0.9
        case .horizontalPull: 0.85
        case .verticalPush: 0.55
        case .lunge: 0.7
        // verticalPull is bodyweight-loaded (pull-ups) — handled by the
        // bodyweight-movement path, not the barbell table.
        default: nil
        }
    }

    /// Bodyweight-movement e1RM as a multiple of bodyweight (pull-ups, dips,
    /// bodyweight rows). The EFFECTIVE 1RM = bodyweight ± added load; a beginner
    /// often needs assist (effective < BW), an advanced lifter adds weight
    /// (effective > BW). Anchor is "intermediate can do a clean single at ~1×BW".
    private static func bodyweightMovementMultiple(for pattern: MovementPattern) -> Double {
        switch pattern {
        case .verticalPull: 1.0 // pull-ups / chin-ups
        case .horizontalPush: 1.0 // dips (loaded push) — anchor near BW
        case .horizontalPull: 0.9 // bodyweight rows
        default: 0.9
        }
    }

    // MARK: - Absolute seeds (dumbbell / cable / machine / kettlebell + isolations)

    /// Conservative absolute e1RM seed (kg) for lifts that are NOT
    /// bodyweight-relative. Keyed by (equipment, isCompound). Dumbbell values are
    /// PER-DUMBBELL (Tempo logs dumbbell weight per hand). Intentionally on the
    /// low side; self-corrects after one session.
    private static func absoluteSeedE1RM(equipment: Equipment, isCompound: Bool) -> Double {
        switch (equipment, isCompound) {
        case (.dumbbell, true): 20
        case (.dumbbell, false): 10
        case (.cable, true): 32
        case (.cable, false): 16
        case (.machine, true): 40
        case (.machine, false): 25
        case (.kettlebell, true): 20
        case (.kettlebell, false): 12
        case (.smithMachine, true): 40
        case (.smithMachine, false): 25
        // Barbell/EZ isolation (e.g. barbell curl, skull crusher) — absolute, not BW-relative.
        case (.barbell, false), (.ezBar, false), (.trapBar, false): 22
        case (.ezBar, true), (.trapBar, true): 50
        case (.resistanceBand, _): 10
        default: 20 // last-resort conservative seed
        }
    }

    // MARK: - Cold-start e1RM (no history, no relative)

    /// Estimated e1RM for an exercise the user has never logged and that has no
    /// usable sibling. Barbell-family compounds use the bodyweight table when a
    /// bodyweight is known; everything else uses an absolute seed. Returns nil
    /// only if there is genuinely nothing to go on (should be rare).
    static func baselineE1RM(
        for exercise: Exercise,
        bodyweightKg: Double?,
        experienceLevel: String?
    ) -> Double {
        let expMult = experienceMultiplier(experienceLevel)
        let scale = expMult * safetyHaircut

        // Bodyweight-loaded movement (pull-up/dip/bodyweight row): BW-relative.
        if isBodyweightLoaded(exercise.equipment), let bw = bodyweightKg, bw > 0 {
            return bw * bodyweightMovementMultiple(for: exercise.movementPattern) * scale
        }

        // Barbell-family COMPOUND with a known bodyweight and a mapped pattern.
        if isBarbellFamily(exercise.equipment),
           exercise.isCompound,
           let bw = bodyweightKg, bw > 0,
           let mult = bodyweightMultiple(for: exercise.movementPattern) {
            return bw * mult * scale
        }

        // Everything else — conservative absolute seed.
        return absoluteSeedE1RM(equipment: exercise.equipment, isCompound: exercise.isCompound) * scale
    }

    // MARK: - Cross-exercise inference (sibling ratio)

    /// e1RM inferred for `target` from a `sibling` lift the user HAS logged,
    /// given the sibling's own e1RM. Only meaningful when the two share a load
    /// basis (both free-weight-non-bodyweight, or both bodyweight); the caller is
    /// responsible for that gate. A novel variant of a movement the user already
    /// trains is usually slightly weaker than the trained one, so we haircut.
    static func siblingE1RM(target: Exercise, sibling: Exercise, siblingE1RM: Double) -> Double {
        let sameEquipment = target.equipmentRaw == sibling.equipmentRaw
        let ratio = sameEquipment ? sameEquipmentSiblingRatio : crossEquipmentSiblingRatio
        return siblingE1RM * ratio
    }

    /// Whether two exercises share a load basis for sibling inference.
    static func shareLoadBasis(_ a: Exercise, _ b: Exercise) -> Bool {
        isBodyweightLoaded(a.equipment) == isBodyweightLoaded(b.equipment)
    }

    private static let sameEquipmentSiblingRatio = 0.95
    private static let crossEquipmentSiblingRatio = 0.85

    // MARK: - Rounding

    /// Smallest sensible load increment (kg) for the equipment, used to round a
    /// derived weight to something loadable. Centralized so gym-specific plate
    /// sets can be tuned in one place later.
    static func increment(for equipment: Equipment) -> Double {
        switch equipment {
        case .dumbbell: 2.0 // typical fixed-dumbbell jump
        default: 2.5 // barbell/machine/cable/etc — nearest 2.5 kg
        }
    }

    /// Round a weight to the equipment's loadable increment (never negative).
    static func roundToIncrement(_ weight: Double, equipment: Equipment) -> Double {
        let step = increment(for: equipment)
        guard step > 0 else { return max(0, weight) }
        return max(0, (weight / step).rounded() * step)
    }

    // MARK: - Equipment classification

    /// Lifts whose load is the lifter's bodyweight plus/minus external load.
    static func isBodyweightLoaded(_ equipment: Equipment) -> Bool {
        switch equipment {
        case .bodyweight, .pullUpBar: true
        default: false
        }
    }

    /// Straight-bar loaded lifts that the bodyweight-relative table applies to.
    static func isBarbellFamily(_ equipment: Equipment) -> Bool {
        switch equipment {
        case .barbell, .ezBar, .trapBar, .smithMachine: true
        default: false
        }
    }
}
