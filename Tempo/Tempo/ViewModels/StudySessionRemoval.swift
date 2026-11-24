//
// StudySessionRemoval.swift
// Tempo
//
// Deleting a focus session takes its minutes off everything that counted them:
// the day's study total (Today's tile and the Study page) and the day's Study
// task (the Lockdown card). One place does both, so they cannot disagree.
//

import Foundation
import SwiftData

enum StudySessionRemoval {
    /// Minutes left after taking `removed` off `current`. Never below zero.
    static func minutesLeft(current: Double, removing removed: Int) -> Double {
        max(0, current - Double(max(0, removed)))
    }

    /// Takes the session's minutes off its day and deletes it. A skipped Study task
    /// is left alone (it was never earned by minutes). A task the removal drops
    /// back under its target is re-opened by the engine, as a raised target is.
    /// The day's leisure unlock, once earned, stays.
    @MainActor
    static func remove(
        _ session: StudySession,
        engine: AccountabilityEngine = AccountabilityEngine(),
        modelContext: ModelContext
    ) {
        let minutes = session.durationMinutes
        if let day = session.dailyAccountability {
            day.totalStudyMinutes = Int(minutesLeft(current: Double(day.totalStudyMinutes), removing: minutes))
            let studyTask = (day.nonNegotiableProgress ?? []).first {
                $0.nonNegotiable?.type == .study && !$0.wasSkipped
            }
            if let studyTask {
                engine.updateProgress(
                    progress: studyTask,
                    newValue: minutesLeft(current: studyTask.currentValue, removing: minutes),
                    modelContext: modelContext
                )
            }
        }
        modelContext.delete(session)
        try? modelContext.save()
    }
}
