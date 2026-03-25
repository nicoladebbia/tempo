import Foundation
import SwiftData

@Model
final class NonNegotiableProgress {

    @Attribute(.unique)
    var id: UUID

    var date: Date

    var currentValue: Double

    var targetValue: Double

    var isCompleted: Bool

    var completedAt: Date?

    var sourceDataJSON: Data?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var nonNegotiable: NonNegotiable?

    @Relationship(deleteRule: .nullify)
    var dailyAccountability: DailyAccountability?

    // MARK: - Computed

    @Transient
    var progressPercentage: Double {
        guard targetValue > 0 else { return 0 }
        return min(currentValue / targetValue, 1.0)
    }

    @Transient
    var sourceData: [String: Any]? {
        guard let data = sourceDataJSON else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        currentValue: Double = 0,
        targetValue: Double,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        sourceDataJSON: Data? = nil,
        nonNegotiable: NonNegotiable? = nil,
        dailyAccountability: DailyAccountability? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sourceDataJSON = sourceDataJSON
        self.nonNegotiable = nonNegotiable
        self.dailyAccountability = dailyAccountability
    }
}

// MARK: - DTO

extension NonNegotiableProgress {

    struct DTO: Codable, Sendable {
        let id: UUID
        let date: Date
        let non_negotiable_id: UUID?
        let current_value: Double
        let target_value: Double
        let is_completed: Bool
        let completed_at: Date?
        let source_data: String?
    }

    func toDTO() -> DTO {
        let sourceString: String? = sourceDataJSON.flatMap { String(data: $0, encoding: .utf8) }
        return DTO(
            id: id,
            date: date,
            non_negotiable_id: nonNegotiable?.id,
            current_value: currentValue,
            target_value: targetValue,
            is_completed: isCompleted,
            completed_at: completedAt,
            source_data: sourceString
        )
    }
}
