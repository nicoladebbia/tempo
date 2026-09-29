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
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable Machine"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .pullUpBar: "Pull-Up Bar"
        case .ezBar: "EZ Bar"
        case .none: "No equipment"
        // Raw values are snake_case ("pull_up_bar" rendered "Pull_Up_Bar").
        default: equipment.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
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
