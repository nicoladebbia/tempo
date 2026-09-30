//
// ExtraSessionRebalancer.swift
// Tempo
//
// After an extra gym session lands on a soccer day, TOMORROW's plan must not
// stack on the same muscles or the same accumulated load. Pure: takes
// tomorrow's template + what was added today, returns the adjustment (or nil
// when tomorrow is already fine). Applied at the end of week assembly.
//

import Foundation

// MARK: - ExtraSessionAdjustment

struct ExtraSessionAdjustment: Equatable, Sendable {
    /// Replacement type for tomorrow, nil = keep its type.
    let newType: WorkoutType?
    /// Multiplier on tomorrow's `recoveryAdjustment` (1.0 = unchanged).
    let recoveryScale: Double
    /// One line for the Tomorrow card, "Adjusted: ..." tone.
    let note: String
}

// MARK: - ExtraSessionRebalancer

nonisolated enum ExtraSessionRebalancer {
    static let hardCombinedScale = 0.9
    static let minRecoveryAdjustment = 0.5

    static func adjust(
        tomorrow: WorkoutType,
        extraFocus: WorkoutType,
        extraIntensity: SessionIntensity,
        soccerLoad: SoccerLoad,
        tomorrowIsPreMatch: Bool = false
    ) -> ExtraSessionAdjustment? {
        guard tomorrow.isGymWorkout, extraFocus.isGymWorkout else {
            return nil
        }
        let extraName = extraFocus.displayName.lowercased()
        let cause = "yesterday's soccer + \(extraName)"
        var newType: WorkoutType?

        if overlaps(extraFocus, tomorrow) {
            newType = tomorrowIsPreMatch ? .mobility : complement(of: tomorrow, after: extraFocus)
        }

        let hardCombined = soccerLoad == .hard && (extraIntensity == .moderate || extraIntensity == .hard)
        let scale = hardCombined && newType != .mobility ? hardCombinedScale : 1.0

        guard newType != nil || scale < 1.0 else {
            return nil
        }
        var note = "Adjusted: \(cause)"
        if let newType {
            note += ". \(tomorrow.displayName) became \(newType.displayName.lowercased())"
        }
        if scale < 1.0 {
            note += ". Lighter loads"
        }
        return ExtraSessionAdjustment(newType: newType, recoveryScale: scale, note: note)
    }

    /// Would `tomorrow` hit muscles the extra session just trained?
    static func overlaps(_ extra: WorkoutType, _ tomorrow: WorkoutType) -> Bool {
        let upperish: Set<WorkoutType> = [.push, .pull, .upper]
        let lowerish: Set<WorkoutType> = [.legs, .lower]
        if extra == tomorrow { return true }
        if extra == .fullBody { return upperish.contains(tomorrow) }
        if tomorrow == .fullBody { return upperish.contains(extra) }
        if upperish.contains(extra), upperish.contains(tomorrow) {
            return extra == .upper || tomorrow == .upper
        }
        return lowerish.contains(extra) && lowerish.contains(tomorrow)
    }

    private static func complement(of tomorrow: WorkoutType, after extra: WorkoutType) -> WorkoutType {
        let trainedBoth = extra == .upper || extra == .fullBody
        switch tomorrow {
        case .legs, .lower: return .upper
        case .push: return trainedBoth ? .legs : .pull
        case .pull: return trainedBoth ? .legs : .push
        case .upper: return extra == .push ? .pull : extra == .pull ? .push : .legs
        default: return .legs
        }
    }
}
