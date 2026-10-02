//
// MealReviewDraft.swift
// Tempo
//
// The editable state behind the "Confirm meal" review sheet (Quick Log, meal
// photo, barcode): when it was eaten, which meal it is, and a portion factor
// per food. Kept out of the view so time → meal-type and portion scaling are
// unit-testable.
//

import Foundation

struct MealReviewDraft {
    let originals: [ParsedFoodItem]
    private(set) var factors: [String: Double]
    private(set) var eatenAt: Date
    private(set) var mealType: MealType

    /// Portion chips offered on every row.
    static let factorChoices: [Double] = [0.5, 1, 1.5, 2]
    /// Typed grams stay inside a sane range.
    static let maxFactor = 10.0

    /// - Parameters:
    ///   - hintedDate: time parsed from the user's text, nil → `now`.
    ///   - hintedType: meal named in the text; wins over the time-of-day default.
    init(items: [ParsedFoodItem], hintedDate: Date? = nil, hintedType: MealType? = nil, now: Date = Date()) {
        originals = items
        factors = Dictionary(uniqueKeysWithValues: items.map { ($0.id, 1.0) })
        let date = hintedDate ?? now
        eatenAt = date
        mealType = hintedType ?? EatenMealRecorder.defaultMealType(for: date)
    }

    /// Changing the time re-derives the meal (3pm lunch → 9pm dinner); picking
    /// the meal by hand afterwards sticks until the time moves again.
    mutating func setEatenAt(_ date: Date) {
        guard date != eatenAt else {
            return
        }
        eatenAt = date
        mealType = EatenMealRecorder.defaultMealType(for: date)
    }

    mutating func setMealType(_ type: MealType) {
        mealType = type
    }

    // MARK: Portions

    func factor(for id: String) -> Double {
        factors[id] ?? 1
    }

    mutating func setFactor(_ factor: Double, for id: String) {
        guard factors[id] != nil, factor > 0 else {
            return
        }
        factors[id] = min(factor, Self.maxFactor)
    }

    /// Typed grams. Ignored when the original weight is unknown.
    mutating func setGrams(_ grams: Double, for id: String) {
        guard let original = originals.first(where: { $0.id == id }), original.quantityGrams > 0, grams > 0 else {
            return
        }
        setFactor(grams / original.quantityGrams, for: id)
    }

    mutating func remove(_ id: String) {
        factors[id] = nil
    }

    /// The foods as they will be logged.
    var items: [ParsedFoodItem] {
        originals.compactMap { original in
            factors[original.id].map { original.scaled(by: $0) }
        }
    }

    var totalCalories: Int {
        items.reduce(0) { $0 + Int($1.calories) }
    }

    var totalProtein: Double {
        items.reduce(0) { $0 + $1.proteinG }
    }

    var totalCarbs: Double {
        items.reduce(0) { $0 + $1.carbsG }
    }

    var totalFat: Double {
        items.reduce(0) { $0 + $1.fatG }
    }
}

// MARK: - Sheet identity

/// Identity of the review sheet for `.sheet(item:)`. Derived from the foods,
/// never from a fresh UUID: an id that changes every time SwiftUI re-reads the
/// binding makes the sheet dismiss and re-present in a loop.
struct ParsedFoodReviewPayload: Identifiable, Equatable {
    let items: [ParsedFoodItem]

    var id: String {
        items.map(\.id).joined(separator: "|")
    }

    static func == (lhs: ParsedFoodReviewPayload, rhs: ParsedFoodReviewPayload) -> Bool {
        lhs.id == rhs.id
    }
}
