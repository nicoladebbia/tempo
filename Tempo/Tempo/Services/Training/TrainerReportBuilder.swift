//
// TrainerReportBuilder.swift
// Tempo
//
// Fix #8 — "send report to trainer". Turns a trainer program plus the
// athlete's logged sessions into ONE `TrainerReportDocument`, the single
// source of truth for both outputs (`TrainerReportTextFormatter` for
// WhatsApp, `TrainerReportPDFRenderer` for the PDF).
//
// Pure apart from its inputs (mirrors `TrainingViewModel.applyTrainerProgram`
// — nonisolated, unit-tested, no I/O of its own): every SwiftData fetch
// (plans, PRs, recovery scores, pain flags) happens in the caller
// (`TrainerReportSheet`), which hands this plain data in via
// `TrainerReportInput`.
//
// "Done / missed / moved" — a scheduled session is DONE when a plan with
// its `programSessionKey` (or `programSecondaryKey`, for a two-a-day's
// second part) is found on the SAME date; MOVED when one is found on a
// different date within the search window (see `searchRange`); MISSED when
// none is found anywhere in that window.
//
// Exercise pairing — `TrainingViewModel.populateFromTrainerProgram` builds
// one `PlannedExercise` per `ProgramExercise` in the same enumerated order,
// so the trainer's prescription (`ProgramDay.exercises[i]`) and what got
// logged (`plan.orderedExercises[i]`) are paired by INDEX, not by name.
//

import Foundation
import SwiftData

// MARK: - TrainerReportInput

/// Everything the builder needs, already fetched by the caller. Plain data
/// only — no `ModelContext`, so `build(input:language:)` stays pure.
struct TrainerReportInput {
    var program: TrainerProgram
    var scope: TrainerReportScope
    /// The strict window of scheduled dates to report on.
    var scopeRange: ClosedRange<Date>
    /// Every `WorkoutPlan` touching a wider window around `scopeRange` (see
    /// `TrainerReportBuilder.searchRange`) — wide enough to catch a session
    /// logged a few days off its scheduled date ("moved").
    var plans: [WorkoutPlan] = []
    /// PRs to attribute to a session via `PersonalRecord.workoutPlanID`.
    var personalRecords: [PersonalRecord] = []
    /// `DailyRecovery.recoveryScore` (0–100) keyed by start-of-day date.
    var recoveryScores: [Date: Double] = [:]
    /// Exercises with a pain-flagged note in the window (best-effort —
    /// "only if cheaply available", per Fix #8's brief).
    var painFlaggedExerciseIDs: Set<UUID> = []
    /// Logged conditioning results, keyed by session — see `ConditioningLine`.
    var conditioningProvider: ConditioningResultProviding = EmptyConditioningResultProvider()
}

// MARK: - TrainerReportBuilder

enum TrainerReportBuilder {
    // MARK: Scope resolution

    /// The strict window of scheduled dates for `scope`, always clamped so
    /// it never runs past `today` — a report only covers what's already
    /// happened (or should have), never the rest of the week.
    static func scheduleRange(
        for scope: TrainerReportScope,
        program: TrainerProgram,
        today: Date = Date()
    ) -> ClosedRange<Date> {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        switch scope {
        case .week:
            let monday = TrainingCalendar.mondayOfWeek(containing: today)
            let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? monday
            let end = min(sunday, startOfToday)
            let start = min(monday, end)
            return start ... end
        case .wholeProgram:
            let start = min(cal.startOfDay(for: program.startDate), startOfToday)
            return start ... startOfToday
        }
    }

    /// A padded window around `scopeRange` to search for a "moved" match —
    /// a session logged up to a week off its scheduled date still counts as
    /// moved rather than missed-and-separately-logged.
    static func searchRange(around scopeRange: ClosedRange<Date>) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: scopeRange.lowerBound) ?? scopeRange.lowerBound
        let end = cal.date(byAdding: .day, value: 7, to: scopeRange.upperBound) ?? scopeRange.upperBound
        return start ... end
    }

    // MARK: Language detection

    /// Italian if the program's own source text reads Italian, else the
    /// device language, else English.
    static func detectLanguage(
        program: TrainerProgram,
        deviceLanguageCode: String? = Locale.current.language.languageCode?.identifier
    ) -> TrainerReportLanguage {
        if let sourceText = program.sourceText, looksItalian(sourceText) {
            return .italian
        }
        return deviceLanguageCode == "it" ? .italian : .english
    }

    private static let italianMarkers = [
        "serie", "ripetizioni", "recupero", "carico", "gambe", "petto", "schiena",
        "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica",
        "settimana", "riscaldamento", "panca", "stacco", "allenamento", "minuti",
    ]
    private static let englishMarkers = [
        "sets", "reps", "rest", "week", "monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday", "warm-up", "warmup", "workout", "bench",
    ]

    private static func looksItalian(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let itScore = italianMarkers.reduce(0) { $0 + (lowered.contains($1) ? 1 : 0) }
        let enScore = englishMarkers.reduce(0) { $0 + (lowered.contains($1) ? 1 : 0) }
        return itScore > enScore
    }

    // MARK: Build

    nonisolated static func build(input: TrainerReportInput, language: TrainerReportLanguage) -> TrainerReportDocument {
        let strings = TrainerReportStrings.forLanguage(language)
        let program = input.program
        let cal = Calendar.current

        // Every trainer-scheduled session (main + any two-a-day secondary)
        // across the strict scope window, in date order.
        var scheduled: [(date: Date, day: ProgramDay, sessionKey: String)] = []
        var cursor = input.scopeRange.lowerBound
        while cursor <= input.scopeRange.upperBound {
            for session in program.sessions(on: cursor) {
                let key = program.sessionKey(weekIndex: session.weekIndex, dayIndex: session.dayIndex)
                scheduled.append((cursor, session.day, key))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        // sessionKey -> every plan (within the padded search window) that
        // carries it, as a main OR secondary session.
        var plansByKey: [String: [WorkoutPlan]] = [:]
        for plan in input.plans {
            if let key = plan.programSessionKey {
                plansByKey[key, default: []].append(plan)
            }
            if let key = plan.programSecondaryKey {
                plansByKey[key, default: []].append(plan)
            }
        }

        let rows = scheduled.map { item -> TrainerReportSessionRow in
            let candidates = plansByKey[item.sessionKey] ?? []
            let exactMatch = candidates.first { cal.isDate($0.date, inSameDayAs: item.date) }
            let closestOther = candidates
                .filter { !cal.isDate($0.date, inSameDayAs: item.date) }
                .min { abs($0.date.timeIntervalSince(item.date)) < abs($1.date.timeIntervalSince(item.date)) }
            let matchedPlan = exactMatch ?? closestOther

            let status: TrainerReportSessionStatus = if let plan = matchedPlan {
                exactMatch != nil ? .done : .moved(to: plan.date)
            } else {
                .missed
            }

            return buildRow(
                scheduledDate: item.date,
                day: item.day,
                sessionKey: item.sessionKey,
                status: status,
                matchedPlan: matchedPlan,
                input: input,
                strings: strings,
                language: language
            )
        }

        let summary = buildSummary(rows: rows, input: input, strings: strings)
        let summaryLines = buildSummaryLines(summary: summary, strings: strings)

        return TrainerReportDocument(
            language: language,
            scope: input.scope,
            strings: strings,
            programName: program.name,
            title: "\(strings.reportTitle) — \(program.name)",
            dateRangeLabel: "\(strings.periodLabel): \(formatRange(input.scopeRange, language: language))",
            generatedLabel: "\(strings.generatedOnLabel) \(formatDate(Date(), language: language, includeWeekday: false))",
            summary: summary,
            summaryLines: summaryLines,
            sessions: rows
        )
    }

    // MARK: Row building

    private static func buildRow(
        scheduledDate: Date,
        day: ProgramDay,
        sessionKey: String,
        status: TrainerReportSessionStatus,
        matchedPlan: WorkoutPlan?,
        input: TrainerReportInput,
        strings: TrainerReportStrings,
        language: TrainerReportLanguage
    ) -> TrainerReportSessionRow {
        let statusLabel: String = switch status {
        case .done: strings.statusDone
        case .missed: strings.statusMissed
        case let .moved(to): "\(strings.statusMovedPrefix) \(formatDate(to, language: language, includeWeekday: true))"
        }

        // A two-a-day's secondary session (almost always conditioning) shares
        // its WorkoutPlan with the day's MAIN (lift) session — `matchedPlan`
        // is the SAME object for both scheduled rows. `populateFromTrainerProgram`
        // only ever builds `PlannedExercise` rows from the plan's PRIMARY
        // `programSessionKey`, never the secondary one (see `TrainerProgram`'s
        // header doc: a conditioning session's prescription is free text, not
        // sets × reps) — so `plan.orderedExercises` here would be the MAIN
        // session's lifts, not this session's own exercises. Pairing them
        // against `day.exercises` for a non-strength day would show the
        // wrong logged data, not just missing data, so it's deliberately
        // skipped: completion, exercise pairing and PRs all key off
        // `day.isStrength` below.
        let completionFraction: Double? = matchedPlan.map { plan in
            guard day.isStrength else {
                return plan.secondaryCompleted ? 1.0 : 0.0
            }
            let working = plan.orderedExercises.flatMap { $0.sets ?? [] }.filter { !$0.isWarmup }
            guard !working.isEmpty else {
                return plan.status == .completed ? 1.0 : 0.0
            }
            return Double(working.filter(\.completed).count) / Double(working.count)
        }

        let recoveryScoreText = input.recoveryScores[Calendar.current.startOfDay(for: scheduledDate)]
            .map { "\(Int($0.rounded()))%" }

        var exerciseLines: [TrainerReportExerciseLine] = []
        var conditioningPrescriptionNotes: [String] = []
        if day.isStrength {
            let plannedExercises = matchedPlan?.orderedExercises ?? []
            exerciseLines = day.exercises.enumerated().map { index, item in
                buildExerciseLine(
                    item: item,
                    plannedEx: index < plannedExercises.count ? plannedExercises[index] : nil,
                    input: input,
                    strings: strings,
                    language: language
                )
            }
            // Anything logged beyond the trainer's written list — an exercise
            // the athlete added ad hoc — still shows up, so the report
            // reflects the full session, not just what the trainer wrote.
            if plannedExercises.count > day.exercises.count {
                for extra in plannedExercises[day.exercises.count...] {
                    exerciseLines.append(TrainerReportExerciseLine(
                        name: extra.displayName,
                        prescriptionText: "—",
                        actualText: actualText(extra, strings: strings),
                        adjustmentText: nil,
                        overrideApplied: extra.trainerOverrideApplied,
                        noteText: nil
                    ))
                }
            }
        } else {
            conditioningPrescriptionNotes = day.exercises.compactMap { item in
                let text = item.detail ?? item.name
                return text.isEmpty ? nil : text
            }
        }

        let conditioning = input.conditioningProvider.conditioningLines(forSessionKey: sessionKey, workoutPlanID: matchedPlan?.id)
            .map { TrainerReportConditioningRow(text: formatConditioningLine($0, strings: strings)) }

        // PRs are lift-based — attribute them to the strength row only, so a
        // shared two-a-day plan doesn't list the same PR twice.
        let prs: [TrainerReportPRLine] = (day.isStrength ? matchedPlan : nil).map { plan in
            input.personalRecords
                .filter { $0.workoutPlanID == plan.id }
                .map { TrainerReportPRLine(text: "\(strings.prLabel): \($0.displayName) \(formatPRValue($0))") }
        } ?? []

        var notes = conditioningPrescriptionNotes
        if let userNotes = matchedPlan?.userNotes, !userNotes.isEmpty {
            notes.append(userNotes)
        }

        return TrainerReportSessionRow(
            id: "\(sessionKey)|\(isoKey(scheduledDate))",
            scheduledDate: scheduledDate,
            dateLabel: formatDate(scheduledDate, language: language, includeWeekday: true),
            title: day.title ?? day.workoutType.displayName,
            status: status,
            statusLabel: statusLabel,
            completionFraction: completionFraction,
            recoveryScoreText: recoveryScoreText,
            exercises: exerciseLines,
            conditioning: conditioning,
            prs: prs,
            notes: notes
        )
    }

    private static func buildExerciseLine(
        item: ProgramExercise,
        plannedEx: PlannedExercise?,
        input: TrainerReportInput,
        strings: TrainerReportStrings,
        language: TrainerReportLanguage
    ) -> TrainerReportExerciseLine {
        let adjustmentText = plannedEx?.loadAdjustmentNote.map {
            "\(strings.adjustedPrefix): \(translateAdjustmentNote($0, language: language))"
        }
        var noteParts: [String] = []
        if let note = plannedEx?.programNote, !note.isEmpty {
            noteParts.append(note)
        } else if let detail = item.notes, !detail.isEmpty {
            noteParts.append(detail)
        }
        if let exerciseID = plannedEx?.exercise?.id, input.painFlaggedExerciseIDs.contains(exerciseID) {
            noteParts.append(strings.painFlagText)
        }

        return TrainerReportExerciseLine(
            name: plannedEx?.displayName ?? item.name,
            prescriptionText: prescriptionText(item, strings: strings),
            actualText: actualText(plannedEx, strings: strings),
            adjustmentText: adjustmentText,
            overrideApplied: plannedEx?.trainerOverrideApplied ?? false,
            noteText: noteParts.isEmpty ? nil : noteParts.joined(separator: " · ")
        )
    }

    // MARK: Summary

    private static func buildSummary(
        rows: [TrainerReportSessionRow],
        input: TrainerReportInput,
        strings: TrainerReportStrings
    ) -> TrainerReportSummary {
        var doneCount = 0
        var missedCount = 0
        var movedCount = 0
        for row in rows {
            switch row.status {
            case .done:
                doneCount += 1
            case .moved:
                doneCount += 1
                movedCount += 1
            case .missed:
                missedCount += 1
            }
        }
        let scheduled = rows.count
        let rate = scheduled > 0 ? Double(doneCount) / Double(scheduled) : 0
        let recoveryValues = Array(input.recoveryScores.values)
        let avgRecovery = recoveryValues.isEmpty ? nil : recoveryValues.reduce(0, +) / Double(recoveryValues.count)
        let painCount = rows.reduce(0) { total, row in
            total + row.exercises.filter { $0.noteText?.contains(strings.painFlagText) == true }.count
        }

        return TrainerReportSummary(
            scheduledCount: scheduled,
            doneCount: doneCount,
            missedCount: missedCount,
            movedCount: movedCount,
            completionRate: rate,
            averageRecoveryScore: avgRecovery,
            painNoteCount: painCount
        )
    }

    private static func buildSummaryLines(summary: TrainerReportSummary, strings: TrainerReportStrings) -> [String] {
        var lines = [
            "\(strings.completionRateLabel): \(Int((summary.completionRate * 100).rounded()))% (\(summary.doneCount)/\(summary.scheduledCount))",
        ]
        if summary.movedCount > 0 {
            lines.append("\(strings.movedLabel): \(summary.movedCount)")
        }
        if summary.missedCount > 0 {
            lines.append("\(strings.missedLabel): \(summary.missedCount)")
        }
        if let avg = summary.averageRecoveryScore {
            lines.append("\(strings.recoveryLabel): \(Int(avg.rounded()))%")
        }
        if summary.painNoteCount > 0 {
            lines.append("\(strings.painNotesLabel): \(summary.painNoteCount)")
        }
        return lines
    }

    // MARK: Formatting helpers

    private static func prescriptionText(_ item: ProgramExercise, strings: TrainerReportStrings) -> String {
        var repsText = "\(item.repsLow)"
        if let high = item.repsHigh, high != item.repsLow {
            repsText += "-\(high)"
        }
        if item.perSide == true {
            repsText += " \(strings.perSideAbbrev)"
        }
        var text = "\(item.sets)×\(repsText) \(strings.repsUnit)"
        if let weight = item.weightKg, weight > 0 {
            text += " \(strings.atLoadPrefix) \(formatKg(weight))"
        } else if let pct = item.percentOf1RM, pct > 0 {
            text += " \(strings.atLoadPrefix) \(Int((pct * 100).rounded()))\(strings.percentOfMaxSuffix)"
        }
        return text
    }

    private static func actualText(_ plannedEx: PlannedExercise?, strings: TrainerReportStrings) -> String {
        guard let plannedEx else {
            return strings.notDoneText
        }
        let working = plannedEx.orderedSets.filter { !$0.isWarmup && $0.completed }
        guard !working.isEmpty else {
            return strings.noSetsLoggedText
        }
        var text = working
            .map { "\(formatKg($0.actualWeight ?? 0))×\($0.actualReps ?? 0)" }
            .joined(separator: ", ")
        let rpes = working.compactMap(\.rpe)
        if !rpes.isEmpty {
            let avg = Double(rpes.reduce(0, +)) / Double(rpes.count)
            let avgText = avg == avg.rounded() ? "\(Int(avg))" : String(format: "%.1f", avg)
            text += " · \(strings.rpeLabel) \(avgText)"
        }
        return text
    }

    /// `PlannedExercise.loadAdjustmentNote` is always one of a small, fixed
    /// set of English fragments built by `TrainingViewModel.
    /// loadAdjustmentNote` (§4). Rather than leaking raw English into an
    /// Italian report, translate the known fragments; anything unrecognized
    /// (a future new reason) is left as-is rather than guessed at.
    private static func translateAdjustmentNote(_ note: String, language: TrainerReportLanguage) -> String {
        guard language == .italian else {
            return note
        }
        var result = note
        let fixed: [(String, String)] = [
            ("Adjusted from your trainer's target", "Adattato rispetto all'obiettivo del trainer"),
            ("Pain note — capped at last session", "Nota dolore — limitato all'ultima sessione"),
        ]
        for (english, italian) in fixed {
            result = result.replacingOccurrences(of: english, with: italian)
        }
        if let range = result.range(of: #"Recovery yellow −\d+%"#, options: .regularExpression) {
            let translated = result[range].replacingOccurrences(of: "Recovery yellow", with: "Recupero giallo")
            result.replaceSubrange(range, with: translated)
        }
        return result
    }

    private static func formatConditioningLine(_ line: ConditioningLine, strings: TrainerReportStrings) -> String {
        var parts = [line.blockLabel]
        if !line.repTimesSeconds.isEmpty {
            parts.append(line.repTimesSeconds.map(formatSeconds).joined(separator: ", "))
        }
        if let duration = line.durationSeconds {
            parts.append(formatSeconds(duration))
        }
        if let distance = line.distanceMeters {
            parts.append("\(Int(distance))m")
        }
        if let rounds = line.roundsCompleted {
            parts.append("\(rounds)×")
        }
        if let rpe = line.rpe {
            parts.append("\(strings.rpeLabel) \(rpe)")
        }
        if let notes = line.notes, !notes.isEmpty {
            parts.append(notes)
        }
        if let met = line.targetMet {
            parts.append(met ? "✓" : "✗")
        }
        return parts.joined(separator: " · ")
    }

    private static func formatPRValue(_ pr: PersonalRecord) -> String {
        if let weight = pr.contextWeightKg, let reps = pr.contextReps {
            return "\(formatKg(weight))×\(reps)"
        }
        return formatKg(pr.value)
    }

    private static func formatKg(_ kg: Double) -> String {
        if kg == kg.rounded() {
            return "\(Int(kg))kg"
        }
        return String(format: "%.1fkg", kg)
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, secs) : "\(secs)s"
    }

    private static func formatDate(_ date: Date, language: TrainerReportLanguage, includeWeekday: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .italian ? "it_IT" : "en_US")
        formatter.dateFormat = includeWeekday ? "EEE d MMM" : "d MMM yyyy"
        return formatter.string(from: date)
    }

    private static func formatRange(_ range: ClosedRange<Date>, language: TrainerReportLanguage) -> String {
        "\(formatDate(range.lowerBound, language: language, includeWeekday: false)) – \(formatDate(range.upperBound, language: language, includeWeekday: false))"
    }

    private static func isoKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = TrainingCalendar.iso8601
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - TrainerReportStrings

/// Every string the report needs, in one place per language — "get the
/// Italian right: serie, ripetizioni, carico, saltata, recupero" (Fix #8).
/// Both `TrainerReportBuilder` (labels embedded in row/summary text) and
/// the two renderers (chrome: table headers, footer) read this.
struct TrainerReportStrings: Sendable {
    let language: TrainerReportLanguage

    let reportTitle: String
    let periodLabel: String
    let generatedOnLabel: String
    let summaryTitle: String
    let completionRateLabel: String
    let missedLabel: String
    let movedLabel: String
    let recoveryLabel: String
    let painNotesLabel: String

    let statusDone: String
    let statusMissed: String
    let statusMovedPrefix: String

    let exerciseHeader: String
    let prescribedHeader: String
    let actualHeader: String
    let adjustedPrefix: String
    let overrideLabel: String
    let notDoneText: String
    let noSetsLoggedText: String
    let notesLabel: String
    let prLabel: String
    let conditioningHeader: String
    let noSessionsText: String
    let footer: String

    let perSideAbbrev: String
    let painFlagText: String
    let repsUnit: String
    let atLoadPrefix: String
    let percentOfMaxSuffix: String
    let rpeLabel: String

    static func forLanguage(_ language: TrainerReportLanguage) -> TrainerReportStrings {
        switch language {
        case .italian:
            TrainerReportStrings(
                language: .italian,
                reportTitle: "Report allenamento",
                periodLabel: "Periodo",
                generatedOnLabel: "Generato il",
                summaryTitle: "Riepilogo",
                completionRateLabel: "Aderenza",
                missedLabel: "Saltate",
                movedLabel: "Spostate",
                recoveryLabel: "Recupero medio",
                painNotesLabel: "Note di dolore",
                statusDone: "Fatta",
                statusMissed: "Saltata",
                statusMovedPrefix: "Spostata al",
                exerciseHeader: "Esercizio",
                prescribedHeader: "Previsto",
                actualHeader: "Eseguito",
                adjustedPrefix: "Adattato",
                overrideLabel: "Usato il carico del trainer",
                notDoneText: "Non eseguito",
                noSetsLoggedText: "Nessuna serie registrata",
                notesLabel: "Note",
                prLabel: "Nuovo record",
                conditioningHeader: "Condizionamento",
                noSessionsText: "Nessuna sessione in questo periodo.",
                footer: "Generato da Tempo",
                perSideAbbrev: "per lato",
                painFlagText: "dolore segnalato",
                repsUnit: "rip",
                atLoadPrefix: "@",
                percentOfMaxSuffix: "% 1RM",
                rpeLabel: "RPE"
            )
        case .english:
            TrainerReportStrings(
                language: .english,
                reportTitle: "Training report",
                periodLabel: "Period",
                generatedOnLabel: "Generated on",
                summaryTitle: "Summary",
                completionRateLabel: "Adherence",
                missedLabel: "Missed",
                movedLabel: "Moved",
                recoveryLabel: "Avg. recovery",
                painNotesLabel: "Pain notes",
                statusDone: "Done",
                statusMissed: "Missed",
                statusMovedPrefix: "Moved to",
                exerciseHeader: "Exercise",
                prescribedHeader: "Prescribed",
                actualHeader: "Actual",
                adjustedPrefix: "Adjusted",
                overrideLabel: "Used the trainer's load",
                notDoneText: "Not done",
                noSetsLoggedText: "No sets logged",
                notesLabel: "Notes",
                prLabel: "New PR",
                conditioningHeader: "Conditioning",
                noSessionsText: "No sessions in this period.",
                footer: "Generated by Tempo",
                perSideAbbrev: "per side",
                painFlagText: "pain flagged",
                repsUnit: "reps",
                atLoadPrefix: "@",
                percentOfMaxSuffix: "% 1RM",
                rpeLabel: "RPE"
            )
        }
    }
}
