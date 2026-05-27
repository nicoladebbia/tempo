//
// CoachInterviewService.swift
// Tempo
//
// Coach v2.1 Phase 7.5 — interview persistence + answer schema.
//
// Pure logic. Translates a six-question answer set into:
//   • Up to 6 LearnedPreference rows (source = .userVerified, confidence = 1.0)
//   • UserSettings flags (coachInterviewCompleted / coachInterviewSkipped /
//     coachInterviewCompletedAt)
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §1 "Coach Interview View" and
// the Q3 decision (6 questions, individually skippable, partial-completion
// keeps any answered priors).
//

import Foundation
import SwiftData

// MARK: - CoachInterviewAnswers

/// Six-question payload. Every field is optional — the interview is
/// individually-skippable per the v2.1 plan §"Per-question skip semantics".
/// Skipped questions stay nil and produce no LearnedPreference row.
struct CoachInterviewAnswers: Equatable {
    /// Q1 — When you're tired, do you want me to (push / ease / askFirst)?
    var tiredMode: TiredMode?

    /// Q2 — Tone preference: drillSergeant / dataAnalyst / supportive / none.
    var tonePreference: TonePreference?

    /// Q3 — What should I track silently? Multi-select.
    var silentTrack: Set<SilentTrackOption>

    /// Q4 — A habit you've tried and failed at. Free text, optional.
    var failedHabit: String?

    /// Q5 — On a hard day, what should I NEVER suggest? Free text, optional.
    var hardDayNeverSuggest: String?

    /// Q6 — Anything weird about your schedule? Free text, optional.
    var scheduleException: String?

    init(
        tiredMode: TiredMode? = nil,
        tonePreference: TonePreference? = nil,
        silentTrack: Set<SilentTrackOption> = [],
        failedHabit: String? = nil,
        hardDayNeverSuggest: String? = nil,
        scheduleException: String? = nil
    ) {
        self.tiredMode = tiredMode
        self.tonePreference = tonePreference
        self.silentTrack = silentTrack
        self.failedHabit = failedHabit
        self.hardDayNeverSuggest = hardDayNeverSuggest
        self.scheduleException = scheduleException
    }

    /// True when at least one question received a non-empty answer.
    /// Drives the completed-vs-skipped flag on UserSettings.
    var hasAnyAnswer: Bool {
        if tiredMode != nil { return true }
        if tonePreference != nil { return true }
        if !silentTrack.isEmpty { return true }
        if let s = failedHabit, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let s = hardDayNeverSuggest, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let s = scheduleException, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }
}

// MARK: - Answer enums

enum TiredMode: String, Codable, CaseIterable, Sendable {
    case push
    case ease
    case askFirst

    var displayName: String {
        switch self {
        case .push: return "Push you anyway"
        case .ease: return "Suggest easing off"
        case .askFirst: return "Ask first"
        }
    }
}

enum TonePreference: String, Codable, CaseIterable, Sendable {
    case drillSergeant
    case dataAnalyst
    case supportive
    case noPreference

    var displayName: String {
        switch self {
        case .drillSergeant: return "Drill-sergeant"
        case .dataAnalyst: return "Data analyst"
        case .supportive: return "Supportive friend"
        case .noPreference: return "No preference"
        }
    }
}

enum SilentTrackOption: String, Codable, CaseIterable, Sendable {
    case meals
    case sleep
    case trainingIntensity
    case mood

    var displayName: String {
        switch self {
        case .meals: return "Meals"
        case .sleep: return "Sleep"
        case .trainingIntensity: return "Training intensity"
        case .mood: return "Mood"
        }
    }
}

// MARK: - CoachVoiceMode

/// Mic mode for Coach chat. Per Coach v2.1 plan Q2 decision: user-
/// configurable in Settings, default tap-to-toggle.
enum CoachVoiceMode: String, Codable, CaseIterable, Sendable {
    case tapToggle
    case holdToRecord

    var displayName: String {
        switch self {
        case .tapToggle: return "Tap to toggle"
        case .holdToRecord: return "Hold to record"
        }
    }
}

// MARK: - CoachInterviewService

enum CoachInterviewService {
    /// Persists every non-empty answer as a LearnedPreference row and
    /// updates UserSettings flags. Returns the run report — count of
    /// preferences inserted + completion state — so callers can drive UI
    /// confirmation copy.
    @MainActor
    @discardableResult
    static func persist(
        answers: CoachInterviewAnswers,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> RunReport {
        var report = RunReport()

        // Q1 — tiredMode
        if let mode = answers.tiredMode {
            let pref = LearnedPreference(
                text: tiredModeText(mode),
                subject: "tone.push_when_tired",
                source: .userVerified,
                polarity: .positive,
                scope: .always,
                lastSeenAt: now
            )
            context.insert(pref)
            report.inserted += 1
        }

        // Q2 — tonePreference (skip when noPreference — nothing useful to learn)
        if let tone = answers.tonePreference, tone != .noPreference {
            let pref = LearnedPreference(
                text: "user prefers Coach's tone to be \(tone.displayName.lowercased())",
                subject: "tone.style",
                source: .userVerified,
                polarity: .positive,
                scope: .always,
                lastSeenAt: now
            )
            context.insert(pref)
            report.inserted += 1
        }

        // Q3 — silent track (skip when empty set)
        if !answers.silentTrack.isEmpty {
            let labels = answers.silentTrack
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.displayName)
                .joined(separator: ", ")
            let pref = LearnedPreference(
                text: "user wants Coach to silently track: \(labels)",
                subject: "tone.silent_track",
                source: .userVerified,
                polarity: .positive,
                scope: .always,
                lastSeenAt: now
            )
            context.insert(pref)
            report.inserted += 1
        }

        // Q4 — failedHabit → red-line, polarity = avoidAtAllCosts
        if let raw = answers.failedHabit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            let pref = LearnedPreference(
                text: "user has tried and failed: \(raw)",
                subject: "red_lines.never_suggest",
                source: .userVerified,
                polarity: .avoidAtAllCosts,
                scope: .always,
                lastSeenAt: now
            )
            context.insert(pref)
            report.inserted += 1
        }

        // Q5 — hardDayNeverSuggest → red-line scoped to hard days
        if let raw = answers.hardDayNeverSuggest?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            let pref = LearnedPreference(
                text: "on hard days, never suggest: \(raw)",
                subject: "red_lines.never_suggest_on_hard_days",
                source: .userVerified,
                polarity: .avoidAtAllCosts,
                scope: .dayTypeHard,
                lastSeenAt: now
            )
            context.insert(pref)
            report.inserted += 1
        }

        // Q6 — schedule exceptions
        if let raw = answers.scheduleException?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            let pref = LearnedPreference(
                text: "schedule note: \(raw)",
                subject: "schedule.exceptions",
                source: .userVerified,
                polarity: .positive,
                scope: .always,
                lastSeenAt: now
            )
            context.insert(pref)
            report.inserted += 1
        }

        // UserSettings flags. Settings is a singleton row in the app —
        // create if missing so first-run paths don't lose the flags.
        let settings = fetchOrCreateSettings(in: context)
        if answers.hasAnyAnswer {
            settings.coachInterviewCompleted = true
            settings.coachInterviewSkipped = false
            report.completed = true
        } else {
            // Zero answers + explicit save = "skip rest" with no priors.
            settings.coachInterviewSkipped = true
            settings.coachInterviewCompleted = false
            report.skipped = true
        }
        settings.coachInterviewCompletedAt = now
        settings.updatedAt = now

        try context.save()
        return report
    }

    /// Re-do path. Marks the existing flag false and clears the
    /// `coachInterviewCompletedAt` timestamp so the gate re-fires. Does
    /// NOT touch existing LearnedPreference rows — the user can edit
    /// or delete them from Coach Memory UI (Phase 8). Re-running the
    /// interview will insert *new* rows alongside the old ones; the
    /// retriever's dedupe + decay logic handles the overlap.
    @MainActor
    static func resetInterview(in context: ModelContext) throws {
        let settings = fetchOrCreateSettings(in: context)
        settings.coachInterviewCompleted = false
        settings.coachInterviewSkipped = false
        settings.coachInterviewCompletedAt = nil
        settings.updatedAt = Date()
        try context.save()
    }

    // MARK: - Helpers

    @MainActor
    private static func fetchOrCreateSettings(in context: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let fresh = UserSettings()
        context.insert(fresh)
        return fresh
    }

    static func tiredModeText(_ mode: TiredMode) -> String {
        switch mode {
        case .push:
            return "when tired, user wants Coach to push them anyway"
        case .ease:
            return "when tired, user wants Coach to suggest easing off"
        case .askFirst:
            return "when tired, user wants Coach to ask before pushing or easing"
        }
    }
}

// MARK: - RunReport

extension CoachInterviewService {
    struct RunReport: Equatable {
        var inserted: Int = 0
        var completed: Bool = false
        var skipped: Bool = false
    }
}
