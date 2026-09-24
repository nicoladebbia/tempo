//
// WeeklyMealPlan.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
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

    /// Per-day supplement take/skip decisions from the plan AI, keyed by
    /// weekday number (1 = Sunday … 7 = Saturday, matching dayTypeAssignments).
    /// Empty/absent when the user owns no supplements. Additive — defaults nil.
    var supplementDecisionsJSON: Data?

    // MARK: - Lifecycle

    var isActive: Bool

    /// True once a newer plan has superseded this one. Archived plans are
    /// retained (not deleted) so the personalization engine can read what the
    /// user actually ate/skipped + their feedback for past weeks, and the
    /// "Past Plans" history view can surface them. They are excluded from every
    /// active/today query (which filter on `isActive`). Defaults false so the
    /// SwiftData field add is a lightweight migration.
    var isArchived: Bool = false

    var generatedAt: Date

    /// `MealPlanInputsFingerprint` of the training / diet-profile inputs this
    /// plan was generated from. A mismatch with the current inputs on load
    /// means the plan is out of date. nil = generated before fingerprints
    /// existed (adopted as current on first load). Optional so the SwiftData
    /// field add is a lightweight migration.
    var inputsFingerprint: String?

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

    /// Per-day supplement decisions, keyed by weekday number (1 = Sunday …
    /// 7 = Saturday). Decoded from `supplementDecisionsJSON`. Empty when the
    /// user owns no supplements or the plan predates this feature.
    @Transient
    var supplementDecisions: [Int: [SupplementDecision]] {
        get {
            guard let data = supplementDecisionsJSON else {
                return [:]
            }
            return (try? JSONDecoder().decode([Int: [SupplementDecision]].self, from: data)) ?? [:]
        }
        set {
            supplementDecisionsJSON = try? JSONEncoder().encode(newValue)
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

    /// True when today's calendar date falls within `[startDate, endDate]`
    /// inclusive. Both bounds are normalized to start-of-day at init, so a
    /// plan dated May 25–31 covers all of May 31. This is the single source
    /// of truth for "is this plan current" — `isActive` alone is NOT enough,
    /// because a plan stays `isActive` until the next generation deletes it,
    /// so an out-of-range past plan would otherwise read as the active plan.
    @Transient
    var coversToday: Bool {
        coversDate(Date())
    }

    /// True when `date`'s calendar day falls within `[startDate, endDate]`
    /// inclusive.
    func coversDate(_ date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        return day >= startDate && day <= endDate
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
        let normalizedStart = Calendar.current.startOfDay(for: startDate)
        let normalizedEnd = Calendar.current.startOfDay(for: endDate)
        // If caller swaps arguments, swap them back so we never store a
        // negative-width week (which downstream day iterators would skip).
        if normalizedEnd < normalizedStart {
            self.startDate = normalizedEnd
            self.endDate = normalizedStart
        } else {
            self.startDate = normalizedStart
            self.endDate = normalizedEnd
        }
        dayTypeAssignmentsJSON = dayTypeAssignments.isEmpty
            ? nil
            : try? JSONEncoder().encode(dayTypeAssignments)
        self.isActive = isActive
        self.generatedAt = generatedAt
    }
}
