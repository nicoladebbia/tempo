//
// NonNegotiable.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - NonNegotiable

@Model
final class NonNegotiable {
    @Attribute(.unique)
    var id: UUID

    var name: String

    var typeRaw: String

    var icon: String

    var targetValue: Double

    var trackingMethodRaw: String

    var activeDaysRaw: Int

    var order: Int

    var isActive: Bool

    var createdAt: Date

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \NonNegotiableProgress.nonNegotiable)
    var progressEntries: [NonNegotiableProgress]?

    // MARK: - Computed

    @Transient
    var type: NonNegotiableType {
        get { NonNegotiableType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var trackingMethod: TrackingMethod {
        get { TrackingMethod(rawValue: trackingMethodRaw) ?? .manual }
        set { trackingMethodRaw = newValue.rawValue }
    }

    @Transient
    var activeDays: ActiveDays {
        get { ActiveDays(rawValue: activeDaysRaw) }
        set { activeDaysRaw = newValue.rawValue }
    }

    @Transient
    var isAutoTracked: Bool {
        trackingMethod != .manual
    }

    @Transient
    var integrationSourceName: String? {
        switch trackingMethod {
        case .autoWhoop: "WHOOP"
        case .autoNutritrack: "NUTRITRACK"
        case .autoHealthkit: "HEALTHKIT"
        case .timer: "TIMER"
        case .manual: nil
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        type: NonNegotiableType,
        icon: String? = nil,
        targetValue: Double,
        trackingMethod: TrackingMethod = .manual,
        activeDays: ActiveDays = .everyday,
        order: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        typeRaw = type.rawValue
        self.icon = icon ?? type.defaultIcon
        self.targetValue = targetValue
        trackingMethodRaw = trackingMethod.rawValue
        activeDaysRaw = activeDays.rawValue
        self.order = order
        self.isActive = isActive
        createdAt = Date()
    }
}

// MARK: - DTO

extension NonNegotiable {
    struct DTO: Codable {
        let id: UUID
        let name: String
        let type: String
        let icon: String
        let target_value: Double
        let tracking_method: String
        let active_days: Int
        let order: Int
        let is_active: Bool
        let created_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            name: name,
            type: typeRaw,
            icon: icon,
            target_value: targetValue,
            tracking_method: trackingMethodRaw,
            active_days: activeDaysRaw,
            order: order,
            is_active: isActive,
            created_at: createdAt
        )
    }
}
