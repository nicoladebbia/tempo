//
// TravelEquipmentPeriod.swift
// Tempo
//
// "Limited equipment today/this week" (pause/travel-pain feature). While one
// covers a day, trainer exercises needing unavailable equipment are
// auto-swapped by `TravelSwapEngine` inside
// `TrainingViewModel.populateFromTrainerProgram` (`TrainingViewModel+
// TrainerProgram.swift`) — see that file's travel-swap block.
//
// Distinct model from `TrainingPause`: equipment-limited doesn't mean
// "don't train" (the opposite of a pause — you're still training, just with
// less gear), so it needs its own date range and its own payload (the
// available-equipment set) rather than overloading the pause model.
//

import Foundation
import SwiftData

// MARK: - TravelEquipmentScope

enum TravelEquipmentScope: String, Codable, CaseIterable, Sendable {
    case today
    case thisWeek

    var displayName: String {
        switch self {
        case .today: "Today only"
        case .thisWeek: "This week"
        }
    }
}

// MARK: - TravelEquipmentPeriod

@Model
final class TravelEquipmentPeriod {
    @Attribute(.unique)
    var id: UUID

    /// Start-of-day, inclusive.
    var startDate: Date
    /// Start-of-day, inclusive — `startDate` itself for `.today`, the Sunday
    /// of `startDate`'s ISO week for `.thisWeek`.
    var endDate: Date

    var scopeRaw: String

    /// `Equipment.rawValue` list — what's actually available (e.g. hotel gym
    /// = dumbbells only). JSON array, same convention as
    /// `UserSettings.customWeekdayPlanJSON`.
    var availableEquipmentJSON: Data

    var createdAt: Date

    /// Set when the athlete ends it early (mirrors `TrainingPause.resumedAt`).
    var endedAt: Date?

    init(
        id: UUID = UUID(),
        scope: TravelEquipmentScope,
        availableEquipment: [Equipment],
        startDate: Date = Date(),
        createdAt: Date = Date(),
        calendar: Calendar = TrainingCalendar.iso8601
    ) {
        self.id = id
        let start = calendar.startOfDay(for: startDate)
        self.startDate = start
        scopeRaw = scope.rawValue
        switch scope {
        case .today:
            endDate = start
        case .thisWeek:
            let monday = TrainingCalendar.mondayOfWeek(containing: start)
            endDate = calendar.date(byAdding: .day, value: 6, to: monday) ?? start
        }
        availableEquipmentJSON = (try? JSONEncoder().encode(availableEquipment.map(\.rawValue))) ?? Data()
        self.createdAt = createdAt
    }

    // MARK: - Typed accessors

    @Transient
    var scope: TravelEquipmentScope {
        get { TravelEquipmentScope(rawValue: scopeRaw) ?? .today }
        set { scopeRaw = newValue.rawValue }
    }

    @Transient
    var availableEquipment: Set<Equipment> {
        get {
            guard let raw = try? JSONDecoder().decode([String].self, from: availableEquipmentJSON) else {
                return []
            }
            return Set(raw.compactMap(Equipment.init(rawValue:)))
        }
        set {
            availableEquipmentJSON = (try? JSONEncoder().encode(Array(newValue).map(\.rawValue))) ?? Data()
        }
    }

    /// True while this period covers `date` and hasn't been manually ended
    /// before it.
    nonisolated func covers(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard day >= startDate, day <= endDate else {
            return false
        }
        if let endedAt, day >= calendar.startOfDay(for: endedAt) {
            return false
        }
        return true
    }
}
