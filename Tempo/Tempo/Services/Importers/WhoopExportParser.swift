//
// WhoopExportParser.swift
// Tempo
//
// Pure parsing for the official Whoop account-data export (the 4-CSV folder:
// physiological_cycles / workouts / journal_entries / sleeps). One year of
// history seeds the training intelligence in one shot: real 30-day baselines
// (opens the brain gate), honest ACWR, instant venue/time patterns.
//
// sleeps.csv is deliberately NOT imported: physiological_cycles.csv already
// carries the per-day sleep fields the app stores; importing both would
// double-write. journal_entries.csv is OUT by Nicola's call (2026-06-09).
// Naps are out of scope (no model holds them).
//
// Everything here is pure text → value structs; SwiftData writes live in
// WhoopExportImporter so this parses under unit test with zero IO.
//

import Foundation

enum WhoopExportParser {
    // MARK: - Quote-aware CSV core

    /// Minimal RFC-4180 parser: handles quoted fields containing commas,
    /// escaped quotes ("") and newlines (journal Notes have all three).
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n": row.append(field); field = ""; rows.append(row); row = []
                case "\r": break
                default: field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// Header-keyed rows; blank lines dropped.
    static func keyedRows(_ text: String) -> [[String: String]] {
        let raw = parseCSV(text)
        guard let header = raw.first else { return [] }
        return raw.dropFirst().compactMap { fields in
            guard fields.count > 1 else { return nil }
            var dict: [String: String] = [:]
            for (i, name) in header.enumerated() where i < fields.count {
                dict[name] = fields[i]
            }
            return dict
        }
    }

    // MARK: - Value rows

    /// One day of physiological_cycles.csv, shaped for DailyRecovery's init.
    struct CycleRow: Equatable, Sendable {
        let date: Date
        let recoveryScore: Double
        let hrv: Double?
        let rhr: Double?
        let skinTemp: Double?
        let spo2: Double?
        let dayStrain: Double?
        let maxHR: Double?
        let avgHR: Double?
        let calories: Double?
        let sleepPerformancePct: Double?
        let respRate: Double?
        let sleepHours: Double?
        let deepMin: Int?
        let remMin: Int?
        let lightMin: Int?
        let awakeMin: Int?
        let sleepNeedHours: Double?
        let sleepDebtHours: Double?
        let efficiencyPct: Double?
        let consistencyPct: Double?
    }

    /// One workout of workouts.csv, shaped for ActivitySession's init.
    struct WorkoutRow: Equatable, Sendable {
        let startTime: Date
        let durationMin: Double
        let activityName: String
        /// Mapped onto WorkoutType raw values where one exists (Soccer →
        /// "football"); otherwise the lowercased Whoop name — still venue/time
        /// evidence, just without a venue inference.
        let workoutType: String
        let strain: Double?
        let calories: Double?
        let maxHR: Double?
        let avgHR: Double?
        /// Z1–Z5 minutes, derived from the export's zone percentages × duration.
        let zoneMinutes: [Double]?
    }

    // MARK: - File mappers

    static func cycles(fromCSV text: String, calendar: Calendar = .current) -> [CycleRow] {
        keyedRows(text).compactMap { r in
            guard let date = date(r["Cycle start time"], tz: r["Cycle timezone"]),
                  let recovery = double(r["Recovery score %"]) else { return nil }
            return CycleRow(
                date: calendar.startOfDay(for: date),
                recoveryScore: recovery,
                hrv: double(r["Heart rate variability (ms)"]),
                rhr: double(r["Resting heart rate (bpm)"]),
                skinTemp: double(r["Skin temp (celsius)"]),
                spo2: double(r["Blood oxygen %"]),
                dayStrain: double(r["Day Strain"]),
                maxHR: double(r["Max HR (bpm)"]),
                avgHR: double(r["Average HR (bpm)"]),
                calories: double(r["Energy burned (cal)"]),
                sleepPerformancePct: double(r["Sleep performance %"]),
                respRate: double(r["Respiratory rate (rpm)"]),
                sleepHours: double(r["Asleep duration (min)"]).map { $0 / 60 },
                deepMin: int(r["Deep (SWS) duration (min)"]),
                remMin: int(r["REM duration (min)"]),
                lightMin: int(r["Light sleep duration (min)"]),
                awakeMin: int(r["Awake duration (min)"]),
                sleepNeedHours: double(r["Sleep need (min)"]).map { $0 / 60 },
                sleepDebtHours: double(r["Sleep debt (min)"]).map { $0 / 60 },
                efficiencyPct: double(r["Sleep efficiency %"]),
                consistencyPct: double(r["Sleep consistency %"])
            )
        }
    }

    static func workouts(fromCSV text: String) -> [WorkoutRow] {
        keyedRows(text).compactMap { r in
            guard let start = date(r["Workout start time"], tz: r["Cycle timezone"]),
                  let duration = double(r["Duration (min)"]),
                  let name = r["Activity name"], !name.isEmpty else { return nil }
            let pcts = ["HR Zone 1 %", "HR Zone 2 %", "HR Zone 3 %", "HR Zone 4 %", "HR Zone 5 %"]
                .map { double(r[$0]) }
            let zones: [Double]? = pcts.allSatisfy { $0 != nil }
                ? pcts.map { ($0! / 100) * duration }
                : nil
            return WorkoutRow(
                startTime: start,
                durationMin: duration,
                activityName: name,
                workoutType: workoutTypeRaw(forActivity: name),
                strain: double(r["Activity Strain"]),
                calories: double(r["Energy burned (cal)"]),
                maxHR: double(r["Max HR (bpm)"]),
                avgHR: double(r["Average HR (bpm)"]),
                zoneMinutes: zones
            )
        }
    }

    // MARK: - Helpers

    /// Whoop activity name → WorkoutType raw value where one exists.
    static func workoutTypeRaw(forActivity name: String) -> String {
        switch name.lowercased() {
        case "soccer": "football"
        case "running": "run"
        case "swimming": "pool"
        case "weightlifting", "strength trainer", "powerlifting": "full_body"
        case "spin", "cycling", "hiit", "functional fitness": "conditioning"
        case "stretching", "yoga", "pilates": "mobility"
        default: name.lowercased()
        }
    }

    /// "2026-06-09 00:43:33" + "UTC-04:00" → Date. nil tz → current zone.
    static func date(_ value: String?, tz: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = timeZone(from: tz) ?? .current
        return formatter.date(from: value)
    }

    /// "UTC-04:00" / "UTC+05:30" → TimeZone.
    static func timeZone(from raw: String?) -> TimeZone? {
        guard let raw, raw.hasPrefix("UTC"), raw.count >= 9 else { return nil }
        let offset = raw.dropFirst(3) // "-04:00"
        let sign: Int = offset.hasPrefix("-") ? -1 : 1
        let parts = offset.dropFirst().split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
    }

    static func double(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        return Double(value)
    }

    static func int(_ value: String?) -> Int? {
        guard let value, !value.isEmpty else { return nil }
        return Double(value).map { Int($0) }
    }
}
