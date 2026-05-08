//
// WeeklyMealPlan.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import SwiftData

@Model
final class WeeklyMealPlan {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Schedule

    var startDate: Date

    var endDate: Date

    var dayTypeAssignmentsJSON: Data?

    // MARK: - Lifecycle

    var isActive: Bool

    var generatedAt: Date

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.mealPlan)
    var meals: [PlannedMeal]?

    // MARK: - Computed Properties

    /// Maps weekday number (1 = Sunday, 7 = Saturday) to DayType.
    @Transient
    var dayTypeAssignments: [Int: String] {
        get {
            guard let data = dayTypeAssignmentsJSON else {
                return [:]
            }
            return (try? JSONDecoder().decode([Int: String].self, from: data)) ?? [:]
        }
        set {
            dayTypeAssignmentsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    /// Typed day-type lookup for a given weekday number.
    @Transient
    var dayTypes: [Int: DayType] {
        var result: [Int: DayType] = [:]
        for (key, value) in dayTypeAssignments {
            if let dayType = DayType(rawValue: value) {
                result[key] = dayType
            }
        }
        return result
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        dayTypeAssignments: [Int: String] = [:],
        isActive: Bool = true,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: endDate)
        dayTypeAssignmentsJSON = dayTypeAssignments.isEmpty
            ? nil
            : try? JSONEncoder().encode(dayTypeAssignments)
        self.isActive = isActive
        self.generatedAt = generatedAt
    }
}
