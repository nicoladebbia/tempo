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
// A weekday may hold more than one session (lift + conditioning): the
// strength session becomes the day, a conditioning session its second part.
// Conditioning sessions (runs, intervals, drills) carry their prescription
// as free text in `ProgramExercise.detail` rather than sets × reps.
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
    /// Free-text prescription for anything that isn't sets × reps — a
    /// conditioning block ("35' — 2' slow / 1' fast / 30\" walk"), a timed
    /// hold, a distance. Shown verbatim.
    var detail: String?
    /// "8+8" style reps: `repsLow` is per side.
    var perSide: Bool?

    /// trainer-feedback-tests — true when this row is a max/time-trial TEST
    /// ("test 1RM", "5RM", "time trial", "test 30m", "Yo-Yo"…), detected on
    /// import by `TrainerTestDayDetector` (or inherited from `ProgramDay
    /// .isTest`) — never guessed beyond its keyword list. Drives the "TEST —
    /// work up to a max" banner in the workout (`PlannedExercise
    /// .isTestExercise`) and, for a conditioning block, whether its logged
    /// result becomes a trusted baseline (`ConditioningBlockResult
    /// .isBaselineTest`). Optional → lightweight SwiftData/Codable migration
    /// (nil on every program saved before this shipped).
    var isTest: Bool?

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
    /// WorkoutType raw value — strength (push/pull/legs/upper/lower/
    /// full_body) or conditioning (run/sprint/conditioning/pool/mobility).
    /// Unknown → full body.
    var focus: String?
    var exercises: [ProgramExercise]
    var notes: String?
    /// True when the source gave no weekday ("Day 1", "Lifting 2") and Tempo
    /// picked one — ProgramScheduler may move it around football days.
    var weekdayGuessed: Bool?

    /// trainer-feedback-tests — true when the WHOLE day is a max/time-trial
    /// test (a day titled "Test 1RM" / "5RM Week", say), detected on import
    /// by `TrainerTestDayDetector` from the day's title/notes/exercise text.
    /// Every exercise on a test day is treated as a test exercise even if it
    /// individually carries no test wording of its own (`ProgramExercise
    /// .isTest`). Optional → lightweight SwiftData/Codable migration.
    var isTest: Bool?

    var workoutType: WorkoutType {
        if let focus, let type = WorkoutType(rawValue: focus), type != .rest, type != .football {
            return type
        }
        return .fullBody
    }

    /// Lifting session (built as sets in the gym) vs conditioning (blocks).
    var isStrength: Bool {
        workoutType.isGymWorkout
    }
}

// MARK: - ProgramWeek

struct ProgramWeek: Codable, Hashable, Identifiable {
    var id = UUID()
    var days: [ProgramDay]
}

// MARK: - TrainerProgramChangeLogEntry

/// trainer-feedback-tests — one "trainer sent changes" batch: when it was
/// applied, the athlete's own source text (for reference/debugging), and a
/// short human-readable line per edit actually accepted. `TrainerProgramSaver
/// .appendChangeLogEntry` is the only writer.
struct TrainerProgramChangeLogEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var sourceText: String
    var editSummaries: [String]
}

// MARK: - TrainerProgramSkip

/// A one-off, dated skip ("skip Thursday" from a trainer message): ONE
/// occurrence of a session is dropped, the program itself is unchanged — so
/// a repeating program is back to normal the following week. `date` is the
/// start of the skipped day; `sessionKey` is the session's key (so a
/// two-a-day's other session that day still runs). Reversible by removing
/// the entry (`TrainerProgramSaver.undoSkip`).
struct TrainerProgramSkip: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var sessionKey: String
    /// "Thu Anaerobic Run: skipped — knee", for the undo list.
    var summary: String
}

// MARK: - TrainerProgramScheduleMode

/// Fix #6 — how the program maps its sessions onto calendar days.
enum TrainerProgramScheduleMode: String, Codable, CaseIterable {
    /// Today's session is whatever's pinned to today's ISO weekday
    /// (`sessions(on:)`). A missed day is simply gone — the trainer's own
    /// weekday layout is the source of truth. Default, for backward
    /// compatibility with every program saved before this mode existed.
    case fixed
    /// Sessions run in program order, decoupled from any specific weekday.
    /// "Today's session" is the next not-yet-done one in that order — a
    /// missed session is never skipped, it carries forward until it's
    /// actually done (`sequenceSession(completedCount:)`). See
    /// `TrainerProgram.sequenceSteps`/`sequenceSession` and
    /// `TrainingViewModel.applyTrainerProgram`'s `.sequence` branch for the
    /// full resolution rule, including the cadence (which calendar days can
    /// even carry a session) and the never-two-lifts-in-a-row guard.
    case sequence

    var displayName: String {
        switch self {
        case .fixed: "Fixed weekdays"
        case .sequence: "Sequence (program order)"
        }
    }

    var explanation: String {
        switch self {
        case .fixed: "Each session stays pinned to the weekday your trainer wrote it on. A missed day is skipped."
        case .sequence: "Sessions run in order. A missed one carries forward to the next training day instead of being skipped."
        }
    }
}

// MARK: - TrainerProgramCadence

/// Weekly-upload feature — how the athlete's trainer sends programs: a fresh
/// one every week (`.weekly`), or a fixed multi-week block that repeats or
/// ends (`.block`, the pre-existing behavior). Drives the duration text on
/// `TrainerProgramView`, the "New week — upload" prompt/reminders
/// (`TrainerProgramWeeklyUpload`), and how a new upload replaces the old one
/// (`TrainerProgramReviewView`).
enum TrainerProgramCadence: String, Codable, CaseIterable {
    case weekly
    case block

    var displayName: String {
        switch self {
        case .weekly: "A new program every week"
        case .block: "A block of weeks"
        }
    }

    /// Compact label for the program screen's menu row.
    var shortName: String {
        switch self {
        case .weekly: "Every week"
        case .block: "Block of weeks"
        }
    }
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

    /// §13 — whether Tempo adds its own 50%/75% ramp warm-up sets on this
    /// program's lifting days. nil defaults to true (existing behavior);
    /// off = trainer days get exactly the sets the trainer wrote, nothing
    /// more. Editable on the review screen and on `TrainerProgramView`.
    /// Optional → lightweight SwiftData migration.
    var autoWarmups: Bool?

    /// Fix #6 — nil means `.fixed` (the pre-existing behavior, and the
    /// default for every program saved before this shipped — lightweight
    /// SwiftData migration). Editable on the review screen and on
    /// `TrainerProgramView`.
    var scheduleModeRaw: String?

    /// Fix #11(b) — queue the next block: set on import when the athlete
    /// chose "starts after the current one ends" or a specific future date
    /// instead of starting now. While non-nil, this program is NOT active
    /// (`isActive` stays false) even though it's saved — `activeTrainerProgram`
    /// promotes it (flips `isActive`, archives the outgoing program, clears
    /// this field) once `Date()` reaches it. Optional → lightweight
    /// SwiftData migration.
    var queuedActivationDate: Date?

    /// When this program stopped being the active one (paused by hand, or
    /// replaced by another). Lets the history stats count the same days the
    /// active card did right up to that moment. nil on programs archived
    /// before this existed (stats fall back to the last plan date).
    /// Optional → lightweight SwiftData migration.
    var endedAt: Date?

    /// Weekly-upload feature — nil means `.block` (the pre-existing behavior,
    /// and the default for every program saved before this shipped —
    /// lightweight SwiftData migration). Editable on the review screen and on
    /// `TrainerProgramView`.
    var cadenceRaw: String?

    /// trainer-feedback-tests — "trainer sent changes" history: one entry per
    /// accepted feedback-edit batch (date, the athlete's own source text, and
    /// a short description of each edit actually applied). Shown on
    /// `TrainerProgramView` and folded into the trainer report as "Changes
    /// from trainer this week" (`TrainerReportChangesSection.swift` — a
    /// separate extension so it stays out of `TrainerReportBuilder`'s way).
    /// Defaulted → lightweight SwiftData migration (empty on every program
    /// saved before this shipped).
    var changeLog: [TrainerProgramChangeLogEntry] = []

    /// Dated one-off skips from "Trainer Sent Changes" (fixed mode only) —
    /// `sessions(on:)` drops a skipped occurrence. Defaulted → lightweight
    /// SwiftData migration (empty on every program saved before this).
    var skippedSessions: [TrainerProgramSkip] = []

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        weeks: [ProgramWeek],
        repeats: Bool = true,
        isActive: Bool = true,
        sourceKind: String,
        sourceText: String? = nil,
        autoWarmups: Bool? = nil,
        scheduleMode: TrainerProgramScheduleMode? = nil,
        queuedActivationDate: Date? = nil,
        cadence: TrainerProgramCadence? = nil,
        changeLog: [TrainerProgramChangeLogEntry] = [],
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
        self.autoWarmups = autoWarmups
        self.scheduleModeRaw = scheduleMode?.rawValue
        self.queuedActivationDate = queuedActivationDate
        self.cadenceRaw = cadence?.rawValue
        self.changeLog = changeLog
        self.createdAt = createdAt
    }

    /// `scheduleModeRaw` read with its nil-means-`.fixed` default.
    var scheduleMode: TrainerProgramScheduleMode {
        get { scheduleModeRaw.flatMap(TrainerProgramScheduleMode.init(rawValue:)) ?? .fixed }
        set { scheduleModeRaw = newValue.rawValue }
    }

    /// `cadenceRaw` read with its nil-means-`.block` default.
    var cadence: TrainerProgramCadence {
        get { cadenceRaw.flatMap(TrainerProgramCadence.init(rawValue:)) ?? .block }
        set { cadenceRaw = newValue.rawValue }
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

    /// Every session the program schedules on `date`, in program order.
    func sessions(on date: Date) -> [(weekIndex: Int, dayIndex: Int, day: ProgramDay)] {
        guard let index = weekIndex(on: date) else {
            return []
        }
        let weekday = Self.isoWeekday(of: date)
        let cal = TrainingCalendar.iso8601
        return weeks[index].days.enumerated().compactMap { dayIndex, day in
            guard day.weekday == weekday, !day.exercises.isEmpty else {
                return nil
            }
            let key = sessionKey(weekIndex: index, dayIndex: dayIndex)
            if skippedSessions.contains(where: { $0.sessionKey == key && cal.isDate($0.date, inSameDayAs: date) }) {
                return nil
            }
            return (index, dayIndex, day)
        }
    }

    /// The day's main session: its strength session if it has one, else the
    /// first session.
    func session(on date: Date) -> (weekIndex: Int, dayIndex: Int, day: ProgramDay)? {
        let all = sessions(on: date)
        return all.first { $0.day.isStrength } ?? all.first
    }

    /// True once a non-repeating block has run out of weeks.
    func isFinished(on date: Date) -> Bool {
        weekIndex(on: date) == nil && TrainingCalendar.mondayOfWeek(containing: date) >= startDate
    }

    // MARK: - Sequence mode (fix #6)

    /// One step of sequence-mode program order — a single athlete session.
    /// Same-weekday entries within a week are paired exactly like
    /// `sessions(on:)`/`session(on:)` pair them (a lift + its conditioning
    /// partner count as ONE step, main = the strength day).
    struct SequenceStep: Hashable {
        let weekIndex: Int
        let dayIndex: Int
        let secondaryDayIndex: Int?
    }

    /// Every session the program will ever run, in program order: weeks in
    /// array order, and within a week, in the order each NEW weekday is
    /// first encountered (i.e. the order the trainer's sheet listed the
    /// days in — sequence mode never reads the weekday itself as an
    /// ordering signal, only as the same-day pairing signal it already was).
    var sequenceSteps: [SequenceStep] {
        var steps: [SequenceStep] = []
        for (weekIndex, week) in weeks.enumerated() {
            var handledWeekdays = Set<Int>()
            for (dayIndex, day) in week.days.enumerated() {
                guard !day.exercises.isEmpty, !handledWeekdays.contains(day.weekday) else {
                    continue
                }
                handledWeekdays.insert(day.weekday)
                let sameWeekday = week.days.indices.filter {
                    week.days[$0].weekday == day.weekday && !week.days[$0].exercises.isEmpty
                }
                let mainIndex = sameWeekday.first { week.days[$0].isStrength } ?? dayIndex
                let secondaryIndex = sameWeekday.first { $0 != mainIndex }
                steps.append(SequenceStep(weekIndex: weekIndex, dayIndex: mainIndex, secondaryDayIndex: secondaryIndex))
            }
        }
        return steps
    }

    /// Sequence mode's session resolution: `completedCount` is how many
    /// sessions this program has ACTUALLY had marked complete so far
    /// (counted across all time, not deduped by session key — a repeating
    /// program reuses the same keys every loop, so only a raw count tells
    /// loop 2 apart from loop 1). The step at `completedCount` (wrapped by
    /// `repeats`) is next-due — a step is never skipped just because its
    /// calendar day passed, so a missed session simply stays "next" until
    /// something increments the count past it (carry-forward). nil when the
    /// program has no sessions, or every one has run and it doesn't repeat.
    func sequenceSession(completedCount: Int) -> (weekIndex: Int, dayIndex: Int, day: ProgramDay, secondaryDayIndex: Int?)? {
        let steps = sequenceSteps
        guard !steps.isEmpty else {
            return nil
        }
        // A 1-week program always repeats, exactly like `weekIndex(on:)`'s
        // own special case (see its doc comment) — `repeats` only means
        // something for a multi-week block.
        let effectiveRepeats = repeats || weeks.count == 1
        if !effectiveRepeats, completedCount >= steps.count {
            return nil
        }
        let cursor = effectiveRepeats ? completedCount % steps.count : min(completedCount, steps.count - 1)
        let step = steps[cursor]
        return (step.weekIndex, step.dayIndex, weeks[step.weekIndex].days[step.dayIndex], step.secondaryDayIndex)
    }

    /// Stable key stored on the generated WorkoutPlan so the day can be traced
    /// back to its program session. Index-based: a weekday may hold two
    /// sessions. Fix #11(a) — a saved program can now be edited in place
    /// (`TrainerProgramSaver.update`); a sets/reps/notes edit keeps the same
    /// weekIndex/dayIndex so existing keys still resolve, but reordering or
    /// removing a day shifts indices — `day(forSessionKey:)` already returns
    /// nil for a key that no longer resolves, and every caller already
    /// treats nil as "fall back to the generated workout" (never a crash).
    func sessionKey(weekIndex: Int, dayIndex: Int) -> String {
        "\(id.uuidString)#\(weekIndex)#d\(dayIndex)"
    }

    /// Resolve a `sessionKey` back to its day (nil if this program didn't
    /// produce it).
    func day(forSessionKey key: String) -> ProgramDay? {
        let parts = key.split(separator: "#")
        guard parts.count == 3, parts[0] == id.uuidString,
              let week = Int(parts[1]), weeks.indices.contains(week),
              parts[2].hasPrefix("d"), let dayIndex = Int(parts[2].dropFirst()),
              weeks[week].days.indices.contains(dayIndex)
        else {
            return nil
        }
        return weeks[week].days[dayIndex]
    }

    /// `autoWarmups` read with its nil-means-true default (§13).
    var warmupsEnabled: Bool {
        autoWarmups ?? true
    }

    static func isoWeekday(of date: Date) -> Int {
        let weekday = TrainingCalendar.iso8601.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }
}
