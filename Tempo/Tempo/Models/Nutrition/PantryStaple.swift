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

// MARK: - StapleDietFilter

/// Hides staple suggestions that clash with the user's allergies, won't-eat
/// list or diet flags — a soy allergy must never see soy sauce pre-listed.
struct StapleDietFilter: Equatable, Sendable {
    /// Free text from DietaryProfile.allergies + dislikedFoods, lowercased.
    var avoidTerms: [String] = []
    var glutenFree = false
    var vegan = false
    var nutFree = false
    var avoidAddedSugars = false
    var lactoseFree = false
    var halal = false
    var shellfishAllergy = false

    static let none = StapleDietFilter()

    init(avoidTerms: [String] = [], glutenFree: Bool = false, vegan: Bool = false, nutFree: Bool = false, avoidAddedSugars: Bool = false, lactoseFree: Bool = false, halal: Bool = false, shellfishAllergy: Bool = false) {
        self.avoidTerms = avoidTerms.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.glutenFree = glutenFree
        self.vegan = vegan
        self.nutFree = nutFree
        self.avoidAddedSugars = avoidAddedSugars
        self.lactoseFree = lactoseFree
        self.halal = halal
        self.shellfishAllergy = shellfishAllergy
    }

    init(profile: DietaryProfile?) {
        guard let profile else {
            self = .none
            return
        }
        self.init(
            avoidTerms: profile.allergies + profile.dislikedFoods,
            glutenFree: profile.isGlutenFree,
            vegan: profile.isVegan,
            nutFree: profile.isNutFree,
            avoidAddedSugars: profile.avoidAddedSugars,
            lactoseFree: profile.isLactoseFree,
            halal: profile.isHalal,
            shellfishAllergy: profile.isShellFishAllergy
        )
    }

    /// What each suggestion is made of / counts as, beyond its own name.
    private static let hiddenIngredients: [String: [String]] = [
        "soy sauce": ["soy", "soya", "soybean", "wheat", "gluten"],
        "flour": ["wheat", "gluten"],
        "mayonnaise": ["egg", "eggs"],
        "vegetable oil": ["soy", "soya", "soybean"],
        "ketchup": ["tomato"],
        "mustard": ["mustard"],
        "hot sauce": ["chili", "chilli", "pepper"],
        "chili flakes": ["chili", "chilli", "pepper"],
        "black pepper": ["pepper"],
        "baking powder": ["corn"],
        "vanilla extract": ["vanilla", "alcohol"],
    ]

    private static let glutenStaples: Set = ["soy sauce", "flour"]
    /// Words each diet flag adds to the hidden-ingredient check, so any
    /// staple (default list or future) that is made of them is filtered.
    private static let nutTerms = ["nut", "almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "peanut"]
    private static let dairyTerms = ["milk", "dairy", "butter", "cheese", "cream", "ghee", "whey"]
    private static let nonHalalTerms = ["pork", "lard", "bacon", "alcohol", "wine", "rum", "bourbon", "gelatin"]
    private static let shellfishTerms = ["shellfish", "shrimp", "prawn", "crab", "lobster", "oyster", "clam", "mussel"]
    private static let veganBlocked: Set = ["honey", "mayonnaise"]
    private static let sugarStaples: Set = ["sugar", "brown sugar", "honey", "ketchup"]

    /// `true` when the staple is fine for this user.
    func allows(_ staple: (canonicalName: String, displayName: String)) -> Bool {
        let key = staple.canonicalName
        if glutenFree, Self.glutenStaples.contains(key) {
            return false
        }
        if vegan, Self.veganBlocked.contains(key) {
            return false
        }
        if avoidAddedSugars, Self.sugarStaples.contains(key) {
            return false
        }
        let haystack = ([key, staple.displayName.lowercased()] + (Self.hiddenIngredients[key] ?? []))
        var terms = avoidTerms
        if nutFree { terms += Self.nutTerms }
        if lactoseFree { terms += Self.dairyTerms }
        if halal { terms += Self.nonHalalTerms }
        if shellfishAllergy { terms += Self.shellfishTerms }
        for term in terms {
            let variants = Set([term, PantryStorageGuesser.singular(term)])
            if haystack.contains(where: { text in variants.contains { Self.matches(term: $0, in: text) } }) {
                return false
            }
        }
        return true
    }

    /// Whole-word match: "soy" blocks "soy sauce"; "pea" never hits "peanut".
    private static func matches(term: String, in text: String) -> Bool {
        if text == term {
            return true
        }
        return PantryStorageGuesser.containsKeyword(term, in: text)
    }
}

extension PantryStaple {
    /// `commonSuggestions` minus anything the diet filter rejects.
    static func suggestions(for filter: StapleDietFilter) -> [(canonicalName: String, displayName: String)] {
        commonSuggestions.filter { filter.allows($0) }
    }
}
