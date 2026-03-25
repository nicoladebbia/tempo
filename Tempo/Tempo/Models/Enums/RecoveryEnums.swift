import Foundation

// MARK: - RecoveryZone

enum RecoveryZone: String, Codable, CaseIterable, Sendable {
    case green
    case yellow
    case red

    init(score: Double) {
        switch score {
        case 67...100: self = .green
        case 34..<67: self = .yellow
        default: self = .red
        }
    }

    var colorAssetName: String {
        switch self {
        case .green: "tempo.color.recovery.green"
        case .yellow: "tempo.color.recovery.yellow"
        case .red: "tempo.color.recovery.red"
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - RecoveryInsightType

enum RecoveryInsightType: String, Codable, CaseIterable, Sendable {
    case correlation
    case pattern
    case recommendation
}
