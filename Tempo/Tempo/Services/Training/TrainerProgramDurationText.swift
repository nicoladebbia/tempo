//
// TrainerProgramDurationText.swift
// Tempo
//
// Cadence-aware duration text for TrainerProgramView's active card and
// TrainerProgramHistoryView's rows: how long a `.block` runs (current week +
// end date, or "repeats"), or a `.weekly` program's current week + the
// standing reminder that the next one is due Sunday. Pure/testable — no view
// dependency.
//

import Foundation

// MARK: - TrainerProgramDurationText

enum TrainerProgramDurationText {
    /// TrainerProgramView's active-card duration line.
    static func summary(for program: TrainerProgram, now: Date = Date()) -> String {
        switch program.cadence {
        case .weekly:
            // Rolled forward to `now`'s own week once stale, so an overdue
            // program shows the upcoming (real) Sunday instead of freezing
            // on a date that's already passed — see TrainerProgramWeeklyUpload's header.
            let monday = TrainerProgramWeeklyUpload.effectiveWeekMonday(for: program, now: now)
            let sunday = weekEnd(of: monday)
            return "Weekly program · this week ends \(format(sunday)) · next week's upload due Sunday"
        case .block:
            if program.repeats {
                return "\(program.weeks.count)-week block · repeats"
            }
            if let currentWeek = program.weekIndex(on: now) {
                return "Week \(currentWeek + 1) of \(program.weeks.count) · ends \(format(blockEndDate(program)))"
            }
            return "This block has finished."
        }
    }

    /// TrainerProgramHistoryView's row subtitle — dates, cadence-aware.
    static func historyText(for program: TrainerProgram) -> String {
        switch program.cadence {
        case .weekly:
            let monday = TrainerProgramWeeklyUpload.servedWeekMonday(for: program)
            return "Weekly · week of \(format(monday)) – \(format(weekEnd(of: monday)))"
        case .block:
            let start = format(program.startDate)
            guard !program.repeats else {
                return "Block · started \(start)"
            }
            return "Block · \(start) – \(format(blockEndDate(program)))"
        }
    }

    /// Monday of `program`'s last week's Sunday — the end of a `.block`
    /// program that doesn't repeat.
    static func blockEndDate(_ program: TrainerProgram) -> Date {
        TrainingCalendar.iso8601.date(byAdding: .day, value: program.weeks.count * 7 - 1, to: program.startDate)
            ?? program.startDate
    }

    private static func weekEnd(of monday: Date) -> Date {
        TrainingCalendar.iso8601.date(byAdding: .day, value: 6, to: monday) ?? monday
    }

    /// Fixed `en_US_POSIX` locale — this is a literal-format label ("Sun 18
    /// Oct"), not a locale-adaptive display string, and must read the same
    /// regardless of the device's language (Nicola runs Tempo in both
    /// English and Italian).
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.calendar = TrainingCalendar.iso8601
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
