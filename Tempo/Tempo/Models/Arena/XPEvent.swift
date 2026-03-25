import Foundation
import SwiftData

@Model
final class XPEvent {

    @Attribute(.unique)
    var id: UUID

    var date: Date

    var sourceRaw: String

    var amount: Int

    var eventDescription: String

    var createdAt: Date

    // MARK: - Computed

    @Transient
    var source: XPSource {
        get { XPSource(rawValue: sourceRaw) ?? .workout }
        set { sourceRaw = newValue.rawValue }
    }

    @Transient
    var isPenalty: Bool {
        amount < 0
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        source: XPSource,
        amount: Int,
        description: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.sourceRaw = source.rawValue
        self.amount = amount
        self.eventDescription = description
        self.createdAt = createdAt
    }
}

// MARK: - DTO

extension XPEvent {

    struct DTO: Codable, Sendable {
        let id: UUID
        let date: Date
        let source: String
        let amount: Int
        let description: String
        let created_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            source: sourceRaw,
            amount: amount,
            description: eventDescription,
            created_at: createdAt
        )
    }
}
