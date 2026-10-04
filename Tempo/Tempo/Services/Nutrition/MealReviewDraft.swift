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
    /// Kitchen (comes off the pantry) or out, per food. Pre-selected from the
    /// location when it is known; a manual pick always wins over a later fix.
    private(set) var itemOrigins: [String: MealOrigin]
    /// True while the origins still come from the location / last choice,
    /// false once the user picked any by hand.
    private(set) var originWasAutoSet = true
    /// True once the meal type was named (by the text or by the user): then it
    /// no longer follows the time.
    private(set) var mealTypeWasPicked: Bool

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
        itemOrigins = Dictionary(uniqueKeysWithValues: items.map { ($0.id, MealOrigin.kitchen) })
        mealTypeWasPicked = hintedType != nil
        let date = hintedDate ?? now
        eatenAt = date
        mealType = hintedType ?? EatenMealRecorder.defaultMealType(for: date)
    }

    /// Changing the time re-derives the meal (3pm lunch → 9pm dinner) unless
    /// the meal was named: by the user's text ("for lunch") or by the user's
    /// own tap on a meal chip. A named meal sticks.
    mutating func setEatenAt(_ date: Date) {
        guard date != eatenAt else {
            return
        }
        eatenAt = date
        if !mealTypeWasPicked {
            mealType = EatenMealRecorder.defaultMealType(for: date)
        }
    }

    /// The user's own pick. Sticks, whatever the time does afterwards.
    mutating func setMealType(_ type: MealType) {
        mealType = type
        mealTypeWasPicked = true
    }

    // MARK: Origin

    /// The meal-level origin the rows add up to: all kitchen / all out / mixed.
    var origin: MealOrigin {
        MealOrigin.combined(remainingIDs.map(origin(for:))) ?? lastTopChoice
    }

    /// What the top "Where from?" control last set (used while no rows remain).
    private var lastTopChoice: MealOrigin = .kitchen

    private var remainingIDs: [String] {
        originals.map(\.id).filter { factors[$0] != nil }
    }

    func origin(for id: String) -> MealOrigin {
        itemOrigins[id] ?? .kitchen
    }

    /// The user's top choice: every row follows it. Sticks: a location fix
    /// arriving later can't undo it. (`.mixed` is not a choice: a no-op.)
    mutating func setOrigin(_ newOrigin: MealOrigin) {
        guard newOrigin != .mixed else {
            return
        }
        for id in itemOrigins.keys {
            itemOrigins[id] = newOrigin
        }
        lastTopChoice = newOrigin
        originWasAutoSet = false
    }

    /// One row's own choice (the soy sauce from home on an ate-out meal).
    mutating func setOrigin(_ newOrigin: MealOrigin, for id: String) {
        guard newOrigin != .mixed, itemOrigins[id] != nil else {
            return
        }
        itemOrigins[id] = newOrigin
        originWasAutoSet = false
    }

    /// The location (or remembered choice) says `suggested`. Ignored once the
    /// user chose by hand.
    mutating func applySuggestedOrigin(_ suggested: MealOrigin) {
        guard originWasAutoSet, suggested != .mixed else {
            return
        }
        for id in itemOrigins.keys {
            itemOrigins[id] = suggested
        }
        lastTopChoice = suggested
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

    /// The foods as they will be logged, each stamped with where it came from.
    var items: [ParsedFoodItem] {
        originals.compactMap { original in
            factors[original.id].map {
                var item = original.scaled(by: $0)
                item.origin = origin(for: original.id)
                return item
            }
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
