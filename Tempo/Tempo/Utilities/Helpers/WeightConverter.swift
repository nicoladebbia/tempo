//
// WeightConverter.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

/// Converts between kg and lbs and snaps prescriptions to weights that
/// physically exist in a gym — in the USER'S DISPLAY UNIT. Prescribing on a
/// 2.5 kg lattice and converting produced numbers like "88 lbs" (a barbell
/// loads 85 or 90) and "27 lbs" on a cable stack (pins go in 5s). The fix:
/// snap in the display unit, store the kg equivalent.
enum WeightConverter {
    /// Convert kg to lbs.
    static func toLbs(_ kg: Double) -> Double {
        kg * 2.20462
    }

    /// Convert lbs to kg.
    static func toKg(_ lbs: Double) -> Double {
        lbs / 2.20462
    }

    /// Smallest real-world jump for this equipment, in the display unit.
    /// lbs gyms: 2.5 lb plates per side / 5 lb dumbbell + stack steps → 5.
    /// kg gyms: 1.25 kg plates per side → 2.5; stacks mostly 5 kg plates.
    static func increment(for equipment: Equipment, unit: WeightUnit) -> Double {
        switch unit {
        case .lbs:
            5
        case .kg:
            switch equipment {
            case .machine,
                 .cable:
                5
            case .kettlebell:
                4
            default:
                2.5
            }
        }
    }

    /// Real kettlebell bell sizes in kg. Gyms don't stock a bell every 2 kg —
    /// they jump 20 -> 22 -> 24 -> 28 (no 26), and 28 -> 32 -> 36 -> 40 -> 44
    /// -> 48 (no odd-4 step at the top either). The old fixed 4 kg lattice
    /// (`increment(for: .kettlebell, unit: .kg)`) missed every bell at 6, 10,
    /// 14, 18 and 22 kg and could snap a 21 kg prescription to 20 when the
    /// nearest REAL bell is 22. Kept separate from `increment` — that's still
    /// the right step size for a manual +/- stepper (NumericEntrySheet);
    /// this is for snapping a PRESCRIPTION to gear that actually exists.
    private static let kettlebellSizesKg: [Double] = [
        4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 40, 44, 48,
    ]

    /// Nearest bell; ties (a value exactly between two — the ladder steps by
    /// 2 kg from 4-24, so every odd kg in that range is exactly between two
    /// real bells) round UP rather than defaulting to whichever the array
    /// happens to list first.
    private static func nearestKettlebellKg(_ kg: Double) -> Double {
        var best = kettlebellSizesKg[0]
        var bestDistance = abs(best - kg)
        for size in kettlebellSizesKg.dropFirst() {
            let distance = abs(size - kg)
            if distance < bestDistance || (distance == bestDistance && size > best) {
                best = size
                bestDistance = distance
            }
        }
        return best
    }

    /// Bar weight in the display unit's REGIONAL standard — a US bar is
    /// 45 lbs, not the 44.1 a 20 kg bar converts to. Non-bar equipment → 0.
    static func barWeight(for equipment: Equipment, unit: WeightUnit) -> Double {
        switch unit {
        case .kg:
            equipment.barWeightKg
        case .lbs:
            switch equipment {
            case .barbell: 45
            case .ezBar: 25
            case .trapBar: 55
            default: 0
            }
        }
    }

    /// Snap a kg prescription so its display value is loadable: convert to
    /// the user's unit, round to the equipment increment, floor bar lifts at
    /// the bar itself (you can't bench 25 lbs on a 45 lb bar), convert back
    /// to kg for storage. Bodyweight-style equipment passes through — its
    /// "weight" is the lifter, not a load.
    static func loadableKg(_ kg: Double, equipment: Equipment, unit: WeightUnit) -> Double {
        guard kg > 0 else {
            return kg
        }
        switch equipment {
        case .bodyweight,
             .pullUpBar,
             .resistanceBand:
            return kg
        default:
            break
        }
        // Kettlebells in kg: snap to a REAL bell size, not a fixed lattice
        // (see kettlebellSizesKg above). In lbs, gyms already sell bells in
        // ~5 lb steps, which the generic path below already produces.
        if equipment == .kettlebell, unit == .kg {
            return nearestKettlebellKg(kg)
        }
        let display = unit == .kg ? kg : toLbs(kg)
        let step = increment(for: equipment, unit: unit)
        var snapped = max(step, (display / step).rounded() * step)
        let bar = barWeight(for: equipment, unit: unit)
        if equipment.isBarLoaded, bar > 0 {
            snapped = max(snapped, bar)
        }
        return unit == .kg ? snapped : toKg(snapped)
    }
}
