//
// Goal.swift
// Tempo
//
// One target with a date: a body weight, a lift's estimated one-rep max, or
// a run time. Optional and additive: a person with no goal has no rows, and
// nothing else in the app depends on one.
//
// Values are stored in plain units (kilograms, seconds) and shown in the
// person's own unit by `GoalFormat`.
//

import Foundation
import SwiftData

// MARK: - GoalKind

enum GoalKind: String, CaseIterable, Identifiable {
    case bodyWeight
    case liftE1RM
    case runTime

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .bodyWeight: "Body weight"
        case .liftE1RM: "Lift"
        case .runTime: "Run time"
        }
    }

    var icon: String {
        switch self {
        case .bodyWeight: "scalemass.fill"
        case .liftE1RM: "dumbbell.fill"
        case .runTime: "figure.run"
        }
    }
}

// MARK: - Goal

@Model
final class Goal {
    @Attribute(.unique)
    var id: UUID
    var kindRaw: String
    /// Kilograms for a weight or a lift, seconds for a run.
    var targetValue: Double
    var targetDate: Date
    /// Where the line starts: the first reading when the goal was set. nil
    /// until there is one; the first reading after that becomes the start.
    var startValue: Double?
    var startDate: Date
    /// The lift's name ("Barbell Bench Press"). nil for the other kinds.
    var exerciseName: String?
    /// The run distance in kilometres (5, 10, 21.1). nil for the other kinds.
    var runDistanceKm: Double?
    var isActive: Bool
    var createdAt: Date

    init(
        kind: GoalKind,
        targetValue: Double,
        targetDate: Date,
        startValue: Double? = nil,
        startDate: Date = Date(),
        exerciseName: String? = nil,
        runDistanceKm: Double? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.targetValue = targetValue
        self.targetDate = targetDate
        self.startValue = startValue
        self.startDate = startDate
        self.exerciseName = exerciseName
        self.runDistanceKm = runDistanceKm
        self.isActive = true
        self.createdAt = Date()
    }

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .bodyWeight }
        set { kindRaw = newValue.rawValue }
    }
}
