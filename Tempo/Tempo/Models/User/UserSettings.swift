//
// UserSettings.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - UserSettings

@Model
final class UserSettings {
    @Attribute(.unique)
    var id: UUID

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var userProfile: UserProfile?

    // MARK: - Notification Preferences

    var notificationIntensity: Int

    var morningBriefingEnabled: Bool
    var accountabilityEnabled: Bool
    var recoveryEnabled: Bool
    var mealRemindersEnabled: Bool
    var bedtimeReminderEnabled: Bool
    var streakWarningEnabled: Bool
    var arenaNotificationsEnabled: Bool
    var weeklyReportEnabled: Bool
    var trainingReminderEnabled: Bool
    var soundEnabled: Bool
    var quietHoursEnabled: Bool
    var quietHoursStartMinutes: Int
    var quietHoursEndMinutes: Int

    // MARK: - Training

    var trainingSplitRaw: String

    var weightUnitRaw: String

    var autoStartRestTimer: Bool

    /// Global default rest between sets, in seconds. Applies to every exercise
    /// unless it has a per-exercise `preferredRestSeconds` override. The inline
    /// default keeps SwiftData lightweight-migration happy for existing stores
    /// (the field was added after users already had a UserSettings row).
    var defaultRestSeconds: Int = 120

    var showPlateCalculator: Bool

    var autoDeload: Bool

    var deloadFrequencyWeeks: Int

    var footballDaysRaw: Int

    /// Advanced custom split — a user-assigned WorkoutType for each weekday,
    /// Mon-first (index 0 = Monday), JSON-encoded (array of length 7). Nil until
    /// the user configures a custom split (the engine falls back to the default
    /// sequence). Optional Data? is SwiftData-migration-safe for existing rows.
    var customWeekdayPlanJSON: Data?

    // MARK: - Schedule

    var leisureTimeMinutes: Int

    var wakeTimeMinutes: Int

    var bedtimeTargetMinutes: Int

    // MARK: - Focus Timer

    var focusTimerEnabled: Bool

    var pomodoroDuration: Int

    var breakDuration: Int

    var longBreakDuration: Int

    // MARK: - Arena

    var dailyXPGoalRaw: Int

    var leagueRaw: String

    // MARK: - Modes

    var weekendMode: Bool

    var examMode: Bool

    var examModeEndDate: Date?

    // MARK: - Coach (v2.1)

    /// True once the user has completed the Coach interview OR explicitly
    /// skipped after answering at least one question. False on first open.
    var coachInterviewCompleted: Bool = false

    /// True only if the user tapped "Skip rest" before answering ANY
    /// question. Partial completions set `coachInterviewCompleted` instead
    /// — partial priors are still useful.
    var coachInterviewSkipped: Bool = false

    /// When the user finished (or skipped from) the interview. Used by the
    /// "Re-do Coach interview" affordance to show how stale the priors are.
    var coachInterviewCompletedAt: Date?

    /// Mic mode for Coach chat input. "tapToggle" (default) or "holdToRecord".
    /// Per Coach v2.1 plan Q2 decision.
    var coachVoiceModeRaw: String = "tapToggle"

    // MARK: - Grocery preferences (persisted across regens)

    /// Weekly grocery budget cap in USD. Nil = no cap. Persisted here
    /// (not on the in-memory MealPlanIntake struct) so the user doesn't
    /// have to re-enter their budget every regen. Read by the wizard's
    /// GroceryIntentStepView at onAppear; written back on advance.
    var groceryBudgetCapUSD: Int?

    /// CSV of preferred grocery store names ("Publix, Trader Joe's").
    /// Stored raw to keep the schema flat — the @Transient
    /// `groceryPreferredStores: [String]` accessor below splits + joins.
    /// Same lifecycle reasoning as groceryBudgetCapUSD.
    var groceryPreferredStoresRaw: String = ""

    // MARK: - Meal-plan intake (persisted across regens)

    /// The user's meal-plan preferences, persisted so EVERY generate path
    /// reuses them — not just the one-shot wizard. Before this, 4 of 5
    /// generate buttons (incl. "Regenerate Plan") passed no intake and fell
    /// back to defaults; only grocery prefs above persisted. All optional /
    /// defaulted → additive migration; nil means "never set, use the engine
    /// default". Read via `MealPlanIntake.loadPersisted(from:)`.

    /// Cookable days this week (1–7). Nil → MealPlanIntake.default (4).
    var mealIntakeCookableDays: Int?

    /// `LeftoverTolerance.rawValue`. Nil → default (twoToThreeDayBatches).
    var mealIntakeLeftoverToleranceRaw: String?

    /// Eating-window bounds (hour 0–23). Nil → default (8…20).
    var mealIntakeFirstMealHour: Int?
    var mealIntakeLastMealHour: Int?

    /// Whether the plan skews macros to training-day fuel / lighter rest days.
    var mealIntakeRecoveryAdjusted: Bool = false

    /// CSV of foods off-limits — PERSISTED (the user manages them from the AI
    /// Meals settings page; not auto-cleared each week).
    var mealIntakeExclusionsRaw: String = ""

    /// How many meals the user WANTS per day (3/4/5). Nil → let the AI decide
    /// (the current 4-5 default). Drives the meal-count directive.
    var mealsPerDayPreference: Int?

    /// Cooking-time budget in minutes — weekday vs weekend. Nil → no cap (AI
    /// uses its under-20-min weekday default). Drives recipe complexity.
    var cookTimeWeekdayMins: Int?
    var cookTimeWeekendMins: Int?

    // MARK: - Timestamps

    var updatedAt: Date

    // MARK: - Computed

    @Transient
    var trainingSplit: TrainingSplit {
        get { TrainingSplit(rawValue: trainingSplitRaw) ?? .pushPullLegs }
        set { trainingSplitRaw = newValue.rawValue }
    }

    @Transient
    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
        set { weightUnitRaw = newValue.rawValue }
    }

    @Transient
    var footballDays: ActiveDays {
        get { ActiveDays(rawValue: footballDaysRaw) }
        set { footballDaysRaw = newValue.rawValue }
    }

    /// Decoded custom weekday split (Mon-first, length 7). Nil/invalid → nil, so
    /// the engine falls back to the default sequence.
    @Transient
    var customWeekdayPlan: [WorkoutType]? {
        get {
            guard let data = customWeekdayPlanJSON,
                  let arr = try? JSONDecoder().decode([WorkoutType].self, from: data),
                  arr.count == 7 else { return nil }
            return arr
        }
        set {
            if let arr = newValue, arr.count == 7 {
                customWeekdayPlanJSON = try? JSONEncoder().encode(arr)
            } else {
                customWeekdayPlanJSON = nil
            }
        }
    }

    @Transient
    var dailyXPGoal: DailyXPGoal {
        get { DailyXPGoal(rawValue: dailyXPGoalRaw) ?? .regular }
        set { dailyXPGoalRaw = newValue.rawValue }
    }

    @Transient
    var league: League {
        get { League(rawValue: leagueRaw) ?? .bronze }
        set { leagueRaw = newValue.rawValue }
    }

    @Transient
    var leisureTime: DateComponents {
        DateComponents(hour: leisureTimeMinutes / 60, minute: leisureTimeMinutes % 60)
    }

    @Transient
    var wakeTime: DateComponents {
        DateComponents(hour: wakeTimeMinutes / 60, minute: wakeTimeMinutes % 60)
    }

    @Transient
    var bedtimeTarget: DateComponents {
        DateComponents(hour: bedtimeTargetMinutes / 60, minute: bedtimeTargetMinutes % 60)
    }

    @Transient
    var bedtimeToday: Date? {
        Calendar.current.date(from: DateComponents(
            year: Calendar.current.component(.year, from: .now),
            month: Calendar.current.component(.month, from: .now),
            day: Calendar.current.component(.day, from: .now),
            hour: bedtimeTargetMinutes / 60,
            minute: bedtimeTargetMinutes % 60
        ))
    }

    /// Coach voice mode — typed accessor over coachVoiceModeRaw.
    @Transient
    var coachVoiceMode: CoachVoiceMode {
        get { CoachVoiceMode(rawValue: coachVoiceModeRaw) ?? .tapToggle }
        set { coachVoiceModeRaw = newValue.rawValue }
    }

    /// Preferred grocery stores as a typed array. Splits/joins the raw
    /// CSV. Empty array when the user hasn't set any. Setting via this
    /// accessor trims whitespace + drops empties so a trailing comma
    /// doesn't produce a phantom store.
    @Transient
    var groceryPreferredStores: [String] {
        get {
            groceryPreferredStoresRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            groceryPreferredStoresRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        notificationIntensity: Int = 3,
        morningBriefingEnabled: Bool = true,
        accountabilityEnabled: Bool = true,
        recoveryEnabled: Bool = true,
        mealRemindersEnabled: Bool = true,
        bedtimeReminderEnabled: Bool = true,
        streakWarningEnabled: Bool = true,
        arenaNotificationsEnabled: Bool = true,
        weeklyReportEnabled: Bool = true,
        trainingReminderEnabled: Bool = true,
        soundEnabled: Bool = true,
        quietHoursEnabled: Bool = false,
        quietHoursStartMinutes: Int = 1380,
        quietHoursEndMinutes: Int = 420,
        trainingSplit: TrainingSplit = .pushPullLegs,
        weightUnit: WeightUnit = .kg,
        autoStartRestTimer: Bool = true,
        defaultRestSeconds: Int = 120,
        showPlateCalculator: Bool = true,
        autoDeload: Bool = true,
        deloadFrequencyWeeks: Int = 5,
        footballDays: ActiveDays = ActiveDays(rawValue: 0),
        leisureTimeMinutes: Int = 1170,
        wakeTimeMinutes: Int = 420,
        bedtimeTargetMinutes: Int = 1380,
        focusTimerEnabled: Bool = false,
        pomodoroDuration: Int = 25,
        breakDuration: Int = 5,
        longBreakDuration: Int = 15,
        dailyXPGoal: DailyXPGoal = .regular,
        league: League = .bronze,
        weekendMode: Bool = true,
        examMode: Bool = false,
        examModeEndDate: Date? = nil
    ) {
        self.id = id
        self.notificationIntensity = notificationIntensity
        self.morningBriefingEnabled = morningBriefingEnabled
        self.accountabilityEnabled = accountabilityEnabled
        self.recoveryEnabled = recoveryEnabled
        self.mealRemindersEnabled = mealRemindersEnabled
        self.bedtimeReminderEnabled = bedtimeReminderEnabled
        self.streakWarningEnabled = streakWarningEnabled
        self.arenaNotificationsEnabled = arenaNotificationsEnabled
        self.weeklyReportEnabled = weeklyReportEnabled
        self.trainingReminderEnabled = trainingReminderEnabled
        self.soundEnabled = soundEnabled
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = quietHoursStartMinutes
        self.quietHoursEndMinutes = quietHoursEndMinutes
        trainingSplitRaw = trainingSplit.rawValue
        weightUnitRaw = weightUnit.rawValue
        self.autoStartRestTimer = autoStartRestTimer
        self.defaultRestSeconds = defaultRestSeconds
        self.showPlateCalculator = showPlateCalculator
        self.autoDeload = autoDeload
        self.deloadFrequencyWeeks = deloadFrequencyWeeks
        footballDaysRaw = footballDays.rawValue
        self.leisureTimeMinutes = leisureTimeMinutes
        self.wakeTimeMinutes = wakeTimeMinutes
        self.bedtimeTargetMinutes = bedtimeTargetMinutes
        self.focusTimerEnabled = focusTimerEnabled
        self.pomodoroDuration = pomodoroDuration
        self.breakDuration = breakDuration
        self.longBreakDuration = longBreakDuration
        dailyXPGoalRaw = dailyXPGoal.rawValue
        leagueRaw = league.rawValue
        self.weekendMode = weekendMode
        self.examMode = examMode
        self.examModeEndDate = examModeEndDate
        updatedAt = Date()
    }
}

// MARK: - Codable DTO

extension UserSettings {
    struct DTO: Codable {
        let notification_intensity: Int
        let morning_briefing_enabled: Bool
        let accountability_enabled: Bool
        let recovery_enabled: Bool
        let meal_reminders_enabled: Bool
        let bedtime_reminder_enabled: Bool
        let streak_warning_enabled: Bool
        let arena_notifications_enabled: Bool
        let weekly_report_enabled: Bool
        let training_reminder_enabled: Bool
        let sound_enabled: Bool
        let quiet_hours_enabled: Bool
        let quiet_hours_start_minutes: Int
        let quiet_hours_end_minutes: Int
        let training_split: String
        let weight_unit: String
        let auto_start_rest_timer: Bool
        let show_plate_calculator: Bool
        let auto_deload: Bool
        let deload_frequency_weeks: Int
        let football_days: Int
        let leisure_time_minutes: Int
        let wake_time_minutes: Int
        let bedtime_target_minutes: Int
        let focus_timer_enabled: Bool
        let pomodoro_duration: Int
        let break_duration: Int
        let long_break_duration: Int
        let daily_xp_goal: Int
        let league: String
        let weekend_mode: Bool
        let exam_mode: Bool
        let exam_mode_end_date: Date?
    }

    func toDTO() -> DTO {
        DTO(
            notification_intensity: notificationIntensity,
            morning_briefing_enabled: morningBriefingEnabled,
            accountability_enabled: accountabilityEnabled,
            recovery_enabled: recoveryEnabled,
            meal_reminders_enabled: mealRemindersEnabled,
            bedtime_reminder_enabled: bedtimeReminderEnabled,
            streak_warning_enabled: streakWarningEnabled,
            arena_notifications_enabled: arenaNotificationsEnabled,
            weekly_report_enabled: weeklyReportEnabled,
            training_reminder_enabled: trainingReminderEnabled,
            sound_enabled: soundEnabled,
            quiet_hours_enabled: quietHoursEnabled,
            quiet_hours_start_minutes: quietHoursStartMinutes,
            quiet_hours_end_minutes: quietHoursEndMinutes,
            training_split: trainingSplitRaw,
            weight_unit: weightUnitRaw,
            auto_start_rest_timer: autoStartRestTimer,
            show_plate_calculator: showPlateCalculator,
            auto_deload: autoDeload,
            deload_frequency_weeks: deloadFrequencyWeeks,
            football_days: footballDaysRaw,
            leisure_time_minutes: leisureTimeMinutes,
            wake_time_minutes: wakeTimeMinutes,
            bedtime_target_minutes: bedtimeTargetMinutes,
            focus_timer_enabled: focusTimerEnabled,
            pomodoro_duration: pomodoroDuration,
            break_duration: breakDuration,
            long_break_duration: longBreakDuration,
            daily_xp_goal: dailyXPGoalRaw,
            league: leagueRaw,
            weekend_mode: weekendMode,
            exam_mode: examMode,
            exam_mode_end_date: examModeEndDate
        )
    }
}

// MARK: - Validation

extension UserSettings {
    enum ValidationError: LocalizedError {
        case invalidNotificationIntensity
        case invalidPomodoroDuration
        case invalidBreakDuration
        case invalidTimeOfDay

        var errorDescription: String? {
            switch self {
            case .invalidNotificationIntensity: "Notification intensity must be 1-4 (Gentle, Firm, Drill Sergeant, Savage)."
            case .invalidPomodoroDuration: "Pomodoro duration must be 5-120 minutes."
            case .invalidBreakDuration: "Break duration must be 1-60 minutes."
            case .invalidTimeOfDay: "Time of day must be 0-1439 (minutes from midnight)."
            }
        }
    }

    func validate() throws {
        guard (1 ... 4).contains(notificationIntensity) else {
            throw ValidationError.invalidNotificationIntensity
        }
        guard (5 ... 120).contains(pomodoroDuration) else {
            throw ValidationError.invalidPomodoroDuration
        }
        guard (1 ... 60).contains(breakDuration) else {
            throw ValidationError.invalidBreakDuration
        }
        guard (1 ... 60).contains(longBreakDuration) else {
            throw ValidationError.invalidBreakDuration
        }
        let validTimeRange = 0 ..< 1440
        guard validTimeRange.contains(leisureTimeMinutes),
              validTimeRange.contains(wakeTimeMinutes),
              validTimeRange.contains(bedtimeTargetMinutes)
        else {
            throw ValidationError.invalidTimeOfDay
        }
    }
}
