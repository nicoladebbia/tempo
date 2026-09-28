//
// TrainingViewModel+Pause.swift
// Tempo
//
// "I'm sick / taking a break" (pause/travel-pain feature). New file — see
// `TrainingPause.swift` (model) and `TrainingPauseSchedule.swift` (pure
// overlay logic). Mirrors `TrainingViewModel+TrainerProgram.swift`'s own
// fetch/apply/notify pattern so this reads as "the same kind of feature",
// not a bolt-on.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Fetch

    func fetchTrainingPauses(modelContext: ModelContext) -> [TrainingPause] {
        (try? modelContext.fetch(FetchDescriptor<TrainingPause>())) ?? []
    }

    /// The pause currently covering `date` (default today), if any.
    func activePause(asOf date: Date = Date(), modelContext: ModelContext) -> TrainingPause? {
        TrainingPauseSchedule.coveringPause(fetchTrainingPauses(modelContext: modelContext), on: date)
    }

    /// A pause whose planned end has passed (or that was resumed) but that
    /// still needs its fixed-mode resume decision recorded — drives the
    /// "Welcome back — pick up where you left off?" prompt. nil once
    /// `resumePause` has run for it, or for a sequence-mode/program-less
    /// pause (nothing to decide — see `TrainingPause.swift` header).
    func pendingResumeDecision(modelContext: ModelContext, now: Date = Date()) -> TrainingPause? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return fetchTrainingPauses(modelContext: modelContext).first { pause in
            guard pause.resumeDecision == nil, pause.scheduleModeAtPauseTyped == .fixed else {
                return false
            }
            let stillCovering = TrainingPauseSchedule.coveringPause([pause], on: today, calendar: cal) != nil
            guard !stillCovering else {
                return false
            }
            // Only once it's actually over (planned end passed, or manually
            // resumed) — a pause with no end yet that also wasn't resumed
            // isn't over, so `stillCovering` above already excludes it.
            return true
        }
    }

    // MARK: - Start

    /// Starts a new pause. `days` is `nil` for "until I resume"; otherwise the
    /// pause covers `days` calendar days starting today (1...14 per the UI).
    /// Any OTHER still-open pause is implicitly ended as of yesterday first —
    /// only one pause is ever active at a time.
    @discardableResult
    func startPause(
        reason: PauseReason,
        otherReasonText: String? = nil,
        days: Int?,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> TrainingPause {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for open in fetchTrainingPauses(modelContext: modelContext) where open.resumedAt == nil {
            open.resumedAt = today
        }
        let program = activeTrainerProgram(modelContext: modelContext)
        let plannedEnd = days.flatMap { cal.date(byAdding: .day, value: max(1, $0) - 1, to: today) }
        let pause = TrainingPause(
            reason: reason,
            otherReasonText: reason == .other ? otherReasonText : nil,
            startDate: today,
            plannedEndDate: plannedEnd,
            createdAt: now,
            programIDAtPause: program?.id,
            scheduleModeAtPause: program?.scheduleMode
        )
        modelContext.insert(pause)
        _ = modelContext.saveOrAlert("start training pause")
        // Same regeneration trigger `promoteQueuedProgramIfDue` /
        // `TrainerProgramSaver` use so Today/Week Plan/Nutrition all
        // re-derive the week with the pause applied.
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
        HapticManager.selection()
        return pause
    }

    // MARK: - Resume

    /// Ends `pause` as of `now` and, for a FIXED-mode program, applies the
    /// chosen resume strategy. Sequence mode needs no decision: a paused day
    /// already never advanced `sequenceCursor` (`TrainingPauseSchedule.apply`
    /// runs BEFORE `applyTrainerProgram` would have consumed a step — see
    /// `assembleWeekPlans`/`generateAndPersist`), so "continue exactly where
    /// you left off" is already true with zero extra work; `decision` is
    /// ignored for it (and recorded as nil).
    func resumePause(
        _ pause: TrainingPause,
        decision: PauseResumeDecision,
        modelContext: ModelContext,
        now: Date = Date()
    ) {
        pause.resumedAt = now
        let isFixedMode = pause.scheduleModeAtPauseTyped == .fixed
        pause.resumeDecision = isFixedMode ? decision : nil

        if isFixedMode, decision == .shiftForward,
           let programID = pause.programIDAtPause,
           let program = fetchProgram(id: programID, modelContext: modelContext)
        {
            let pausedDays = TrainingPauseSchedule.pausedDayCount(pause, resumeDay: now)
            program.startDate = TrainingPauseSchedule.shiftedStartDate(
                for: program, pausedDays: pausedDays
            )
        }

        _ = modelContext.saveOrAlert("resume training pause")
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
        HapticManager.selection()
    }

    /// "Resume now" from the Today card — no fixed/sequence decision to make
    /// (sequence mode never asks; a program-less or already-past-end pause
    /// has nothing to shift either), just ends the pause immediately.
    func resumePauseNow(_ pause: TrainingPause, modelContext: ModelContext, now: Date = Date()) {
        resumePause(pause, decision: .continueFromToday, modelContext: modelContext, now: now)
    }

    private func fetchProgram(id: UUID, modelContext: ModelContext) -> TrainerProgram? {
        let descriptor = FetchDescriptor<TrainerProgram>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}
