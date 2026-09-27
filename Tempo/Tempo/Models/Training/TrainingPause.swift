//
// TrainingPause.swift
// Tempo
//
// "I'm sick / taking a break" — a date-ranged pause on ALL training (not just
// the trainer program): while one is active, `TrainingPauseSchedule.apply`
// forces every covered day to `.rest` in the SAME place `applyTrainerProgram`
// already overlays match days (`TrainingViewModel.assembleWeekPlans` /
// `TrainingViewModel+PlanResolution.generateAndPersist`), so every reader of
// `WorkoutPlan` — Nutrition (`TrainingScheduleProvider` -> `WeeklyTrainingSchedule
// .build`), the trainer-session reminder scheduler, the missed-session card
// and the weekly-upload nudge — sees the pause for free, without each of
// them having to know this model exists. See `TrainingPauseSchedule.swift`.
//
// Reason + day count OR "until I resume" (`plannedEndDate == nil`). Resuming
// (`TrainingViewModel+Pause.resumePause`) stamps `resumedAt` and, for a
// FIXED-mode trainer program, records which of the two offered strategies the
// athlete picked (`resumeDecisionRaw`) — sequence mode never needs to ask
// (see that file's header for why).
//
// All-additive schema, following the project's single-V1-schema rule (see
// `Match.swift`, `UserSettings.swift`): a brand-new @Model type is itself an
// additive change (SwiftData lightweight-migrates a new entity with no
// existing rows to reconcile).
//

import Foundation
import SwiftData

// MARK: - PauseReason

enum PauseReason: String, Codable, CaseIterable, Sendable {
    case sick
    case injured
    case travel
    case other

    var displayName: String {
        switch self {
        case .sick: "Sick"
        case .injured: "Injured"
        case .travel: "Travel"
        case .other: "Other"
        }
    }

    /// Short label used in the trainer report ("Sick Tue–Thu") — see
    /// `TrainerReportSupplementalSections.swift`.
    var reportLabel: String {
        displayName
    }
}

// MARK: - PauseResumeDecision

/// Fixed-mode-only choice, recorded at resume time (§ header). Sequence mode
/// and a program-less pause never set this — nil forever for them.
enum PauseResumeDecision: String, Codable, CaseIterable, Sendable {
    /// Push the fixed-mode program's `startDate` forward by the number of
    /// paused calendar days, so the week you were IN when you paused keeps
    /// applying right after you resume (multi-week blocks only — see
    /// `TrainingPauseSchedule.shiftedStartDate(for:pausedDays:)`).
    case shiftForward
    /// No-op: today's ISO weekday resolves normally, exactly as if the
    /// paused days had simply been missed.
    case continueFromToday
}

// MARK: - TrainingPause

@Model
final class TrainingPause {
    @Attribute(.unique)
    var id: UUID

    var reasonRaw: String
    /// Free text only when `reasonRaw == "other"`.
    var otherReasonText: String?

    /// Start-of-day, inclusive.
    var startDate: Date
    /// Start-of-day, inclusive. nil = "until I resume" (open-ended).
    var plannedEndDate: Date?

    var createdAt: Date

    /// Set the moment the athlete taps "Resume now" (or the app auto-detects
    /// the planned end has passed and offers the resume decision — see
    /// `TrainingViewModel+Pause.resumePause`). While nil, this pause is still
    /// (potentially) in effect for `TrainingPauseSchedule.coveringPause`.
    var resumedAt: Date?

    /// Fixed-mode resume strategy (§ header). nil until resolved, and stays
    /// nil for sequence-mode / program-less pauses.
    var resumeDecisionRaw: String?

    /// The TrainerProgram active when this pause STARTED, if any — read at
    /// resume time to know which program (and schedule mode) the decision
    /// applies to, even if a different program becomes active later.
    var programIDAtPause: UUID?
    var scheduleModeAtPause: String?

    init(
        id: UUID = UUID(),
        reason: PauseReason,
        otherReasonText: String? = nil,
        startDate: Date,
        plannedEndDate: Date?,
        createdAt: Date = Date(),
        programIDAtPause: UUID? = nil,
        scheduleModeAtPause: TrainerProgramScheduleMode? = nil
    ) {
        self.id = id
        reasonRaw = reason.rawValue
        self.otherReasonText = otherReasonText
        let cal = Calendar.current
        self.startDate = cal.startOfDay(for: startDate)
        self.plannedEndDate = plannedEndDate.map { cal.startOfDay(for: $0) }
        self.createdAt = createdAt
        self.programIDAtPause = programIDAtPause
        self.scheduleModeAtPause = scheduleModeAtPause?.rawValue
    }

    // MARK: - Typed accessors

    @Transient
    var reason: PauseReason {
        get { PauseReason(rawValue: reasonRaw) ?? .other }
        set { reasonRaw = newValue.rawValue }
    }

    @Transient
    var resumeDecision: PauseResumeDecision? {
        get { resumeDecisionRaw.flatMap(PauseResumeDecision.init(rawValue:)) }
        set { resumeDecisionRaw = newValue?.rawValue }
    }

    @Transient
    var scheduleModeAtPauseTyped: TrainerProgramScheduleMode? {
        scheduleModeAtPause.flatMap(TrainerProgramScheduleMode.init(rawValue:))
    }

    /// True once the athlete explicitly ended this pause early or the resume
    /// flow ran (`resumedAt != nil`) — distinct from "the planned end date
    /// has simply passed", which `TrainingPauseSchedule.coveringPause` also
    /// treats as no-longer-covering but which leaves `resumedAt` nil (no
    /// decision needed/offered yet). `pendingResume` on
    /// `TrainingViewModel+Pause` is what surfaces "your pause ended, resume?"
    /// for a fixed-mode program.
    @Transient
    var wasManuallyResumed: Bool {
        resumedAt != nil
    }
}
