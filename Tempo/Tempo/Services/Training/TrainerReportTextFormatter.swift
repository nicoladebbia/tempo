//
// TrainerReportTextFormatter.swift
// Tempo
//
// Fix #8 — renders a `TrainerReportDocument` as compact, WhatsApp-ready
// text. Reads ONLY fields the document already carries, pre-localized and
// pre-formatted by `TrainerReportBuilder` — this formatter adds no
// business logic of its own, so it can never disagree with
// `TrainerReportPDFRenderer`, which lays out the same document.
//

import Foundation

enum TrainerReportTextFormatter {
    static func text(for document: TrainerReportDocument) -> String {
        let s = document.strings
        var lines: [String] = []

        lines.append(document.title)
        lines.append(document.dateRangeLabel)
        lines.append("")
        lines.append(s.summaryTitle.uppercased())
        lines.append(contentsOf: document.summaryLines.map { "• \($0)" })

        if document.sessions.isEmpty {
            lines.append("")
            lines.append(s.noSessionsText)
        }

        for session in document.sessions {
            lines.append("")
            lines.append("——————————")
            lines.append("\(statusMark(session.status)) \(session.dateLabel) — \(session.title) (\(session.statusLabel))")
            if let recovery = session.recoveryScoreText {
                lines.append("\(s.recoveryLabel): \(recovery)")
            }
            for exercise in session.exercises {
                lines.append("• \(exercise.name): \(exercise.prescriptionText) → \(exercise.actualText)")
                if let adjustment = exercise.adjustmentText {
                    lines.append("   \(adjustment)")
                }
                if exercise.overrideApplied {
                    lines.append("   \(s.overrideLabel)")
                }
                if let note = exercise.noteText {
                    lines.append("   \(s.notesLabel): \(note)")
                }
            }
            for conditioning in session.conditioning {
                lines.append("• \(s.conditioningHeader): \(conditioning.text)")
            }
            for pr in session.prs {
                lines.append("🏆 \(pr.text)")
            }
            for note in session.notes {
                lines.append("\(s.notesLabel): \(note)")
            }
        }

        lines.append("")
        lines.append("——————————")
        lines.append("\(s.footer) · \(document.generatedLabel)")

        return lines.joined(separator: "\n")
    }

    private static func statusMark(_ status: TrainerReportSessionStatus) -> String {
        switch status {
        case .done: "✅"
        case .missed: "❌"
        case .moved: "↔️"
        }
    }
}
