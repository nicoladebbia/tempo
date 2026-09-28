//
// ShelfLifeEstimator.swift
// Tempo
//
// Hand-authored shelf-life table: how many days a food keeps in each storage
// location. Drives the auto-expiry feature — every pantry add/merge/set path
// (manual, voice, receipt, grocery-confirm) sets an estimated `useBy` when
// none is given, so the dead expiry UI (PantryView's "Expiring soon",
// UseUpSoonCard, the plan's FIFO prompt block) finally has data to show.
//
// Pure, synchronous, deterministic — no AI, no I/O. Matched by SUBSTRING
// against a food's canonical name (same matching style as
// `LiveReceiptService.defaultLocation`). When nothing in the table matches,
// callers get a conservative generic fallback by storage location and a
// `matched == false` flag so they know the estimate is a guess worth
// refining with `ShelfLifeAIEstimating` (see ShelfLifeAIEstimator.swift).
//

import Foundation

// MARK: - ShelfLifeEstimator

enum ShelfLifeEstimator {
    // MARK: - Rule

    /// Days-to-spoil per storage location for one food keyword. Any field
    /// left `nil` means "this location doesn't really apply" (e.g. raw
    /// chicken has no sensible `cupboard` entry) — `days(for:)` falls back
    /// to the closest sensible field rather than surfacing `nil`.
    struct Rule {
        var fridge: Int?
        var freezer: Int?
        var pantry: Int?
        var cupboard: Int?

        func days(for location: PantryStorageLocation) -> Int? {
            switch location {
            case .fridge: fridge ?? pantry ?? cupboard ?? freezer
            case .freezer: freezer ?? fridge.map { max($0 * 20, 60) } ?? pantry ?? cupboard
            case .pantry: pantry ?? cupboard ?? fridge
            case .cupboard: cupboard ?? pantry ?? fridge
            }
        }
    }

    /// Generic fallback when no keyword matches — conservative, biased
    /// toward "check before you use it" rather than false confidence.
    static let genericFallbackDays: [PantryStorageLocation: Int] = [
        .fridge: 7,
        .freezer: 180,
        .pantry: 180,
        .cupboard: 270,
    ]

    /// Cooked / prepped leftovers — the cook/prep event resets the clock
    /// regardless of what the raw ingredient's own rule would say.
    static let cookedFridgeDays = 4
    static let cookedFreezerDays = 90

    // MARK: - Table

    /// Keyword → Rule. Order doesn't matter; the FIRST substring match wins
    /// (longer/more specific keywords are listed first so e.g. "ground beef"
    /// matches before a hypothetical generic "beef").
    static let table: [(keyword: String, rule: Rule)] = [
        // Raw poultry / meat / fish — short fridge life, long freezer life.
        ("chicken breast", Rule(fridge: 2, freezer: 270)),
        ("chicken thigh", Rule(fridge: 2, freezer: 270)),
        ("chicken", Rule(fridge: 2, freezer: 270)),
        ("turkey", Rule(fridge: 2, freezer: 270)),
        ("ground beef", Rule(fridge: 2, freezer: 120)),
        ("ground turkey", Rule(fridge: 2, freezer: 120)),
        ("ground pork", Rule(fridge: 2, freezer: 120)),
        ("beef steak", Rule(fridge: 4, freezer: 270)),
        ("steak", Rule(fridge: 4, freezer: 270)),
        ("pork chop", Rule(fridge: 4, freezer: 180)),
        ("pork", Rule(fridge: 4, freezer: 180)),
        ("bacon", Rule(fridge: 7, freezer: 30)),
        ("sausage", Rule(fridge: 3, freezer: 60)),
        ("salmon", Rule(fridge: 2, freezer: 90)),
        ("tuna steak", Rule(fridge: 2, freezer: 90)),
        ("shrimp", Rule(fridge: 2, freezer: 180)),
        ("fish", Rule(fridge: 2, freezer: 180)),
        ("tuna canned", Rule(pantry: 1095, cupboard: 1095)),
        ("deli meat", Rule(fridge: 5)),
        ("ham", Rule(fridge: 5, freezer: 60)),

        // Dairy / eggs.
        ("milk", Rule(fridge: 7)),
        ("greek yogurt", Rule(fridge: 14)),
        ("yogurt", Rule(fridge: 14)),
        ("cottage cheese", Rule(fridge: 10)),
        ("cream cheese", Rule(fridge: 14)),
        ("shredded cheese", Rule(fridge: 21)),
        ("cheese", Rule(fridge: 21, freezer: 180)),
        ("butter", Rule(fridge: 60, freezer: 270)),
        ("eggs", Rule(fridge: 28)),
        ("egg", Rule(fridge: 28)),
        ("heavy cream", Rule(fridge: 10)),
        ("sour cream", Rule(fridge: 14)),
        ("tofu", Rule(fridge: 7, freezer: 150)),

        // Produce — fridge unless noted, no meaningful freezer default.
        ("spinach", Rule(fridge: 5, freezer: 240)),
        ("lettuce", Rule(fridge: 7)),
        ("asparagus", Rule(fridge: 4)),
        ("broccoli", Rule(fridge: 7, freezer: 240)),
        ("berries", Rule(fridge: 5, freezer: 240)),
        ("strawberr", Rule(fridge: 5, freezer: 240)),
        ("grapes", Rule(fridge: 10)),
        ("banana", Rule(fridge: 7, pantry: 5)),
        ("apple", Rule(fridge: 30, pantry: 14)),
        ("avocado", Rule(fridge: 7, pantry: 5)),
        ("tomato", Rule(fridge: 7, pantry: 5)),
        ("cucumber", Rule(fridge: 7)),
        ("bell pepper", Rule(fridge: 10)),
        ("carrot", Rule(fridge: 21)),
        ("celery", Rule(fridge: 14)),
        ("onion", Rule(pantry: 30, cupboard: 30)),
        ("garlic", Rule(pantry: 90, cupboard: 90)),
        ("potato", Rule(pantry: 30, cupboard: 30)),
        ("sweet potato", Rule(pantry: 21, cupboard: 21)),
        ("mushroom", Rule(fridge: 7)),

        // Bread / grains / dry goods — pantry/cupboard shelf-stable.
        ("bread", Rule(freezer: 90, pantry: 5)),
        ("rice", Rule(pantry: 730, cupboard: 730)),
        ("rolled oats", Rule(pantry: 365, cupboard: 365)),
        ("oatmeal", Rule(pantry: 365, cupboard: 365)),
        ("pasta", Rule(pantry: 730, cupboard: 730)),
        ("quinoa", Rule(pantry: 730, cupboard: 730)),
        ("flour", Rule(pantry: 240, cupboard: 240)),
        ("sugar", Rule(pantry: 730, cupboard: 730)),
        ("cereal", Rule(pantry: 240, cupboard: 240)),
        ("canned", Rule(pantry: 1095, cupboard: 1095)),
        ("beans canned", Rule(pantry: 1095, cupboard: 1095)),

        // Condiments / oils / sauces (also staples — still worth an estimate
        // for the odd case a bottle ends up in a quantitied pantry row).
        ("olive oil", Rule(pantry: 545, cupboard: 545)),
        ("oil", Rule(pantry: 365, cupboard: 365)),
        ("ketchup", Rule(fridge: 180, pantry: 365)),
        ("mustard", Rule(fridge: 365, pantry: 365)),
        ("mayo", Rule(fridge: 60, pantry: 60)),
        ("soy sauce", Rule(pantry: 730, cupboard: 730)),
        ("hot sauce", Rule(pantry: 730, cupboard: 730)),
        ("salsa", Rule(fridge: 30, pantry: 365)),
        ("jam", Rule(fridge: 180, pantry: 365)),
        ("honey", Rule(pantry: 3650, cupboard: 3650)),
        ("peanut butter", Rule(pantry: 270, cupboard: 270)),
    ]

    // MARK: - Estimate

    /// Estimated days-to-spoil for a food + storage location. Cooked/prepped
    /// leftovers always use the cooked-food clock regardless of the raw
    /// ingredient's own rule. Returns `matched == false` when the table has
    /// no keyword for this food, so the caller knows the generic fallback
    /// was used and may want to refine it with `ShelfLifeAIEstimating`.
    static func estimate(
        canonicalName: String,
        storageLocation: PantryStorageLocation,
        isCooked: Bool = false,
        isPrepped: Bool = false
    ) -> (days: Int, matched: Bool) {
        if isCooked || isPrepped {
            let days = storageLocation == .freezer ? cookedFreezerDays : cookedFridgeDays
            return (days, true)
        }
        let name = canonicalName.lowercased()
        for (keyword, rule) in table where name.contains(keyword) {
            if let days = rule.days(for: storageLocation) {
                return (days, true)
            }
        }
        return (genericFallbackDays[storageLocation] ?? 180, false)
    }

    /// Convenience: the actual `useBy` date given a purchase/base date.
    @discardableResult
    static func useByDate(
        from baseDate: Date,
        canonicalName: String,
        storageLocation: PantryStorageLocation,
        isCooked: Bool = false,
        isPrepped: Bool = false
    ) -> Date {
        let (days, _) = estimate(
            canonicalName: canonicalName,
            storageLocation: storageLocation,
            isCooked: isCooked,
            isPrepped: isPrepped
        )
        return Calendar.current.date(byAdding: .day, value: days, to: baseDate) ?? baseDate
    }

    /// `true` when the table has no dedicated keyword for this food (the
    /// generic fallback was used) — a candidate for AI refinement.
    static func isUnmatched(canonicalName: String, storageLocation: PantryStorageLocation) -> Bool {
        !estimate(canonicalName: canonicalName, storageLocation: storageLocation).matched
    }
}
