//
// UserDailyPlanProfile.swift
// Tempo
//
// Captures the 11 onboarding fields the daily time-blocked plan engine
// needs. Per docs/INTELLIGENCE_REMEDIATION_PLAN.md §8 — onboarding gap
// closure. Kept separate from `UserSettings` so the daily-plan domain
// model can evolve without rebuilding every settings migration.
//

import Foundation
import SwiftData

// MARK: - UserDailyPlanProfile

/// One row per user. Survives across sessions and feeds the daily plan
/// engine + backend AI services (training-program, study-schedule,
/// meal-timing, recovery-prescription).
@Model
final class UserDailyPlanProfile {

    @Attribute(.unique)
    var id: UUID

    // MARK: - Sleep & chronotype

    /// Target wake time, minutes from midnight. Mirrors `UserSettings.wakeTimeMinutes`
    /// but lives here so the daily plan engine has one canonical source. Range 0..<1440.
    var wakeTimeMinutes: Int

    /// Target nightly sleep duration. Spec range 6.0..10.0 hours.
    var sleepTargetHours: Double

    /// MEQ-style 5-point chronotype scale (richer than 3-way so the engine can
    /// bias study + training placement smoothly without forcing morning-or-night).
    var chronotypeRaw: String

    // MARK: - Term-bounded class schedule

    /// Class blocks are owned by exactly one profile. Cascading delete keeps
    /// the join tidy when a user wipes onboarding.
    @Relationship(deleteRule: .cascade, inverse: \ClassBlock.profile)
    var classBlocks: [ClassBlock]

    /// Fixed work shifts (part-time job, lab hours). Same lifecycle as classes.
    @Relationship(deleteRule: .cascade, inverse: \WorkBlock.profile)
    var workBlocks: [WorkBlock]

    /// Start of the academic term (inclusive). Class blocks repeat weekly
    /// between term start and term end; outside that window they don't fire.
    var termStartDate: Date?

    /// End of the academic term (inclusive). Nil means "open-ended; recur forever
    /// until the user updates the schedule".
    var termEndDate: Date?

    // MARK: - Training

    var trainingTimePreferenceRaw: String

    // MARK: - Eating window

    /// Eating window start, minutes from midnight. With a preset of
    /// `.sixteenEight` and a noon start, this would be 720 (12:00).
    var eatingWindowStartMinutes: Int

    /// Eating window end. Must be > start. Wrap-around days (e.g. user with
    /// 22:00–06:00 window) are not modelled — out of scope for v1.
    var eatingWindowEndMinutes: Int

    /// Preset that produced the current window — UI uses this to highlight the
    /// matching chip. Persisted because re-deriving from the window times is
    /// lossy when the user picks "custom".
    var eatingWindowPresetRaw: String

    var breakfastSkipped: Bool

    var postWorkoutMandatory: Bool

    // MARK: - Study

    /// Pomodoro length in minutes. 25 / 50 / 90 per spec; custom values allowed
    /// in 5..120. Mirrors `UserSettings.pomodoroDuration` for the same reason
    /// as `wakeTimeMinutes` — single source of truth for the daily plan engine.
    var studySessionLengthMinutes: Int

    // MARK: - Weekend

    var weekendDifferentialRaw: String

    // MARK: - Migration sentinel

    /// Non-nil once the legacy `OnboardingViewModel.examSchedule` free-text has
    /// been parsed (or skipped) into structured class blocks. Lets the daily
    /// plan engine know whether to prompt the user to re-enter their schedule.
    var examScheduleMigratedAt: Date?

    // MARK: - Weekly routine

    /// JSON `WeeklyRoutine` from Fuel setup (per-weekday wake / leave / back /
    /// bed, training, classes, meals out and places). nil until captured.
    var weeklyRoutineJSON: Data?

    /// Free-text extras from Fuel setup that a planner should know.
    var fuelSetupNotes: String?

    var updatedAt: Date

    // MARK: - Transient accessors

    @Transient
    var chronotype: Chronotype {
        get { Chronotype(rawValue: chronotypeRaw) ?? .neutral }
        set { chronotypeRaw = newValue.rawValue }
    }

    @Transient
    var trainingTimePreference: TrainingTimePreference {
        get { TrainingTimePreference(rawValue: trainingTimePreferenceRaw) ?? .anyFree }
        set { trainingTimePreferenceRaw = newValue.rawValue }
    }

    @Transient
    var eatingWindowPreset: EatingWindowPreset {
        get { EatingWindowPreset(rawValue: eatingWindowPresetRaw) ?? .twelveTwelve }
        set { eatingWindowPresetRaw = newValue.rawValue }
    }

    @Transient
    var weeklyRoutine: WeeklyRoutine? {
        get { weeklyRoutineJSON.flatMap { try? JSONDecoder().decode(WeeklyRoutine.self, from: $0) } }
        set { weeklyRoutineJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    @Transient
    var weekendDifferential: WeekendDifferential {
        get { WeekendDifferential(rawValue: weekendDifferentialRaw) ?? .sameAsWeekday }
        set { weekendDifferentialRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        wakeTimeMinutes: Int = 7 * 60,
        sleepTargetHours: Double = 8.0,
        chronotype: Chronotype = .neutral,
        classBlocks: [ClassBlock] = [],
        workBlocks: [WorkBlock] = [],
        termStartDate: Date? = nil,
        termEndDate: Date? = nil,
        trainingTimePreference: TrainingTimePreference = .anyFree,
        eatingWindowPreset: EatingWindowPreset = .twelveTwelve,
        eatingWindowStartMinutes: Int = 8 * 60,
        eatingWindowEndMinutes: Int = 20 * 60,
        breakfastSkipped: Bool = false,
        postWorkoutMandatory: Bool = true,
        studySessionLengthMinutes: Int = 50,
        weekendDifferential: WeekendDifferential = .lateWake,
        examScheduleMigratedAt: Date? = nil
    ) {
        self.id = id
        self.wakeTimeMinutes = wakeTimeMinutes
        self.sleepTargetHours = sleepTargetHours
        self.chronotypeRaw = chronotype.rawValue
        self.classBlocks = classBlocks
        self.workBlocks = workBlocks
        self.termStartDate = termStartDate
        self.termEndDate = termEndDate
        self.trainingTimePreferenceRaw = trainingTimePreference.rawValue
        self.eatingWindowPresetRaw = eatingWindowPreset.rawValue
        self.eatingWindowStartMinutes = eatingWindowStartMinutes
        self.eatingWindowEndMinutes = eatingWindowEndMinutes
        self.breakfastSkipped = breakfastSkipped
        self.postWorkoutMandatory = postWorkoutMandatory
        self.studySessionLengthMinutes = studySessionLengthMinutes
        self.weekendDifferentialRaw = weekendDifferential.rawValue
        self.examScheduleMigratedAt = examScheduleMigratedAt
        self.updatedAt = Date()
    }
}

// MARK: - Lookup

extension UserDailyPlanProfile {
    /// The user's profile — the most recently updated row. Onboarding upserts
    /// a single row, but older builds could insert duplicates, so readers
    /// should use this instead of an unordered `fetch(...).first`.
    /// Nil when onboarding predates the daily-plan steps.
    static func current(in context: ModelContext) -> UserDailyPlanProfile? {
        var descriptor = FetchDescriptor<UserDailyPlanProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

// MARK: - ClassBlock

/// A weekly-recurring class. Recurrence is bounded by the parent profile's
/// `termStartDate` and `termEndDate`.
@Model
final class ClassBlock {
    @Attribute(.unique)
    var id: UUID

    /// 1 = Sunday … 7 = Saturday (matches `Calendar.Weekday` raw values).
    var weekday: Int

    var startMinuteOfDay: Int
    var endMinuteOfDay: Int

    var courseCode: String
    var courseName: String?
    var location: String?

    @Relationship(deleteRule: .nullify)
    var profile: UserDailyPlanProfile?

    init(
        id: UUID = UUID(),
        weekday: Int,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        courseCode: String,
        courseName: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.weekday = weekday
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.courseCode = courseCode
        self.courseName = courseName
        self.location = location
    }
}

// MARK: - WorkBlock

@Model
final class WorkBlock {
    @Attribute(.unique)
    var id: UUID

    var weekday: Int
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int

    var label: String

    @Relationship(deleteRule: .nullify)
    var profile: UserDailyPlanProfile?

    init(
        id: UUID = UUID(),
        weekday: Int,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        label: String = "Work"
    ) {
        self.id = id
        self.weekday = weekday
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.label = label
    }
}

// MARK: - Enums

enum Chronotype: String, CaseIterable, Codable {
    case definitelyMorning = "definitely_morning"
    case moderatelyMorning = "moderately_morning"
    case neutral
    case moderatelyEvening = "moderately_evening"
    case definitelyEvening = "definitely_evening"

    var label: String {
        switch self {
        case .definitelyMorning: "Definitely a morning person"
        case .moderatelyMorning: "Morning-leaning"
        case .neutral: "Neither"
        case .moderatelyEvening: "Evening-leaning"
        case .definitelyEvening: "Definitely a night owl"
        }
    }
}

enum TrainingTimePreference: String, CaseIterable, Codable {
    case morning
    case midday
    case evening
    case anyFree = "any_free"

    var label: String {
        switch self {
        case .morning: "Morning"
        case .midday: "Midday"
        case .evening: "Evening"
        case .anyFree: "Any free slot"
        }
    }
}

enum EatingWindowPreset: String, CaseIterable, Codable {
    case sixteenEight = "16_8"     // 16h fast / 8h eating
    case fourteenTen = "14_10"
    case twelveTwelve = "12_12"
    case custom

    var label: String {
        switch self {
        case .sixteenEight: "16:8 (16h fast)"
        case .fourteenTen: "14:10"
        case .twelveTwelve: "12:12 (no restriction)"
        case .custom: "Custom"
        }
    }

    /// Returns the default (start, end) window in minutes-from-midnight for
    /// the preset, anchored around a reasonable wake time. `.custom` returns
    /// nil so callers know to keep the existing user-edited window.
    var defaultWindow: (start: Int, end: Int)? {
        switch self {
        case .sixteenEight: (12 * 60, 20 * 60)
        case .fourteenTen: (10 * 60, 20 * 60)
        case .twelveTwelve: (8 * 60, 20 * 60)
        case .custom: nil
        }
    }
}

enum WeekendDifferential: String, CaseIterable, Codable {
    case sameAsWeekday = "same_as_weekday"
    case lateWake = "late_wake"
    case fullOff = "full_off"

    var label: String {
        switch self {
        case .sameAsWeekday: "Same as weekdays"
        case .lateWake: "Late wake, looser schedule"
        case .fullOff: "Full rest day"
        }
    }
}

// MARK: - Wire DTO

extension UserDailyPlanProfile {
    struct DTO: Codable {
        let wake_time_minutes: Int
        let sleep_target_hours: Double
        let chronotype: String
        let training_time_preference: String
        let eating_window_preset: String
        let eating_window_start_minutes: Int
        let eating_window_end_minutes: Int
        let breakfast_skipped: Bool
        let post_workout_mandatory: Bool
        let study_session_length_minutes: Int
        let weekend_differential: String
        let term_start_date: Date?
        let term_end_date: Date?
        let class_blocks: [ClassBlockDTO]
        let work_blocks: [WorkBlockDTO]
    }

    struct ClassBlockDTO: Codable {
        let weekday: Int
        let start_minute_of_day: Int
        let end_minute_of_day: Int
        let course_code: String
        let course_name: String?
        let location: String?
    }

    struct WorkBlockDTO: Codable {
        let weekday: Int
        let start_minute_of_day: Int
        let end_minute_of_day: Int
        let label: String
    }

    func toDTO() -> DTO {
        DTO(
            wake_time_minutes: wakeTimeMinutes,
            sleep_target_hours: sleepTargetHours,
            chronotype: chronotypeRaw,
            training_time_preference: trainingTimePreferenceRaw,
            eating_window_preset: eatingWindowPresetRaw,
            eating_window_start_minutes: eatingWindowStartMinutes,
            eating_window_end_minutes: eatingWindowEndMinutes,
            breakfast_skipped: breakfastSkipped,
            post_workout_mandatory: postWorkoutMandatory,
            study_session_length_minutes: studySessionLengthMinutes,
            weekend_differential: weekendDifferentialRaw,
            term_start_date: termStartDate,
            term_end_date: termEndDate,
            class_blocks: classBlocks.map {
                ClassBlockDTO(
                    weekday: $0.weekday,
                    start_minute_of_day: $0.startMinuteOfDay,
                    end_minute_of_day: $0.endMinuteOfDay,
                    course_code: $0.courseCode,
                    course_name: $0.courseName,
                    location: $0.location
                )
            },
            work_blocks: workBlocks.map {
                WorkBlockDTO(
                    weekday: $0.weekday,
                    start_minute_of_day: $0.startMinuteOfDay,
                    end_minute_of_day: $0.endMinuteOfDay,
                    label: $0.label
                )
            }
        )
    }
}
