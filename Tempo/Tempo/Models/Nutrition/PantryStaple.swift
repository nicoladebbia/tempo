//
// PantryStaple.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

// MARK: - StapleStatus

/// A staple's stock is a mood, not a count — nobody weighs their salt.
enum StapleStatus: String, Codable, CaseIterable, Sendable {
    case have
    case runningLow
    case out

    var label: String {
        switch self {
        case .have: "Have"
        case .runningLow: "Running low"
        case .out: "Out"
        }
    }

    /// Cycles have → running low → out → have, for the one-tap chip in
    /// `PantryView`'s Staples section.
    var next: StapleStatus {
        switch self {
        case .have: .runningLow
        case .runningLow: .out
        case .out: .have
        }
    }

    /// `runningLow` and `out` both belong on the grocery list — `have`
    /// doesn't need restocking.
    var needsRestock: Bool {
        self != .have
    }
}

// MARK: - PantryStaple

/// Spices, oils, sauces, condiments and baking basics — tracked as a
/// have/running-low/out MOOD rather than a quantity. Deliberately a
/// separate model from `PantryItem`:
///   - Staples are never decremented by a meal (`PantryDecrementService`
///     skips them), never show a quantity/unit/useBy in the UI, and are
///     cycled by a single tap rather than edited with a number pad.
///     Bolting three staple-only booleans + a status enum onto
///     `PantryItem` would mean every `PantryItem` reader (plan generator,
///     grocery generator, decrement service, receipts ingestion, Today
///     view) has to remember to check `isStaple` before touching quantity/
///     useBy/storageLocation — a silent footgun for every future feature.
///   - `docs/NUTRITION_PERSONALIZATION_DESIGN.md` §9 independently
///     recommends the same: "lean: own model" for staples.
@Model
final class PantryStaple {
    @Attribute(.unique)
    var id: UUID

    /// FoodCanonicalizer.canonicalize output — the merge/lookup key.
    var canonicalName: String

    /// Display label ("Olive oil", "Soy sauce").
    var displayName: String

    var statusRaw: String

    var createdAt: Date
    var updatedAt: Date

    @Transient
    var status: StapleStatus {
        get { StapleStatus(rawValue: statusRaw) ?? .have }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        canonicalName: String,
        displayName: String,
        status: StapleStatus = .have
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.displayName = displayName
        statusRaw = status.rawValue
        createdAt = Date()
        updatedAt = Date()
    }
}

// MARK: - Default suggestions

extension PantryStaple {
    /// Suggested on first opening the Staples section — a checklist, not a
    /// forced seed, so a vegan or gluten-free kitchen isn't handed soy
    /// sauce and flour it'll never buy.
    static let commonSuggestions: [(canonicalName: String, displayName: String)] = [
        ("salt", "Salt"),
        ("black pepper", "Black pepper"),
        ("olive oil", "Olive oil"),
        ("vegetable oil", "Vegetable oil"),
        ("soy sauce", "Soy sauce"),
        ("garlic powder", "Garlic powder"),
        ("onion powder", "Onion powder"),
        ("paprika", "Paprika"),
        ("cumin", "Cumin"),
        ("chili flakes", "Chili flakes"),
        ("oregano", "Oregano"),
        ("basil dried", "Dried basil"),
        ("cinnamon", "Cinnamon"),
        ("flour", "Flour"),
        ("sugar", "Sugar"),
        ("brown sugar", "Brown sugar"),
        ("baking powder", "Baking powder"),
        ("baking soda", "Baking soda"),
        ("vanilla extract", "Vanilla extract"),
        ("honey", "Honey"),
        ("ketchup", "Ketchup"),
        ("mustard", "Mustard"),
        ("mayonnaise", "Mayonnaise"),
        ("vinegar", "Vinegar"),
        ("hot sauce", "Hot sauce"),
    ]
}
