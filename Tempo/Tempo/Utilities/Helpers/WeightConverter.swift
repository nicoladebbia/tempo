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
            return 5
        case .kg:
            switch equipment {
            case .machine, .cable:
                return 5
            case .kettlebell:
                return 4
            default:
                return 2.5
            }
        }
    }

    /// Bar weight in the display unit's REGIONAL standard — a US bar is
    /// 45 lbs, not the 44.1 a 20 kg bar converts to. Non-bar equipment → 0.
    static func barWeight(for equipment: Equipment, unit: WeightUnit) -> Double {
        switch unit {
        case .kg:
            return equipment.barWeightKg
        case .lbs:
            switch equipment {
            case .barbell: return 45
            case .ezBar: return 25
            case .trapBar: return 55
            default: return 0
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
        case .bodyweight, .pullUpBar, .resistanceBand:
            return kg
        default:
            break
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
