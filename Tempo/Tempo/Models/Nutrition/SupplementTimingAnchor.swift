//
// SupplementTimingAnchor.swift
// Tempo
//
// WHEN in the day a supplement is taken, as a moment anchored to the user's
// real day (meals, training, sleep) rather than a fixed clock time. The
// timing engine resolves an anchor to minutes-after-midnight for a given day.
//

import Foundation

enum SupplementTimingAnchor: String, Codable, CaseIterable, Sendable {
    case wake
    case breakfast
    case lunch
    case dinner
    case preTraining
    case postTraining
    case bedtime

    var displayName: String {
        switch self {
        case .wake: "On waking"
        case .breakfast: "With breakfast"
        case .lunch: "With lunch"
        case .dinner: "With dinner"
        case .preTraining: "Before training"
        case .postTraining: "After training"
        case .bedtime: "Before bed"
        }
    }

    /// Evidence-based default when neither the user nor the plan says:
    /// creatine any consistent time (breakfast), fat-soluble D3 / omega-3
    /// with a meal, magnesium before bed, protein and electrolytes around
    /// training, pre-workout before it.
    static func defaultAnchor(for kind: SupplementKind) -> SupplementTimingAnchor {
        switch kind {
        case .creatine, .multivitamin, .vitamin: .breakfast
        case .omega3: .dinner
        case .protein, .electrolytes: .postTraining
        case .preworkout: .preTraining
        case .other: .breakfast
        }
    }
}
