//
// TrainerProgram.swift
// Tempo
//
// A program written by the athlete's own coach/personal trainer, imported
// from a photo, PDF or pasted text. While a program is active, its sessions
// replace the generated gym days (TrainingViewModel.applyTrainerProgram);
// Tempo still adjusts them automatically for recovery and match days.
//
// Shape: weeks → days (ISO weekday 1 = Mon … 7 = Sun) → exercises. A 1-week
// program repeats every week; a multi-week block runs week by week from
// `startDate` and then either repeats or ends (`repeats`).
//

import Foundation
import SwiftData

// MARK: - ProgramExercise

struct ProgramExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    /// As the trainer wrote it; also the fallback label.
    var name: String
    /// Library match, set on import (a custom exercise is created if none).
    var exerciseID: UUID?
    var sets: Int
    /// "8" → 8/nil, "8-10" → 8/10.
    var repsLow: Int
    var repsHigh: Int?
    /// Always stored in kg (converted from lb on import).
    var weightKg: Double?
    var rpe: Double?
    /// 0–1 (0.75 = 75% of 1RM).
    var percentOf1RM: Double?
    var restSeconds: Int?
    /// Exercises sharing a group run as a superset/circuit.
    var group: Int?
    var notes: String?

    /// Rep target for a prescribed set: the low end of a range.
    var targetReps: Int {
        max(1, repsLow)
    }
}

// MARK: - ProgramDay

struct ProgramDay: Codable, Hashable, Identifiable {
    var id = UUID()
    /// ISO weekday: 1 = Monday … 7 = Sunday.
    var weekday: Int
    var title: String?
    /// WorkoutType raw value (push/pull/legs/upper/lower/full_body) — the
    /// day's label in Tempo. Unknown → full body.
    var focus: String?
    var exercises: [ProgramExercise]
    var notes: String?

    var workoutType: WorkoutType {
        if let focus, let type = WorkoutType(rawValue: focus), type.isGymWorkout {
            return type
        }
        return .fullBody
    }
}

// MARK: - ProgramWeek

struct ProgramWeek: Codable, Hashable, Identifiable {
    var id = UUID()
    var days: [ProgramDay]
}

// MARK: - TrainerProgram

@Model
final class TrainerProgram {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var createdAt: Date
    /// Monday of program week 1.
    var startDate: Date
    var weeks: [ProgramWeek]
    /// Multi-week blocks: loop back to week 1 after the last week (true) or
    /// stop (false). A 1-week program always repeats.
    var repeats: Bool
    /// At most one program is active; the active one drives the plan.
    var isActive: Bool
    /// "photo" | "pdf" | "text".
    var sourceKind: String
    /// The text read from the source, kept for reference / re-parsing.
    var sourceText: String?

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        weeks: [ProgramWeek],
        repeats: Bool = true,
        isActive: Bool = true,
        sourceKind: String,
        sourceText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.startDate = TrainingCalendar.mondayOfWeek(containing: startDate)
        self.weeks = weeks
        self.repeats = repeats
        self.isActive = isActive
        self.sourceKind = sourceKind
        self.sourceText = sourceText
        self.createdAt = createdAt
    }

    /// Which program week applies to `date` (0-based), or nil before the
    /// start or after a non-repeating block has ended.
    func weekIndex(on date: Date) -> Int? {
        guard !weeks.isEmpty else {
            return nil
        }
        let monday = TrainingCalendar.mondayOfWeek(containing: date)
        let days = TrainingCalendar.iso8601.dateComponents([.day], from: startDate, to: monday).day ?? 0
        guard days >= 0 else {
            return nil
        }
        let index = days / 7
        if weeks.count == 1 {
            return 0
        }
        if index < weeks.count {
            return index
        }
        return repeats ? index % weeks.count : nil
    }

    /// The trainer's session for `date`, if the program schedules one.
    func session(on date: Date) -> (weekIndex: Int, day: ProgramDay)? {
        guard let index = weekIndex(on: date) else {
            return nil
        }
        let weekday = Self.isoWeekday(of: date)
        guard let day = weeks[index].days.first(where: { $0.weekday == weekday }),
              !day.exercises.isEmpty
        else {
            return nil
        }
        return (index, day)
    }

    /// True once a non-repeating block has run out of weeks.
    func isFinished(on date: Date) -> Bool {
        weekIndex(on: date) == nil && TrainingCalendar.mondayOfWeek(containing: date) >= startDate
    }

    /// Stable key stored on the generated WorkoutPlan so the day can be traced
    /// back to its program session.
    func sessionKey(weekIndex: Int, weekday: Int) -> String {
        "\(id.uuidString)#\(weekIndex)#\(weekday)"
    }

    /// Resolve a `sessionKey` back to its day (nil if this program didn't
    /// produce it or the program was edited since).
    func day(forSessionKey key: String) -> ProgramDay? {
        let parts = key.split(separator: "#")
        guard parts.count == 3, parts[0] == id.uuidString,
              let week = Int(parts[1]), let weekday = Int(parts[2]),
              weeks.indices.contains(week)
        else {
            return nil
        }
        return weeks[week].days.first { $0.weekday == weekday }
    }

    static func isoWeekday(of date: Date) -> Int {
        let weekday = TrainingCalendar.iso8601.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }
}
