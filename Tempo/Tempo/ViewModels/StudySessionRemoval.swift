//
// StudySessionRemoval.swift
// Tempo
//
// Deleting a focus session takes its minutes off everything that counted them:
// the day's study total (Today's tile and the Study page) and the day's Study
// task (the Lockdown card). One place does both, so they cannot disagree. When
// that undoes a Study task finished today, the day's unlock goes back with it.
// The Study streak is not touched: the morning reset credits it from the day's
// stored result, so it follows the re-opened task by itself.
//

import Foundation
import SwiftData

enum StudySessionRemoval {
    /// The timer's short break, which sits between two pomodoros of a session.
    static let shortBreakMinutes = 5

    /// Minutes left after taking `removed` off `current`. Never below zero.
    static func minutesLeft(current: Double, removing removed: Int) -> Double {
        max(0, current - Double(max(0, removed)))
    }

    /// The minutes the timer added to the day for a session. A session records
    /// the time it ran, short breaks included, while the timer credits only the
    /// focus time of each finished pomodoro, so the breaks between pomodoros come
    /// off. A pomodoro session with none finished was cancelled and never
    /// credited; any other kind counts what it ran.
    static func creditedMinutes(
        durationMinutes: Int, completedPomodoros: Int, sessionType: StudySessionType
    ) -> Int {
        let ran = max(0, durationMinutes)
        switch (sessionType, completedPomodoros) {
        case (.pomodoro, ...0):
            return 0
        case (.pomodoro, let finished):
            return max(0, ran - (finished - 1) * shortBreakMinutes)
        default:
            return ran
        }
    }

    static func creditedMinutes(of session: StudySession) -> Int {
        creditedMinutes(
            durationMinutes: session.durationMinutes,
            completedPomodoros: session.completedPomodoros,
            sessionType: session.sessionType
        )
    }

    /// Takes the session's credited minutes off its day and deletes it.
    ///
    /// - The Study task is left alone when it was skipped, or ticked by hand with
    ///   fewer session minutes than its target: minutes never earned it.
    /// - Today: a task the removal drops back under its target re-opens (the
    ///   engine does the same when a target is raised), and since the day is no
    ///   longer complete its unlock goes too.
    /// - An earlier day is a closed record: its numbers come down, nothing else
    ///   about it changes.
    @MainActor
    static func remove(
        _ session: StudySession,
        engine: AccountabilityEngine = AccountabilityEngine(),
        calendar: Calendar = .current,
        modelContext: ModelContext
    ) {
        let minutes = creditedMinutes(of: session)
        if let day = session.dailyAccountability {
            day.totalStudyMinutes = Int(minutesLeft(current: Double(day.totalStudyMinutes), removing: minutes))
            let studyTask = (day.nonNegotiableProgress ?? []).first {
                $0.nonNegotiable?.type == .study && !$0.wasSkipped
            }
            let earned = (day.studySessions ?? []).reduce(0) { $0 + creditedMinutes(of: $1) }
            let tickedByHand = studyTask.map { $0.isCompleted && Double(earned) < $0.targetValue } ?? false
            if let studyTask, !tickedByHand {
                let left = minutesLeft(current: studyTask.currentValue, removing: minutes)
                if calendar.isDateInToday(day.date) {
                    let wasCompleted = studyTask.isCompleted
                    engine.updateProgress(progress: studyTask, newValue: left, modelContext: modelContext)
                    if wasCompleted, !studyTask.isCompleted {
                        day.leisureUnlocked = false
                        day.unlockedAt = nil
                    }
                } else {
                    studyTask.currentValue = left
                }
            }
        }
        modelContext.delete(session)
        try? modelContext.save()
    }
}
