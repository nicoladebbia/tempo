//
// SetPlausibility.swift
// Tempo
//
// Pre-log sanity check for a set. A logged set feeds e1RM, PRs and next
// week's prescription directly, so a slip ("0 kg" from over-tapping minus,
// "300" instead of "30") used to poison the whole progression silently.
// This doesn't block anything — it asks once before an implausible set lands.
//

import Foundation

enum SetPlausibility {
    /// An e1RM this far above the lift's all-time best is almost certainly a typo.
    static let outlierFactor = 1.3

    /// A confirmation message for an implausible set, or nil when it looks fine.
    static func warning(
        weightKg: Double,
        reps: Int,
        bestE1RMKg: Double?,
        equipment: Equipment?,
        isWarmup: Bool
    ) -> String? {
        let bodyweightLoaded = equipment.map(StrengthStandards.isBodyweightLoaded) ?? false
        // Only kit that always carries a load. `.none`/`.bench`/nil cover
        // unmatched trainer/CSV moves (planks, burpees) where 0 kg is normal.
        let externallyLoaded: Bool = switch equipment {
        case .barbell, .dumbbell, .cable, .machine, .kettlebell, .smithMachine, .ezBar, .trapBar: true
        default: false
        }
        if externallyLoaded, weightKg <= 0 {
            return "0 kg logged. That set won't count toward your progress."
        }
        guard !isWarmup, !bodyweightLoaded, let best = bestE1RMKg, best > 0 else {
            return nil
        }
        // Epley is unreliable past ~12 reps — cap so a high-rep set isn't
        // flagged as a "record" it isn't.
        let e1RM = StrengthStandards.epleyE1RM(weight: weightKg, reps: min(reps, 12))
        if e1RM > best * outlierFactor {
            return "That's far beyond your best on this lift. Typo?"
        }
        return nil
    }
}
