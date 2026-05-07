//
// RecoveryInsight.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - RecoveryInsight

@Model
final class RecoveryInsight {
    @Attribute(.unique)
    var id: UUID

    var date: Date

    var typeRaw: String

    var title: String

    var body: String

    var dataPointsJSON: Data?

    var confidence: Double

    var wasDismissed: Bool

    var dismissedAt: Date?

    // MARK: - Computed

    @Transient
    var type: RecoveryInsightType {
        get { RecoveryInsightType(rawValue: typeRaw) ?? .recommendation }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var dataPoints: [[String: Any]]? {
        guard let data = dataPointsJSON else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    @Transient
    var isHighConfidence: Bool {
        confidence >= 0.7
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        type: RecoveryInsightType,
        title: String,
        body: String,
        dataPointsJSON: Data? = nil,
        confidence: Double,
        wasDismissed: Bool = false
    ) {
        self.id = id
        self.date = date
        typeRaw = type.rawValue
        self.title = title
        self.body = body
        self.dataPointsJSON = dataPointsJSON
        self.confidence = confidence
        self.wasDismissed = wasDismissed
    }
}

// MARK: - DTO

extension RecoveryInsight {
    struct DTO: Codable {
        let id: UUID
        let date: Date
        let type: String
        let title: String
        let body: String
        let data_points: String?
        let confidence: Double
        let was_dismissed: Bool
    }

    func toDTO() -> DTO {
        let dpString: String? = dataPointsJSON.flatMap { String(data: $0, encoding: .utf8) }
        return DTO(
            id: id,
            date: date,
            type: typeRaw,
            title: title,
            body: body,
            data_points: dpString,
            confidence: confidence,
            was_dismissed: wasDismissed
        )
    }
}
