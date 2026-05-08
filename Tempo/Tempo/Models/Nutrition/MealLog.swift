//
// MealLog.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - MealLog

@Model
final class MealLog {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Meal Info

    var mealTypeRaw: String

    var loggedAt: Date

    var photoData: Data?

    // MARK: - Macro Totals

    var totalCalories: Double

    var totalProtein: Double

    var totalCarbs: Double

    var totalFat: Double

    var totalFiber: Double?

    // MARK: - Metadata

    var notes: String?

    var sourceRaw: String

    var syncedToHealthKit: Bool

    var syncedToBackend: Bool

    /// Calendar date (normalized to midnight). Used for grouping and querying.
    var dayDate: Date

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \MealFoodItem.mealLog)
    var items: [MealFoodItem] = []

    // MARK: - Computed Properties

    @Transient
    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    @Transient
    var mealSource: MealSource {
        get { MealSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    @Transient
    var orderedItems: [MealFoodItem] {
        items.sorted { $0.name < $1.name }
    }

    @Transient
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: loggedAt)
    }

    @Transient
    var formattedCalories: String {
        NumberFormatter.localizedString(
            from: NSNumber(value: Int(totalCalories)),
            number: .decimal
        ) + " kcal"
    }

    @Transient
    var itemCount: Int {
        items.count
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        mealType: MealType,
        loggedAt: Date = Date(),
        photoData: Data? = nil,
        totalCalories: Double = 0,
        totalProtein: Double = 0,
        totalCarbs: Double = 0,
        totalFat: Double = 0,
        totalFiber: Double? = nil,
        notes: String? = nil,
        source: MealSource = .manual,
        syncedToHealthKit: Bool = false,
        syncedToBackend: Bool = false,
        dayDate: Date? = nil
    ) {
        self.id = id
        mealTypeRaw = mealType.rawValue
        self.loggedAt = loggedAt
        self.photoData = photoData
        self.totalCalories = totalCalories
        self.totalProtein = totalProtein
        self.totalCarbs = totalCarbs
        self.totalFat = totalFat
        self.totalFiber = totalFiber
        self.notes = notes
        sourceRaw = source.rawValue
        self.syncedToHealthKit = syncedToHealthKit
        self.syncedToBackend = syncedToBackend
        self.dayDate = dayDate ?? Calendar.current.startOfDay(for: loggedAt)
    }

    /// Convenience init for service layer — calculates totals from items.
    init(
        type: MealType,
        dayDate: Date,
        source: MealSource,
        photo: Data? = nil,
        items: [MealFoodItem] = []
    ) {
        id = UUID()
        mealTypeRaw = type.rawValue
        loggedAt = Date()
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        sourceRaw = source.rawValue
        photoData = photo
        totalCalories = items.reduce(0) { $0 + $1.totalCalories }
        totalProtein = items.reduce(0) { $0 + $1.totalProtein }
        totalCarbs = items.reduce(0) { $0 + $1.totalCarbs }
        totalFat = items.reduce(0) { $0 + $1.totalFat }
        totalFiber = nil
        notes = nil
        syncedToHealthKit = false
        syncedToBackend = false
        self.items = items
    }

    /// Recalculate totals from current items.
    func recalculateTotals() {
        totalCalories = items.reduce(0) { $0 + $1.totalCalories }
        totalProtein = items.reduce(0) { $0 + $1.totalProtein }
        totalCarbs = items.reduce(0) { $0 + $1.totalCarbs }
        totalFat = items.reduce(0) { $0 + $1.totalFat }
    }
}

// MARK: - DTO

extension MealLog {
    struct DTO: Codable {
        let id: UUID
        let meal_type: String
        let logged_at: Date
        let total_calories: Double
        let total_protein: Double
        let total_carbs: Double
        let total_fat: Double
        let total_fiber: Double?
        let notes: String?
        let source: String
        let synced_to_healthkit: Bool
        let synced_to_backend: Bool
        let day_date: Date
        let items: [MealFoodItem.DTO]?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            meal_type: mealTypeRaw,
            logged_at: loggedAt,
            total_calories: totalCalories,
            total_protein: totalProtein,
            total_carbs: totalCarbs,
            total_fat: totalFat,
            total_fiber: totalFiber,
            notes: notes,
            source: sourceRaw,
            synced_to_healthkit: syncedToHealthKit,
            synced_to_backend: syncedToBackend,
            day_date: dayDate,
            items: orderedItems.map { $0.toDTO() }
        )
    }
}
