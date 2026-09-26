//
// SundayWrapUpReportTracker.swift
// Tempo
//
// Sunday wrap-up feature — remembers "the trainer report was sent this
// week" so `SundayWrapUpSheet`'s send-report step can show a ✓ on return
// (e.g. the athlete backs out after step (a) and reopens the card later the
// same week). Deliberately a `UserDefaults` flag, not a SwiftData model —
// this is a per-device UI nicety, not training data that needs to sync or
// survive a reinstall, so it doesn't need a schema entry (see
// `TempoSchemaV1`) or a backend round-trip.
//
// Keyed by the program's id and the SERVED week it covers
// (`TrainerProgramWeeklyUpload.servedWeekMonday`) — the same anchor the rest
// of the weekly-upload feature uses, so "this week" here means the exact
// same week the Sunday/Monday reminders and `shouldPromptUpload` are talking
// about, not just whatever `now`'s calendar week happens to be.
//

import Foundation

// MARK: - SundayWrapUpReportTracker

enum SundayWrapUpReportTracker {
    static func markSent(programID: UUID, weekMonday: Date, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(programID: programID, weekMonday: weekMonday))
    }

    static func wasSent(programID: UUID, weekMonday: Date, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(programID: programID, weekMonday: weekMonday))
    }

    private static func key(programID: UUID, weekMonday: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = TrainingCalendar.iso8601
        formatter.dateFormat = "yyyy-MM-dd"
        return "wrapUpReportSent-\(programID.uuidString)-\(formatter.string(from: weekMonday))"
    }
}
