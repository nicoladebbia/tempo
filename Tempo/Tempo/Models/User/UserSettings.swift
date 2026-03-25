import Foundation
import SwiftData

@Model
final class UserSettings {

    @Attribute(.unique)
    var id: UUID

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var userProfile: UserProfile?

    // MARK: - Notification Preferences

    var notificationIntensity: Int

    // MARK: - Schedule

    var leisureTimeMinutes: Int

    var wakeTimeMinutes: Int

    var bedtimeTargetMinutes: Int

    // MARK: - Focus Timer

    var pomodoroDuration: Int

    var breakDuration: Int

    var longBreakDuration: Int

    // MARK: - Modes

    var weekendMode: Bool

    var examMode: Bool

    var examModeEndDate: Date?

    // MARK: - Timestamps

    var updatedAt: Date

    // MARK: - Computed

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

    // MARK: - Init

    init(
        id: UUID = UUID(),
        notificationIntensity: Int = 3,
        leisureTimeMinutes: Int = 1170,
        wakeTimeMinutes: Int = 420,
        bedtimeTargetMinutes: Int = 1380,
        pomodoroDuration: Int = 25,
        breakDuration: Int = 5,
        longBreakDuration: Int = 15,
        weekendMode: Bool = true,
        examMode: Bool = false,
        examModeEndDate: Date? = nil
    ) {
        self.id = id
        self.notificationIntensity = notificationIntensity
        self.leisureTimeMinutes = leisureTimeMinutes
        self.wakeTimeMinutes = wakeTimeMinutes
        self.bedtimeTargetMinutes = bedtimeTargetMinutes
        self.pomodoroDuration = pomodoroDuration
        self.breakDuration = breakDuration
        self.longBreakDuration = longBreakDuration
        self.weekendMode = weekendMode
        self.examMode = examMode
        self.examModeEndDate = examModeEndDate
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO

extension UserSettings {

    struct DTO: Codable, Sendable {
        let notification_intensity: Int
        let leisure_time_minutes: Int
        let wake_time_minutes: Int
        let bedtime_target_minutes: Int
        let pomodoro_duration: Int
        let break_duration: Int
        let long_break_duration: Int
        let weekend_mode: Bool
        let exam_mode: Bool
        let exam_mode_end_date: Date?
    }

    func toDTO() -> DTO {
        DTO(
            notification_intensity: notificationIntensity,
            leisure_time_minutes: leisureTimeMinutes,
            wake_time_minutes: wakeTimeMinutes,
            bedtime_target_minutes: bedtimeTargetMinutes,
            pomodoro_duration: pomodoroDuration,
            break_duration: breakDuration,
            long_break_duration: longBreakDuration,
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
        guard (1...4).contains(notificationIntensity) else {
            throw ValidationError.invalidNotificationIntensity
        }
        guard (5...120).contains(pomodoroDuration) else {
            throw ValidationError.invalidPomodoroDuration
        }
        guard (1...60).contains(breakDuration) else {
            throw ValidationError.invalidBreakDuration
        }
        guard (1...60).contains(longBreakDuration) else {
            throw ValidationError.invalidBreakDuration
        }
        let validTimeRange = 0..<1440
        guard validTimeRange.contains(leisureTimeMinutes),
              validTimeRange.contains(wakeTimeMinutes),
              validTimeRange.contains(bedtimeTargetMinutes) else {
            throw ValidationError.invalidTimeOfDay
        }
    }
}
