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
        case .buildMuscle: String(localized: "Build muscle")
        case .loseFat: String(localized: "Lose fat")
        case .performance: String(localized: "Improve performance")
        case .stayHealthy: String(localized: "Stay healthy")
        case .allAround: String(localized: "All-around")
        }
    }

    var detail: String {
        switch self {
        case .buildMuscle: String(localized: "Gain size and strength")
        case .loseFat: String(localized: "Cut while keeping muscle")
        case .performance: String(localized: "Sport-specific gains")
        case .stayHealthy: String(localized: "Maintain and prevent")
        case .allAround: String(localized: "Balance everything")
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
