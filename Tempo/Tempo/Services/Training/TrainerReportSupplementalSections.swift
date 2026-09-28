//
// TrainerReportSupplementalSections.swift
// Tempo
//
// Pause/travel-pain feature's trainer-report additions — football, pain/
// injury, pauses, and travel swaps. NEW FILE, deliberately kept entirely
// separate from `TrainerReportBuilder.swift`/`TrainerReportStrings` (another
// agent edits that file concurrently for the Sunday wrap-up/weekly-progress
// work — see CLAUDE.md's constraints). This is a pure POST-PROCESSING step:
// `apply(to:input:language:)` takes the document `TrainerReportBuilder.build`
// already produced and returns an augmented copy —
// - relabels any `.missed` row that lands on a paused or match day (the
//   existing classification in `build()` never sees these — it only knows
//   `WorkoutPlan.programSessionKey` matches, not pauses/matches at all);
// - recomputes `summary`/`summaryLines` so a paused/match-skipped day no
//   longer counts as "missed" in the numbers (reusing `document.strings`,
//   the SAME internal-access struct `TrainerReportBuilder.buildSummaryLines`
//   itself reads — replicated here rather than calling it, since it's
//   private to that file);
// - appends new sections via `TrainerReportDocument.extraSections` (added,
//   additively, in `TrainerReportDocument.swift`): football, pain/injury,
//   pauses, and travel swaps.
//
// `TrainerReportSheet.swift` is the only caller — it gathers the raw SwiftData
// rows (pauses, matches, pain reports) and calls this right after
// `TrainerReportBuilder.build(input:language:)`.
//

import Foundation

// MARK: - TrainerReportSupplementalSections

enum TrainerReportSupplementalSections {
    struct Input {
        var pauses: [TrainingPause] = []
        var matches: [Match] = []
        /// Same `[WorkoutPlan]` the caller already fetched for
        /// `TrainerReportInput.plans` — reused here to find travel swaps
        /// (`PlannedExercise.travelSwapOriginalName`) without a second fetch.
        var plans: [WorkoutPlan] = []
        var painReports: [PainReport] = []
        var scopeRange: ClosedRange<Date>
    }

    nonisolated static func apply(
        to document: TrainerReportDocument,
        input: Input,
        language: TrainerReportLanguage
    ) -> TrainerReportDocument {
        var document = document
        let strings = PauseTravelReportStrings.forLanguage(language)
        let cal = Calendar.current

        let pauseDayKeys = Dictionary(
            input.pauses.flatMap { pause -> [(Date, TrainingPause)] in
                dayKeys(in: pause, calendar: cal).map { ($0, pause) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let matchDayKeys = Set(input.matches.map { cal.startOfDay(for: $0.kickoff) })

        var excludedFromMissed = 0
        document.sessions = document.sessions.map { row in
            var row = row
            guard row.status == .missed else {
                return row
            }
            let day = cal.startOfDay(for: row.scheduledDate)
            if let pause = pauseDayKeys[day] {
                row.statusLabel = strings.pausedRowPrefix(for: pause.reason)
                excludedFromMissed += 1
            } else if matchDayKeys.contains(day) {
                row.statusLabel = strings.skippedMatchDay
                excludedFromMissed += 1
            }
            return row
        }

        if excludedFromMissed > 0 {
            document.summary.missedCount = max(0, document.summary.missedCount - excludedFromMissed)
            let scheduled = document.summary.scheduledCount
            document.summary.completionRate = scheduled > 0
                ? Double(document.summary.doneCount) / Double(scheduled)
                : 0
            document.summaryLines = TrainerReportBuilder.buildSummaryLines(summary: document.summary, strings: document.strings)
        }

        var sections: [TrainerReportExtraSection] = []
        if let football = footballSection(input: input, strings: strings) {
            sections.append(football)
        }
        if let pauseSection = pausesSection(pauses: input.pauses, scopeRange: input.scopeRange, strings: strings) {
            sections.append(pauseSection)
        }
        if let travel = travelSwapSection(plans: input.plans, scopeRange: input.scopeRange, strings: strings) {
            sections.append(travel)
        }
        if let pain = painSection(reports: input.painReports, scopeRange: input.scopeRange, strings: strings) {
            sections.append(pain)
        }
        document.extraSections = sections
        return document
    }

    // MARK: - Row relabeling helpers

    /// Every calendar day a pause covers within a generous window (the pause
    /// itself, capped to ±60 days so an open-ended "until I resume" pause
    /// doesn't generate an unbounded key list) — used only to relabel report
    /// ROWS, never to drive live scheduling (that's `TrainingPauseSchedule`).
    private static func dayKeys(in pause: TrainingPause, calendar: Calendar) -> [Date] {
        let end = pause.plannedEndDate
            ?? pause.resumedAt.map { calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: $0)) ?? $0 }
            ?? (calendar.date(byAdding: .day, value: 60, to: pause.startDate) ?? pause.startDate)
        var keys: [Date] = []
        var cursor = pause.startDate
        while cursor <= end {
            keys.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return keys
    }

    // MARK: - Football section

    private static func footballSection(input: Input, strings: PauseTravelReportStrings) -> TrainerReportExtraSection? {
        let inScope = input.matches
            .filter { input.scopeRange.contains(Calendar.current.startOfDay(for: $0.kickoff)) }
            .sorted { $0.kickoff < $1.kickoff }
        guard !inScope.isEmpty else {
            return nil
        }
        let lines = inScope.map { match -> String in
            let dateText = match.kickoff.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            let kind = match.isCompetitive ? strings.competitiveLabel : strings.friendlyLabel
            let opponent = match.opponent.map { " \(strings.vsLabel) \($0)" } ?? ""
            return "\(dateText) — \(kind)\(opponent)"
        }
        return TrainerReportExtraSection(title: strings.footballSectionTitle, lines: lines)
    }

    // MARK: - Pauses section

    private static func pausesSection(
        pauses: [TrainingPause],
        scopeRange: ClosedRange<Date>,
        strings: PauseTravelReportStrings
    ) -> TrainerReportExtraSection? {
        let cal = Calendar.current
        let relevant = pauses.filter { pause in
            let end = pause.plannedEndDate ?? scopeRange.upperBound
            return pause.startDate <= scopeRange.upperBound && end >= scopeRange.lowerBound
        }.sorted { $0.startDate < $1.startDate }
        guard !relevant.isEmpty else {
            return nil
        }
        let lines = relevant.map { pause -> String in
            let start = max(pause.startDate, scopeRange.lowerBound)
            let end = min(pause.plannedEndDate ?? scopeRange.upperBound, scopeRange.upperBound)
            let reasonLabel = strings.reasonLabel(for: pause.reason)
            if cal.isDate(start, inSameDayAs: end) {
                return "\(reasonLabel) \(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
            }
            let startText = start.formatted(.dateTime.weekday(.abbreviated))
            let endText = end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return "\(reasonLabel) \(startText)–\(endText)"
        }
        return TrainerReportExtraSection(title: strings.pausesSectionTitle, lines: lines)
    }

    // MARK: - Travel swaps section

    private static func travelSwapSection(
        plans: [WorkoutPlan],
        scopeRange: ClosedRange<Date>,
        strings: PauseTravelReportStrings
    ) -> TrainerReportExtraSection? {
        let inScope = plans
            .filter { scopeRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .sorted { $0.date < $1.date }
        var lines: [String] = []
        for plan in inScope {
            let swapped = plan.orderedExercises.filter { $0.travelSwapOriginalName != nil }
            guard !swapped.isEmpty else {
                continue
            }
            let dateText = plan.date.formatted(.dateTime.weekday(.abbreviated))
            for exercise in swapped {
                let newName = exercise.displayName
                let originalName = exercise.travelSwapOriginalName ?? newName
                lines.append("\(dateText): \(originalName) → \(newName) (\(strings.swappedTravelSuffix))")
            }
        }
        guard !lines.isEmpty else {
            return nil
        }
        return TrainerReportExtraSection(title: strings.travelSectionTitle, lines: lines)
    }

    // MARK: - Pain section

    private static func painSection(
        reports: [PainReport],
        scopeRange: ClosedRange<Date>,
        strings: PauseTravelReportStrings
    ) -> TrainerReportExtraSection? {
        let inScope = reports
            .filter { scopeRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .sorted { $0.date < $1.date }
        guard !inScope.isEmpty else {
            return nil
        }
        let lines = inScope.map { report -> String in
            let dateText = report.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            let exerciseText = report.exerciseNameSnapshot.map { " · \($0)" } ?? ""
            return "\(dateText): \(strings.bodyAreaLabel(for: report.bodyArea)) \(report.severity)/10\(exerciseText) — \(strings.actionLabel(for: report.actionTaken))"
        }
        return TrainerReportExtraSection(title: strings.painSectionTitle, lines: lines)
    }
}

// MARK: - PauseTravelReportStrings

/// Own IT/EN table for this feature's report additions, mirroring
/// `TrainerReportStrings`'s exact `forLanguage` pattern (see that struct's
/// doc comment) without adding a single field to it — keeps this file's diff
/// against `TrainerReportBuilder.swift` at zero.
struct PauseTravelReportStrings: Sendable {
    let language: TrainerReportLanguage
    let footballSectionTitle: String
    let painSectionTitle: String
    let pausesSectionTitle: String
    let travelSectionTitle: String
    let competitiveLabel: String
    let friendlyLabel: String
    let vsLabel: String
    let skippedMatchDay: String
    let swappedTravelSuffix: String

    static func forLanguage(_ language: TrainerReportLanguage) -> PauseTravelReportStrings {
        switch language {
        case .italian:
            PauseTravelReportStrings(
                language: .italian,
                footballSectionTitle: "Calcio",
                painSectionTitle: "Dolore / infortuni",
                pausesSectionTitle: "Pause",
                travelSectionTitle: "Adattamenti in viaggio",
                competitiveLabel: "Partita",
                friendlyLabel: "Amichevole",
                vsLabel: "vs",
                skippedMatchDay: "Saltata — giorno di partita",
                swappedTravelSuffix: "sostituito — viaggio"
            )
        case .english:
            PauseTravelReportStrings(
                language: .english,
                footballSectionTitle: "Football",
                painSectionTitle: "Pain / injury",
                pausesSectionTitle: "Pauses",
                travelSectionTitle: "Travel adjustments",
                competitiveLabel: "Match",
                friendlyLabel: "Friendly",
                vsLabel: "vs",
                skippedMatchDay: "Skipped — match day",
                swappedTravelSuffix: "swapped — travel"
            )
        }
    }

    func pausedRowPrefix(for reason: PauseReason) -> String {
        let label = reasonLabel(for: reason)
        return language == .italian ? "Saltata — \(label.lowercased())" : "Skipped — \(label.lowercased())"
    }

    func reasonLabel(for reason: PauseReason) -> String {
        let isItalian = language == .italian
        return switch (reason, isItalian) {
        case (.sick, true): "Malattia"
        case (.injured, true): "Infortunio"
        case (.travel, true): "Viaggio"
        case (.other, true): "Pausa"
        case (.sick, false): "Sick"
        case (.injured, false): "Injured"
        case (.travel, false): "Travel"
        case (.other, false): "Paused"
        }
    }

    func bodyAreaLabel(for area: PainBodyArea) -> String {
        let isItalian = language == .italian
        guard isItalian else {
            return area.displayName
        }
        return switch area {
        case .knee: "Ginocchio"
        case .shoulder: "Spalla"
        case .back: "Schiena"
        case .hip: "Anca"
        case .ankle: "Caviglia"
        case .other: "Altro"
        }
    }

    func actionLabel(for action: PainActionTaken) -> String {
        let isItalian = language == .italian
        guard isItalian else {
            return action.displayName.lowercased()
        }
        return switch action {
        case .reducedLoad: "carico ridotto 20%"
        case .swapped: "esercizio sostituito"
        case .skipped: "esercizio saltato"
        case .endedSession: "sessione interrotta"
        case .none: "registrato"
        }
    }
}
