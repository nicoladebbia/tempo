//
// GoalUndo.swift
// Tempo
//
// Removing the goal is a soft delete (`isActive = false`): the row, its start
// point and its readings stay. Undo flips the flag back, so what comes back is
// exactly what was there, start value and dates included.
//

import Foundation
import SwiftData

// MARK: - GoalUndo

@MainActor
enum GoalUndo {
    /// What a goal looked like before it was removed.
    struct State: Equatable {
        let id: UUID
        let wasActive: Bool

        init(_ goal: Goal) {
            id = goal.id
            wasActive = goal.isActive
        }
    }

    /// Takes the goal off (the same soft delete as before) and returns what Undo needs.
    static func remove(_ goal: Goal, in context: ModelContext) -> State {
        let state = State(goal)
        goal.isActive = false
        try? context.save()
        NotificationCenter.default.post(name: .tempoGoalChanged, object: nil)
        return state
    }

    /// Puts the goal back as it was. False when it is gone, or when another goal
    /// became the active one in the meantime (Undo must never leave two).
    @discardableResult
    static func restore(_ state: State, in context: ModelContext) -> Bool {
        let id = state.id
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.id == id })
        descriptor.fetchLimit = 1
        guard let goal = (try? context.fetch(descriptor))?.first else {
            return false
        }
        if state.wasActive, GoalReader.activeGoal(in: context) != nil {
            return false
        }
        goal.isActive = state.wasActive
        try? context.save()
        NotificationCenter.default.post(name: .tempoGoalChanged, object: nil)
        return true
    }
}
