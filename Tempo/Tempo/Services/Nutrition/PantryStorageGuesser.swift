//
// PantryStorageGuesser.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation

/// Guesses a storage location for a barcode-scanned `FoodProduct` from its
/// name + category tags — the same keyword-heuristic idea
/// `LiveReceiptService` uses for receipt line items, applied to Open Food
/// Facts–style category tags instead of a free-text line description.
/// Best-effort; always editable in the confirm sheet before saving.
enum PantryStorageGuesser {
    private static let freezerKeywords = [
        "frozen", "ice-cream", "ice cream", "sorbet", "surgel",
    ]
    private static let fridgeKeywords = [
        "dairy", "milk", "yogurt", "yoghurt", "cheese", "butter", "cream",
        "fresh", "meat", "poultry", "chicken", "beef", "pork", "fish", "seafood",
        "eggs", "tofu", "deli", "charcuterie", "sausage", "ham",
    ]
    private static let pantryKeywords = [
        "canned", "can", "dried", "pasta", "rice", "cereal", "flour", "sugar",
        "spice", "sauce", "oil", "vinegar", "snack", "chip", "biscuit",
        "cookie", "chocolate", "candy", "condiment", "jam", "honey", "coffee",
        "tea", "water", "soda", "juice", "beverage",
    ]

    static func guess(for product: FoodProduct) -> PantryStorageLocation {
        let haystack = ([product.name] + product.categories)
            .joined(separator: " ")
            .lowercased()

        if freezerKeywords.contains(where: haystack.contains) {
            return .freezer
        }
        if fridgeKeywords.contains(where: haystack.contains) {
            return .fridge
        }
        if pantryKeywords.contains(where: haystack.contains) {
            return .pantry
        }
        // Shelf-stable beverages (water, soda) default to pantry; anything
        // else unclassified is safest as pantry too (not perishable-fridge).
        return .pantry
    }
}
