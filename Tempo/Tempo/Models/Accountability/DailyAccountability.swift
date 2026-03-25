import Foundation
import SwiftData

@Model
final class DailyAccountability {

    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var date: Date

    var leisureUnlocked: Bool

    var unlockedAt: Date?

    var totalStudyMinutes: Int

    var accountabilityScore: Int

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \NonNegotiableProgress.dailyAccountability)
    var nonNegotiableProgress: [NonNegotiableProgress]?

    @Relationship(deleteRule: .cascade, inverse: \StudySession.dailyAccountability)
    var studySessions: [StudySession]?

    // MARK: - Computed

    @Transient
    var completedCount: Int {
        (nonNegotiableProgress ?? []).filter(\.isCompleted).count
    }

    @Transient
    var totalCount: Int {
        nonNegotiableProgress?.count ?? 0
    }

    @Transient
    var completionPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    @Transient
    var allComplete: Bool {
        totalCount > 0 && completedCount == totalCount
    }

    @Transient
    var completedPomodoros: Int {
        (studySessions ?? []).reduce(0) { $0 + $1.completedPomodoros }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        leisureUnlocked: Bool = false,
        unlockedAt: Date? = nil,
        totalStudyMinutes: Int = 0,
        accountabilityScore: Int = 0
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.leisureUnlocked = leisureUnlocked
        self.unlockedAt = unlockedAt
        self.totalStudyMinutes = totalStudyMinutes
        self.accountabilityScore = accountabilityScore
    }
}

// MARK: - DTO

extension DailyAccountability {

    struct DTO: Codable, Sendable {
        let id: UUID
        let date: Date
        let leisure_unlocked: Bool
        let unlocked_at: Date?
        let total_study_minutes: Int
        let accountability_score: Int
        let non_negotiable_progress: [NonNegotiableProgress.DTO]?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            leisure_unlocked: leisureUnlocked,
            unlocked_at: unlockedAt,
            total_study_minutes: totalStudyMinutes,
            accountability_score: accountabilityScore,
            non_negotiable_progress: nonNegotiableProgress?.map { $0.toDTO() }
        )
    }
}
