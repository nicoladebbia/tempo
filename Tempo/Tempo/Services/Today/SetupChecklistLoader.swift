//
// SetupChecklistLoader.swift
// Tempo
//
// Reads the app's real state into `SetupChecklist.Signals`. Nothing here is a
// flag the checklist keeps for itself: each answer comes from where the app
// already stores the fact.
//

import Foundation
import SwiftData

@MainActor
enum SetupChecklistLoader {
    static func signals(
        healthAllowed: Bool, whoopConnected: Bool, resolved: Bool, in context: ModelContext
    ) -> SetupChecklist.Signals {
        SetupChecklist.Signals(
            healthAllowed: healthAllowed,
            whoopConnected: whoopConnected,
            hasDietProfile: hasDietProfile(in: context),
            hasChosenTraining: hasChosenTraining(in: context),
            taskCount: activeTaskCount(in: context),
            resolved: resolved
        )
    }

    static func hasDietProfile(in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<DietaryProfile>(predicate: #Predicate<DietaryProfile> { $0.isActive == true })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// The training level was chosen, a trainer program exists, or a session
    /// was logged. The split alone does not count: it always has a default.
    static func hasChosenTraining(in context: ModelContext) -> Bool {
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
        if settings?.experienceLevelRaw != nil {
            return true
        }
        var program = FetchDescriptor<TrainerProgram>()
        program.fetchLimit = 1
        if ((try? context.fetchCount(program)) ?? 0) > 0 {
            return true
        }
        return hasCompletedSession(in: context)
    }

    /// At least one session was finished.
    static func hasCompletedSession(in context: ModelContext) -> Bool {
        let completed = WorkoutStatus.completed.rawValue
        var session = FetchDescriptor<WorkoutPlan>(predicate: #Predicate<WorkoutPlan> { $0.statusRaw == completed })
        session.fetchLimit = 1
        return ((try? context.fetchCount(session)) ?? 0) > 0
    }

    static func activeTaskCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<NonNegotiable>(predicate: #Predicate<NonNegotiable> { $0.isActive == true })
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
