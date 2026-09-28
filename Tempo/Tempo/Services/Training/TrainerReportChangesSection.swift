//
// TrainerReportChangesSection.swift
// Tempo
//
// trainer-feedback-tests — "Changes from trainer this week": folds
// `TrainerProgram.changeLog` (accepted "Trainer sent changes" batches) into
// the trainer report, as its OWN clearly separated section. Deliberately
// kept in its own file/type rather than inside `TrainerReportBuilder.swift`
// — another agent is actively editing that file (Sunday wrap-up/progress),
// so this only needs a single, clearly-marked line wired into it (see the
// `changesSection:` argument in `TrainerReportBuilder.document(rows:...)`),
// not a restructuring of it.
//

import Foundation

// MARK: - TrainerReportChangesSection

struct TrainerReportChangesSection: Sendable {
    struct Entry: Sendable, Identifiable {
        var id = UUID()
        var dateLabel: String
        var summaries: [String]
    }

    var title: String
    var entries: [Entry]
}

// MARK: - TrainerReportChangesSectionBuilder

enum TrainerReportChangesSectionBuilder {
    /// nil when `program.changeLog` has no entry dated inside `scopeRange`
    /// (the report's own week/whole-program window) — no empty section is
    /// ever shown.
    static func build(
        program: TrainerProgram,
        scopeRange: ClosedRange<Date>,
        language: TrainerReportLanguage
    ) -> TrainerReportChangesSection? {
        let cal = Calendar.current
        let matching = program.changeLog
            .filter { entry in
                let day = cal.startOfDay(for: entry.date)
                return day >= scopeRange.lowerBound && day <= scopeRange.upperBound
            }
            .sorted { $0.date < $1.date }
        guard !matching.isEmpty else {
            return nil
        }
        let title = language == .italian ? "Modifiche dal trainer questa settimana" : "Changes from trainer this week"
        let entries = matching.map {
            Entry(dateLabel: formatDate($0.date, language: language), summaries: $0.editSummaries)
        }
        return TrainerReportChangesSection(title: title, entries: entries)
    }

    private static func formatDate(_ date: Date, language: TrainerReportLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .italian ? "it_IT" : "en_US")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    private typealias Entry = TrainerReportChangesSection.Entry
}
