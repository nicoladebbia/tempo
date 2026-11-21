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
        // "tomatoes" must find "tomato" and "peppers" find "pepper": the plural
        // tolerance below only covers a plural haystack, so try both forms.
        let single = singular(keyword)
        if single != keyword.lowercased(), matchesWord(single, in: haystack) {
            return true
        }
        return matchesWord(keyword, in: haystack)
    }

    /// Simple English singular of the last word ("tomatoes" -> "tomato",
    /// "berries" -> "berry", "peppers" -> "pepper"); leaves "glass", "hummus",
    /// and short words alone.
    static func singular(_ phrase: String) -> String {
        let p = phrase.lowercased().trimmingCharacters(in: .whitespaces)
        guard p.count > 3 else {
            return p
        }
        if p.hasSuffix("ies") {
            return String(p.dropLast(3)) + "y"
        }
        if p.hasSuffix("oes") {
            return String(p.dropLast(2))
        }
        for suffix in ["sses", "shes", "ches", "xes"] where p.hasSuffix(suffix) {
            return String(p.dropLast(2))
        }
        if p.hasSuffix("s"), !p.hasSuffix("ss"), !p.hasSuffix("us") {
            return String(p.dropLast())
        }
        return p
    }

    private static func matchesWord(_ keyword: String, in haystack: String) -> Bool {
        // "egg noodles" is pasta, not eggs.
        if keyword == "egg" || keyword == "eggs",
           haystack.range(of: "\\begg\\s+(?:noodle|pasta)", options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        let k = keyword.lowercased()
        // Compound stems may carry a leading word ("strawberries", "catfish");
        // "oat" may carry a trailing one ("oatmeal"). Risky short words
        // (ice, egg) stay exact whole-word.
        let lead = ["berries", "berry", "fish"].contains(k) ? "\\w*" : ""
        let tail = k == "oat" ? "\\w*" : "(?:s|es)?"
        let pattern = "\\b" + lead + NSRegularExpression.escapedPattern(for: keyword) + tail + "\\b"
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
