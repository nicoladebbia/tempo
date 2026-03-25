import Foundation
import SwiftData

@Model
final class StudySession {

    @Attribute(.unique)
    var id: UUID

    var startTime: Date

    var endTime: Date?

    var durationMinutes: Int

    var subject: String?

    var sessionTypeRaw: String

    var focusScore: Int?

    var distractions: Int

    var completedPomodoros: Int

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var dailyAccountability: DailyAccountability?

    // MARK: - Computed

    @Transient
    var sessionType: StudySessionType {
        get { StudySessionType(rawValue: sessionTypeRaw) ?? .pomodoro }
        set { sessionTypeRaw = newValue.rawValue }
    }

    @Transient
    var isInProgress: Bool {
        endTime == nil
    }

    @Transient
    var durationFormatted: String {
        let hours = durationMinutes / 60
        let mins = durationMinutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    @Transient
    var effectiveFocusScore: Int {
        if let fs = focusScore { return fs }
        return max(0, 100 - (distractions * 10))
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date? = nil,
        durationMinutes: Int = 0,
        subject: String? = nil,
        sessionType: StudySessionType = .pomodoro,
        focusScore: Int? = nil,
        distractions: Int = 0,
        completedPomodoros: Int = 0,
        dailyAccountability: DailyAccountability? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.subject = subject
        self.sessionTypeRaw = sessionType.rawValue
        self.focusScore = focusScore
        self.distractions = distractions
        self.completedPomodoros = completedPomodoros
        self.dailyAccountability = dailyAccountability
    }
}

// MARK: - DTO

extension StudySession {

    struct DTO: Codable, Sendable {
        let id: UUID
        let start_time: Date
        let end_time: Date?
        let duration_minutes: Int
        let subject: String?
        let session_type: String
        let focus_score: Int?
        let distractions: Int
        let completed_pomodoros: Int
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            start_time: startTime,
            end_time: endTime,
            duration_minutes: durationMinutes,
            subject: subject,
            session_type: sessionTypeRaw,
            focus_score: focusScore,
            distractions: distractions,
            completed_pomodoros: completedPomodoros
        )
    }
}
