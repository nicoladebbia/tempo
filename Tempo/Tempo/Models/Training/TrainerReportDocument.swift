//
// TrainerReportDocument.swift
// Tempo
//
// Fix #8 — "send report to trainer". Pure, plain-data output of
// `TrainerReportBuilder`: every string here is already localized/formatted
// (see `TrainerReportStrings`), so `TrainerReportTextFormatter` (WhatsApp
// text) and `TrainerReportPDFRenderer` (PDF) both just lay this document
// out — neither adds business logic of its own, so the two outputs can
// never disagree about what happened in a session.
//

import Foundation

// MARK: - TrainerReportLanguage

enum TrainerReportLanguage: String, CaseIterable, Identifiable, Sendable {
    case italian = "it"
    case english = "en"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .italian: "Italiano"
        case .english: "English"
        }
    }
}

// MARK: - TrainerReportScope

/// A week (the current program week, or the last 7 days if the program
/// isn't currently mid-week) or the whole program to date.
enum TrainerReportScope: String, CaseIterable, Identifiable, Sendable {
    case week
    case wholeProgram

    var id: String {
        rawValue
    }
}

// MARK: - TrainerReportSessionStatus

enum TrainerReportSessionStatus: Equatable, Sendable {
    /// Logged on (or matched to) its scheduled date.
    case done
    /// No matching logged session found anywhere in the search window.
    case missed
    /// Logged, but on a different date than the trainer scheduled it.
    case moved(to: Date)
}

// MARK: - TrainerReportExerciseLine

struct TrainerReportExerciseLine: Identifiable, Sendable {
    var id: UUID = .init()
    var name: String
    /// The trainer's own prescription — "3×8 reps @ 80kg" style.
    var prescriptionText: String
    /// What was actually logged — "80kg×8, 80kg×8, 82.5kg×6 · RPE 8" style,
    /// or a localized "not done" / "no sets logged" line.
    var actualText: String
    /// Non-nil only when Tempo changed the trainer's own number, with why.
    var adjustmentText: String?
    /// True once the athlete tapped "use trainer's weight" to override
    /// Tempo's adjustment back to the trainer's own number.
    var overrideApplied: Bool
    /// Trainer's exercise note and/or a pain flag, already localized.
    var noteText: String?
}

// MARK: - TrainerReportPRLine

struct TrainerReportPRLine: Identifiable, Sendable {
    var id: UUID = .init()
    var text: String
}

// MARK: - TrainerReportConditioningRow

struct TrainerReportConditioningRow: Identifiable, Sendable {
    var id: UUID = .init()
    var text: String
}

// MARK: - TrainerReportSessionRow

struct TrainerReportSessionRow: Identifiable, Sendable {
    var id: String
    var scheduledDate: Date
    var dateLabel: String
    var title: String
    var status: TrainerReportSessionStatus
    var statusLabel: String
    /// Fraction of working sets completed (0...1), nil when nothing was
    /// logged at all (a `.missed` session).
    var completionFraction: Double?
    var recoveryScoreText: String?
    var exercises: [TrainerReportExerciseLine]
    var conditioning: [TrainerReportConditioningRow]
    var prs: [TrainerReportPRLine]
    var notes: [String]
}

// MARK: - TrainerReportSummary

struct TrainerReportSummary: Sendable {
    var scheduledCount: Int
    var doneCount: Int
    var missedCount: Int
    var movedCount: Int
    /// doneCount / scheduledCount, 0 when nothing was scheduled.
    var completionRate: Double
    var averageRecoveryScore: Double?
    var painNoteCount: Int
}

// MARK: - TrainerReportDocument

/// The single, pure output of `TrainerReportBuilder.build(input:language:)`.
/// Both `TrainerReportTextFormatter` and `TrainerReportPDFRenderer` render
/// this and only this — see the file header.
struct TrainerReportDocument: Sendable {
    var language: TrainerReportLanguage
    var scope: TrainerReportScope
    var strings: TrainerReportStrings
    var programName: String
    var title: String
    var dateRangeLabel: String
    var generatedLabel: String
    var summary: TrainerReportSummary
    /// Ready-made, localized bullet lines summarizing `summary` — used
    /// verbatim by the text formatter and the PDF's summary box.
    var summaryLines: [String]
    var sessions: [TrainerReportSessionRow]
}
