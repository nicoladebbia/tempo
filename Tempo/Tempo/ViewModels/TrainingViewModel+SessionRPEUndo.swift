//
// TrainingViewModel+SessionRPEUndo.swift
// Tempo
//
// Undo for the one-tap "how hard was that?" rating after a workout. The card
// takes the rating in one tap with ten close buttons and has no way back
// afterwards, so a wrong tap used to stay. The rating is written in two places
// (the plan and the daily session it pairs with); both are put back.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// A session rating just given, kept so Undo can take it back.
    struct SessionRPEUndo {
        let planID: UUID
        let rating: Int
        fileprivate let previousPlanRPE: Int?
        fileprivate let previousDailyRPE: Int?
    }

    /// `recordSessionRPE`, plus what Undo needs. Nil when nothing was recorded.
    @discardableResult
    func recordSessionRPECapturingUndo(_ rpe: Int, modelContext: ModelContext) -> SessionRPEUndo? {
        guard (1 ... 10).contains(rpe), let plan = todayPlan, plan.status == .completed else {
            recordSessionRPE(rpe, modelContext: modelContext)
            return nil
        }
        let undo = SessionRPEUndo(
            planID: plan.id,
            rating: rpe,
            previousPlanRPE: plan.sessionRPE,
            previousDailyRPE: dailySession?.actualSessionRPE
        )
        recordSessionRPE(rpe, modelContext: modelContext)
        return plan.sessionRPE == rpe ? undo : nil
    }

    /// Takes the rating back: the card asks again. False (and nothing changed)
    /// when the plan is no longer today's, or the rating has been changed since.
    @discardableResult
    func undoSessionRPE(_ undo: SessionRPEUndo, modelContext: ModelContext) -> Bool {
        guard let plan = todayPlan, plan.id == undo.planID, plan.sessionRPE == undo.rating else {
            return false
        }
        plan.sessionRPE = undo.previousPlanRPE
        dailySession?.actualSessionRPE = undo.previousDailyRPE
        saveGuarded(modelContext, operation: String(localized: "session RPE"))
        HapticManager.selection()
        return true
    }
}
