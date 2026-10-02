//
// PainReport.swift
// Tempo
//
// "This hurts" flow (pause/travel-pain feature). Distinct from the existing
// free-text pain SIGNAL (`TrainingViewModel+NoteSignals.swift` scanning
// `SetFeedback.note`/`PlannedExercise.programNote` for keywords, which caps
// loads and feeds `TrainerReportBuilder`'s existing per-exercise
// `painFlagText` chip) — this is a STRUCTURED report the athlete files in the
// moment ("This hurts" button), with a body area + 1-10 severity + the action
// Tempo took, so it can drive an immediate response (§ below) and a caution
// chip on related exercises for 7 days, and show up as its own "Pain /
// injury" section in the trainer report
// (`TrainerReportSupplementalSections.swift`). The two systems intentionally
// don't merge — see `TrainingViewModel+Pain.swift`.
//
// Severity tiers (non-medical, careful tone — no diagnosis):
// - mild (<=3): reduce load 20% for this exercise today.
// - moderate (4-6): offer a pain-free swap (same muscle, different movement)
//   or skip.
// - severe (7+): stop the exercise, suggest ending the session, recommend
//   seeing a professional.
//

import Foundation
import SwiftData

// MARK: - PainBodyArea

enum PainBodyArea: String, Codable, CaseIterable, Sendable {
    case knee
    case shoulder
    case back
    case hip
    case ankle
    case other

    var displayName: String {
        switch self {
        case .knee: "Knee"
        case .shoulder: "Shoulder"
        case .back: "Back"
        case .hip: "Hip"
        case .ankle: "Ankle"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .knee,
             .hip,
             .ankle: "figure.walk"
        case .shoulder: "figure.arms.open"
        case .back: "figure.stand"
        case .other: "bandage.fill"
        }
    }
}

// MARK: - PainSeverityTier

enum PainSeverityTier: Sendable, Equatable {
    case mild
    case moderate
    case severe

    init(severity: Int) {
        switch severity {
        case ..<4: self = .mild
        case 4 ... 6: self = .moderate
        default: self = .severe
        }
    }
}

// MARK: - PainActionTaken

/// What Tempo actually did in response — recorded on the report itself so
/// the trainer report and the athlete's own history show the real outcome,
/// not just the tier.
enum PainActionTaken: String, Codable, CaseIterable, Sendable {
    /// Mild — load cut 20% for the rest of today's sets on this exercise.
    case reducedLoad
    /// Moderate — swapped to a pain-free alternative.
    case swapped
    /// Moderate or severe — the exercise was skipped outright.
    case skipped
    /// Severe — the whole session was ended.
    case endedSession
    /// Logged with no automatic action (e.g. logged after the fact, or the
    /// athlete dismissed the offered swap/skip).
    case none

    var displayName: String {
        switch self {
        case .reducedLoad: "Load reduced 20%"
        case .swapped: "Swapped exercise"
        case .skipped: "Skipped exercise"
        case .endedSession: "Ended session"
        case .none: "Logged"
        }
    }
}

// MARK: - PainReport

@Model
final class PainReport {
    @Attribute(.unique)
    var id: UUID

    var date: Date

    var bodyAreaRaw: String
    /// 1-10, clamped on init.
    var severity: Int

    /// Denormalized — survives the exercise being deleted/nullified, same
    /// pattern as `SetFeedback.exerciseID`.
    var exerciseID: UUID?
    var exerciseNameSnapshot: String?

    /// The workout this was filed in, so deleting that workout removes the
    /// flag it produced. Nil on reports filed before this existed or outside a session.
    var workoutPlanID: UUID?

    var actionTakenRaw: String

    var note: String?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        bodyArea: PainBodyArea,
        severity: Int,
        exerciseID: UUID? = nil,
        exerciseNameSnapshot: String? = nil,
        workoutPlanID: UUID? = nil,
        actionTaken: PainActionTaken = .none,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        bodyAreaRaw = bodyArea.rawValue
        self.severity = max(1, min(10, severity))
        self.exerciseID = exerciseID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.workoutPlanID = workoutPlanID
        actionTakenRaw = actionTaken.rawValue
        self.note = note
        self.createdAt = createdAt
    }

    // MARK: - Typed accessors

    @Transient
    var bodyArea: PainBodyArea {
        get { PainBodyArea(rawValue: bodyAreaRaw) ?? .other }
        set { bodyAreaRaw = newValue.rawValue }
    }

    @Transient
    var actionTaken: PainActionTaken {
        get { PainActionTaken(rawValue: actionTakenRaw) ?? .none }
        set { actionTakenRaw = newValue.rawValue }
    }

    @Transient
    var severityTier: PainSeverityTier {
        PainSeverityTier(severity: severity)
    }
}

// MARK: - PainCaution

enum PainCaution {
    static let windowDays = 7

    /// The most recent report for `exerciseID` still inside the caution
    /// window, or nil. Used to show a caution chip on that exercise's row in
    /// a coming session (Today/active workout).
    nonisolated static func recentReport(
        for exerciseID: UUID,
        in reports: [PainReport],
        asOf now: Date = Date(),
        calendar: Calendar = .current
    ) -> PainReport? {
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) else {
            return nil
        }
        return reports
            .filter { $0.exerciseID == exerciseID && $0.date >= cutoff }
            .max { $0.date < $1.date }
    }

    /// Severity at/above which an exercise is dropped from generated sessions
    /// (moderate tier and up — the pain-free swap the report flow offers).
    static let excludeSeverity = 4

    /// Highest severity per exercise across reports still inside the caution
    /// window. Reports without an exercise (general pain) are skipped.
    nonisolated static func activeSeverities(
        in reports: [PainReport],
        asOf now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UUID: Int] {
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) else {
            return [:]
        }
        var out: [UUID: Int] = [:]
        for report in reports where report.date >= cutoff {
            guard let id = report.exerciseID else { continue }
            out[id] = max(out[id] ?? 0, report.severity)
        }
        return out
    }

    /// Weight multiplier for an exercise that is still prescribed despite an
    /// active report (mild: the -20% `filePainReport` applies on the day;
    /// moderate/severe only reach here when the movement can't be swapped out,
    /// e.g. a trainer-program slot).
    nonisolated static func loadFactor(severity: Int?) -> Double {
        guard let severity else { return 1.0 }
        switch PainSeverityTier(severity: severity) {
        case .mild: return 0.8
        case .moderate: return 0.7
        case .severe: return 0.5
        }
    }
}
