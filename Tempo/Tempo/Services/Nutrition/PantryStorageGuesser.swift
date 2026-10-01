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
        "frozen", "ice-cream", "ice cream", "sorbet", "surgel", "gelato", "popsicle", "ice cube",
    ]
    private static let fridgeKeywords = [
        "dairy", "milk", "yogurt", "yoghurt", "cheese", "butter", "cream",
        "fresh", "meat", "poultry", "chicken", "beef", "pork", "fish", "seafood",
        "eggs", "egg", "tofu", "deli", "charcuterie", "sausage", "ham",
        "turkey", "salmon", "spinach", "asparagus", "broccoli", "berries",
        "lettuce", "bacon", "steak", "lamb", "veal", "shrimp", "cod", "tilapia",
    ]
    /// Shelf-stable "butters" that must NOT hit the dairy rule.
    private static let pantryOverrides = [
        "peanut butter", "almond butter", "nut butter", "cashew butter",
        "sunflower seed butter", "cocoa butter", "apple butter", "butter beans",
        "coconut cream", "cream of tartar", "ice tea", "iced tea",
    ]

    /// Whole-word / whole-phrase match (plural-tolerant). Substring matching
    /// put rice, juice and spices in the freezer ("ice"), steak in the pantry
    /// ("tea") and peanut butter in the fridge ("butter").
    static func containsKeyword(_ keyword: String, in haystack: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: keyword) + "(?:s|es)?\\b"
        return haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsAny(_ keywords: [String], in haystack: String) -> Bool {
        keywords.contains { containsKeyword($0, in: haystack) }
    }

    static func guess(for product: FoodProduct) -> PantryStorageLocation {
        guess(haystack: ([product.name] + product.categories).joined(separator: " "))
    }

    /// Receipt/ingredient path: only a canonical food name, no category tags.
    static func guess(forName name: String) -> PantryStorageLocation {
        guess(haystack: name)
    }

    private static func guess(haystack raw: String) -> PantryStorageLocation {
        let haystack = raw.lowercased()
        if containsAny(pantryOverrides, in: haystack) {
            return .pantry
        }
        if containsAny(freezerKeywords, in: haystack) {
            return .freezer
        }
        if containsAny(fridgeKeywords, in: haystack) {
            return .fridge
        }
        // Shelf-stable beverages (water, soda) default to pantry; anything
        // else unclassified is safest as pantry too (not perishable-fridge).
        return .pantry
    }
}
