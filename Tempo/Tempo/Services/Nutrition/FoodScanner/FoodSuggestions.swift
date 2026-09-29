//
// FoodSuggestions.swift
// Tempo
//
// What the product screen shows under "suggestions": healthier swaps when
// something better exists, otherwise equally good picks from the same shelf.
// Works for every source — packaged (Open Food Facts), USDA and built-in foods.
//

import Foundation

// MARK: - FoodSuggestions

struct FoodSuggestions: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Items that score higher than the product.
        case healthier
        /// The product is already great — peers of similar quality.
        case similar
    }

    var kind: Kind
    var items: [FoodProduct]

    static let empty = FoodSuggestions(kind: .similar, items: [])
}

// MARK: - FoodGroup

/// Broad shelf a food belongs to — drives placeholder art and suggestion fallbacks.
enum FoodGroup: String, CaseIterable, Sendable {
    case dairy
    case meat
    case fish
    case eggs
    case grains
    case bread
    case pasta
    case legumes
    case nuts
    case fruit
    case vegetables
    case snacks
    case sweets
    case drinks
    case oils
    case sauces
    case meals
    case other
}

// MARK: - CONTRACT STUBS (lane A replaces the bodies; signatures are fixed)

extension FoodProduct {
    /// Shelf this food belongs to, from categories/name.
    var foodGroup: FoodGroup { .other }

    /// Allergens as people read them ("Milk", "Gluten"), limited to the
    /// EU-14 / US major allergens, de-duplicated. Never raw OFF tags.
    var displayAllergens: [String] { [] }
}

extension FoodCatalog {
    /// Always-there suggestions for any product. Empty only when nothing at
    /// all could be found (offline and no built-in peers).
    func suggestions(for product: FoodProduct, limit: Int = 6) async -> FoodSuggestions {
        .empty
    }
}

/// Photo for foods that have none (USDA, built-in, generic): a CC-licensed
/// picture resolved by name and remembered on disk.
enum GenericFoodImages {
    static func imageURL(for product: FoodProduct) async -> URL? { nil }
}

/// Disk + memory cache for product photos so history and favourites work offline.
actor FoodImageCache {
    static let shared = FoodImageCache()

    func data(for url: URL) async -> Data? { nil }
}
