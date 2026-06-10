//
// WorkoutEnums.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - WorkoutType

enum WorkoutType: String, Codable, CaseIterable {
    case push
    case pull
    case legs
    case upper
    case lower
    case fullBody = "full_body"
    case football
    case run
    case sprint
    case conditioning
    /// §21/§13.1 — pool sessions (easy swim recovery / conditioning). Added
    /// 2026-06-09 with the soccer-emphasis week: Nicola has a pool; the AI
    /// modality list always offered it but no plan could hold it.
    case pool
    case mobility
    case rest

    var displayName: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .upper: "Upper"
        case .lower: "Lower"
        case .fullBody: "Full Body"
        case .football: "Football"
        case .run: "Run"
        case .sprint: "Sprint"
        case .conditioning: "Conditioning"
        case .pool: "Pool"
        case .mobility: "Mobility"
        case .rest: "Rest"
        }
    }

    var isGymWorkout: Bool {
        switch self {
        case .push,
             .pull,
             .legs,
             .upper,
             .lower,
             .fullBody: true
        default: false
        }
    }
}

// MARK: - WorkoutStatus

enum WorkoutStatus: String, Codable, CaseIterable {
    case planned
    case inProgress = "in_progress"
    case completed
    case skipped

    var isTerminal: Bool {
        self == .completed || self == .skipped
    }
}

// MARK: - MuscleGroup

enum MuscleGroup: String, Codable, CaseIterable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case calves
    case core
    case fullBody = "full_body"
    case cardio

    var displayName: String {
        switch self {
        case .fullBody: "Full Body"
        default: rawValue.capitalized
        }
    }
}

// MARK: - Equipment

enum Equipment: String, Codable, CaseIterable {
    case barbell
    case dumbbell
    case cable
    case machine
    case bodyweight
    case kettlebell
    case resistanceBand = "resistance_band"
    case smithMachine = "smith_machine"
    case ezBar = "ez_bar"
    case trapBar = "trap_bar"
    case pullUpBar = "pull_up_bar"
    case bench
    case none
}

extension Equipment {
    /// Whether the logged weight is loaded symmetrically on a bar, so the UI can
    /// show a per-side plate hint. Dumbbells/cables/machines are logged as the
    /// single displayed number with no per-side split.
    var isBarLoaded: Bool {
        switch self {
        case .barbell, .ezBar, .trapBar, .smithMachine: true
        default: false
        }
    }

    /// Approximate bar weight in kg, used only to derive the per-side plate hint
    /// from the total logged load. Smith machines are counterbalanced and vary
    /// widely, so they report 0 (hint shows total ÷ 2 with no bar subtracted).
    var barWeightKg: Double {
        switch self {
        case .barbell: 20
        case .ezBar: 10
        case .trapBar: 25
        default: 0
        }
    }
}

// MARK: - MovementPattern

enum MovementPattern: String, Codable, CaseIterable {
    case horizontalPush = "horizontal_push"
    case horizontalPull = "horizontal_pull"
    case verticalPush = "vertical_push"
    case verticalPull = "vertical_pull"
    case squat
    case hinge
    case lunge
    case carry
    case isolation
    case rotation
    case plank
    case cardio
}

// MARK: - PRType

enum PRType: String, Codable, CaseIterable {
    case oneRepMax = "1rm"
    case repMax = "rep_max"
    case volume
}
