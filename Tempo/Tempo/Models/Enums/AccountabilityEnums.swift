import Foundation

// MARK: - NonNegotiableType

enum NonNegotiableType: String, Codable, CaseIterable, Sendable {
    case study
    case train
    case meals
    case sleep
    case steps
    case hydration
    case custom

    var defaultIcon: String {
        switch self {
        case .study: "book.fill"
        case .train: "dumbbell.fill"
        case .meals: "fork.knife"
        case .sleep: "moon.fill"
        case .steps: "figure.walk"
        case .hydration: "drop.fill"
        case .custom: "star.fill"
        }
    }
}

// MARK: - TrackingMethod

enum TrackingMethod: String, Codable, CaseIterable, Sendable {
    case autoWhoop = "auto_whoop"
    case autoNutritrack = "auto_nutritrack"
    case autoHealthkit = "auto_healthkit"
    case manual
    case timer
}

// MARK: - StudySessionType

enum StudySessionType: String, Codable, CaseIterable, Sendable {
    case pomodoro
    case deepWork = "deep_work"
    case custom
}

// MARK: - StreakType

enum StreakType: String, Codable, CaseIterable, Sendable {
    case overall
    case study
    case training
    case meals
    case nonNegotiables = "non_negotiables"
}
