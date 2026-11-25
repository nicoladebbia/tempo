//
// TodayWorkoutView+Equipment.swift
// Tempo
//
// Equipment label/icon helpers for Today's exercise cards — split out of
// TodayWorkoutView.swift to keep it under the SwiftLint file length cap.
//

import SwiftUI

extension TodayWorkoutView {
    func equipmentHint(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: String(localized: "Barbell")
        case .dumbbell: String(localized: "Dumbbell")
        case .cable: String(localized: "Cable Machine")
        case .machine: String(localized: "Machine")
        case .bodyweight: String(localized: "Bodyweight")
        case .kettlebell: String(localized: "Kettlebell")
        case .pullUpBar: String(localized: "Pull-Up Bar")
        case .ezBar: String(localized: "EZ Bar")
        case .none: String(localized: "No equipment")
        default: equipment.displayName
        }
    }

    /// SF Symbol for equipment type — used in place of emoji.
    func equipmentIcon(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: "figure.strengthtraining.traditional"
        case .dumbbell: "dumbbell.fill"
        case .cable: "cable.connector"
        case .machine: "gearshape.fill"
        case .bodyweight: "figure.flexibility"
        case .kettlebell: "figure.strengthtraining.functional"
        default: "figure.mixed.cardio"
        }
    }
}
