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
        case .push: String(localized: "Push")
        case .pull: String(localized: "Pull")
        case .legs: String(localized: "Legs")
        case .upper: String(localized: "Upper")
        case .lower: String(localized: "Lower")
        case .fullBody: String(localized: "Full Body")
        case .football: String(localized: "Football")
        case .run: String(localized: "Run")
        case .sprint: String(localized: "Sprint")
        case .conditioning: String(localized: "Conditioning")
        case .pool: String(localized: "Pool")
        case .mobility: String(localized: "Mobility")
        case .rest: String(localized: "Rest")
        }
    }

    /// Fixed English name for text that is sent to the AI, exported or stored,
    /// so it never changes with the app language. Use `displayName` on screen.
    var englishName: String {
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

    /// Map a daily-brain modality label (§13 — a free string, not an enum on
    /// the wire) to a plan type, so the day's final prescription can reshape
    /// the WorkoutPlan ROW (§8 connect). Direct rawValue match first, then the
    /// labels the brain actually emits. nil = unmappable → the plan row is
    /// left alone (the session card still renders the prescription).
    static func fromModality(_ modality: String) -> WorkoutType? {
        if let direct = WorkoutType(rawValue: modality) { return direct }
        switch modality.lowercased() {
        case "recovery", "off": return .rest
        case "swim": return .pool
        case "field": return .conditioning
        case "fullbody", "full body": return .fullBody
        default: return nil
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
        case .chest: String(localized: "Chest")
        case .back: String(localized: "Back")
        case .shoulders: String(localized: "Shoulders")
        case .biceps: String(localized: "Biceps")
        case .triceps: String(localized: "Triceps")
        case .forearms: String(localized: "Forearms")
        case .quads: String(localized: "Quads")
        case .hamstrings: String(localized: "Hamstrings")
        case .glutes: String(localized: "Glutes")
        case .calves: String(localized: "Calves")
        case .core: String(localized: "Core")
        case .fullBody: String(localized: "Full Body")
        case .cardio: String(localized: "Cardio")
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

    /// The word shown to the user. English matches the old capitalised raw value.
    var displayName: String {
        switch self {
        case .barbell: String(localized: "Barbell")
        case .dumbbell: String(localized: "Dumbbell")
        case .cable: String(localized: "Cable")
        case .machine: String(localized: "Machine")
        case .bodyweight: String(localized: "Bodyweight")
        case .kettlebell: String(localized: "Kettlebell")
        case .resistanceBand: String(localized: "Resistance Band")
        case .smithMachine: String(localized: "Smith Machine")
        case .ezBar: String(localized: "Ez Bar")
        case .trapBar: String(localized: "Trap Bar")
        case .pullUpBar: String(localized: "Pull Up Bar")
        case .bench: String(localized: "Bench")
        case .none: String(localized: "None")
        }
    }
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

// MARK: - DeloadStyle

/// §19.3 — how a deload week lightens the programme. Stored on UserSettings;
/// nil/unknown raw decodes to `.intensityCut` (the original fixed behavior).
enum DeloadStyle: String, Codable, CaseIterable {
    case intensityCut = "intensity_cut"
    case volumeCut = "volume_cut"
    case fullRest = "full_rest"

    var displayName: String {
        switch self {
        case .intensityCut: String(localized: "Lighter weights")
        case .volumeCut: String(localized: "Fewer sets")
        case .fullRest: String(localized: "Full rest")
        }
    }

    /// One-line description for the deload banner + settings footnote.
    var blurb: String {
        switch self {
        case .intensityCut: String(localized: "Weights reduced 40% — same reps, lighter load.")
        case .volumeCut: String(localized: "Half the working sets — same weights, less volume.")
        case .fullRest: String(localized: "No lifting this week — mobility and recovery only.")
        }
    }
}

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
    /// Heaviest weight ever lifted on this exercise (any reps). Raw value
    /// kept from when it was a "rep max", so stored rows still decode.
    case repMax = "rep_max"
    case volume
    /// Bodyweight-only sets: most reps in one set. `value` is the rep count.
    case mostReps = "most_reps"
}
