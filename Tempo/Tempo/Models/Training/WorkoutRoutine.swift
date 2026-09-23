//
// WorkoutRoutine.swift
// Tempo
//
// A routine the athlete owns: an ordered list of exercises with working-set
// counts and superset/circuit groups. Deliberately NO weights — applying a
// routine re-prescribes loads from each lift's history + today's recovery
// (TrainingViewModel.applyRoutine), so "your exercises, Tempo's loads".
//

import Foundation
import SwiftData

struct RoutineItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: UUID
    /// Snapshot for display if the library entry is ever deleted.
    var exerciseName: String
    var workingSets: Int
    /// Items sharing a non-nil group run as a superset/circuit.
    var group: Int?
}

@Model
final class WorkoutRoutine {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var createdAt: Date
    var lastUsedAt: Date?
    var items: [RoutineItem]

    init(id: UUID = UUID(), name: String, items: [RoutineItem] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
    }
}
