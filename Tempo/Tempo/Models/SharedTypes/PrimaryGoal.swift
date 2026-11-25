//
// PrimaryGoal.swift
// Tempo
//
// The one goal a person picks in onboarding ("what are you fighting for?"). Stored on
// `UserSettings.primaryGoalRaw` and changed in Settings > Profile.
//

import Foundation

// MARK: - PrimaryGoal

enum PrimaryGoal: String, CaseIterable, Codable, Sendable {
    case buildMuscle = "build_muscle"
    case loseFat = "lose_fat"
    case performance
    case stayHealthy = "stay_healthy"
    case allAround = "all_around"

    var title: String {
        switch self {
        case .buildMuscle: "Build muscle"
        case .loseFat: "Lose fat"
        case .performance: "Improve performance"
        case .stayHealthy: "Stay healthy"
        case .allAround: "All-around"
        }
    }

    var detail: String {
        switch self {
        case .buildMuscle: "Gain size and strength"
        case .loseFat: "Cut while keeping muscle"
        case .performance: "Sport-specific gains"
        case .stayHealthy: "Maintain and prevent"
        case .allAround: "Balance everything"
        }
    }

    var icon: String {
        switch self {
        case .buildMuscle: "dumbbell.fill"
        case .loseFat: "flame.fill"
        case .performance: "bolt.fill"
        case .stayHealthy: "heart.fill"
        case .allAround: "circle.hexagongrid.fill"
        }
    }

    /// Reads a saved value: the raw value, or the title the older onboarding saved ("Build Muscle").
    init?(saved: String?) {
        guard let saved, !saved.isEmpty else {
            return nil
        }
        if let known = PrimaryGoal(rawValue: saved) {
            self = known
            return
        }
        let wanted = saved.lowercased()
        guard let match = Self.allCases.first(where: { $0.title.lowercased() == wanted }) else {
            return nil
        }
        self = match
    }
}
