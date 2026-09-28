//
// GroceryStoreLayout.swift
// Tempo
//
// Store Mode aisle ordering. Nicola shops at Publix, Aldi/Trader Joe's and
// Whole Foods — each hand-authored below in a sensible walk-the-store order
// (produce/perimeter first, frozen and checkout-adjacent staples last), plus
// a generic fallback for anyone who hasn't picked a chain.
//
// LEARNING: the hand-authored order is a starting point, not the truth for
// every store location. `CategoryRankLearning` records the position each
// category was actually ticked in during real trips (see
// `recordTripOrder`), and `resolvedOrder` blends that in once there's enough
// signal — so the list drifts toward how THIS user's THIS store is actually
// laid out. Pure, deterministic, unit-tested; no I/O here (persistence is
// UserSettings.groceryCategoryLearning, a JSON blob — see UserSettings.swift).
//

import Foundation

// MARK: - GroceryStore

enum GroceryStore: String, Codable, CaseIterable, Sendable, Identifiable {
    case publix
    case aldiTraderJoes = "aldi_tj"
    case wholeFoods = "whole_foods"
    /// No chain picked yet, or a store outside the three Nicola shops at.
    case generic

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .publix: "Publix"
        case .aldiTraderJoes: "Aldi / Trader Joe's"
        case .wholeFoods: "Whole Foods"
        case .generic: "Other store"
        }
    }

    /// Case-insensitive match against a free-text store name (as typed by
    /// the user or captured off a receipt), used to bucket
    /// `PantryPriceEntry.store` history into "same store" vs "elsewhere" for
    /// price resolution. `.generic` never matches — it's the fallback, not a
    /// real chain to match against.
    func matches(storeName: String?) -> Bool {
        guard let storeName else {
            return false
        }
        let n = storeName.lowercased()
        switch self {
        case .publix: return n.contains("publix")
        case .aldiTraderJoes: return n.contains("aldi") || n.contains("trader joe")
        case .wholeFoods: return n.contains("whole foods") || n.contains("wholefoods")
        case .generic: return false
        }
    }

    /// Hand-authored aisle-walk order for this chain's grocery categories.
    /// Matches `GroceryListGenerator.category(for:)`'s category set.
    var defaultCategoryOrder: [String] {
        switch self {
        case .publix:
            // Publix: produce at the front, then bakery-adjacent bread/grains,
            // meat/seafood service counters mid-store, dairy along the back
            // wall, frozen before checkout, dry pantry/oils in between.
            ["produce", "grains", "meat", "seafood", "dairy", "frozen", "oils", "pantry"]
        case .aldiTraderJoes:
            // Aldi/TJ's: compact single-aisle-loop stores — produce at the
            // door, pantry/dry goods and oils through the middle (that's
            // most of the floor space), dairy and frozen toward the back,
            // meat/seafood in a short refrigerated run near dairy.
            ["produce", "pantry", "grains", "oils", "meat", "seafood", "dairy", "frozen"]
        case .wholeFoods:
            // Whole Foods: produce first, then a large prepared/bulk pantry
            // section, meat/seafood full-service counters, dairy, grains,
            // oils, frozen last along the back wall.
            ["produce", "pantry", "meat", "seafood", "dairy", "grains", "oils", "frozen"]
        case .generic:
            // Matches GroceryListView's pre-existing default order.
            ["produce", "meat", "seafood", "protein", "dairy", "frozen", "grains", "oils", "pantry"]
        }
    }
}

// MARK: - GroceryStoreLayout

enum GroceryStoreLayout {
    /// Minimum number of recorded trips touching a category before its
    /// learned position overrides the authored default for that category.
    /// One trip could be a fluke (skipped an aisle, doubled back); three
    /// gives a stable-enough signal.
    static let minSamplesToTrust = 3

    // MARK: - Learning

    /// Running average tick-order position per category, plus how many
    /// trips contributed to that average. Codable so it round-trips through
    /// UserSettings.groceryCategoryLearningRaw.
    struct CategoryRankLearning: Codable, Sendable, Equatable {
        var averageRank: [String: Double] = [:]
        var sampleCount: [String: Int] = [:]
    }

    /// Fold one trip's tick order into `learning`. `order` is the sequence of
    /// DISTINCT categories in the order the user first ticked an item in
    /// each — e.g. ["produce", "dairy", "pantry"] means produce got ticked
    /// before any dairy item, which got ticked before any pantry item.
    /// Running-average update: newAvg = (oldAvg·oldCount + newRank) / (oldCount+1).
    static func recordTripOrder(
        _ order: [String],
        into learning: inout CategoryRankLearning
    ) {
        for (rank, category) in order.enumerated() {
            let prevAvg = learning.averageRank[category] ?? Double(rank)
            let prevCount = learning.sampleCount[category] ?? 0
            let newCount = prevCount + 1
            learning.averageRank[category] = (prevAvg * Double(prevCount) + Double(rank)) / Double(newCount)
            learning.sampleCount[category] = newCount
        }
    }

    // MARK: - Resolve

    /// Final aisle order for `presentCategories` at `store`: the authored
    /// default, EXCEPT a category with `minSamplesToTrust`+ recorded trips
    /// sorts by its learned average rank instead. Categories present in the
    /// list but absent from the authored order (a future category we
    /// haven't hand-authored yet) sort to the end, alphabetically among
    /// themselves, exactly like GroceryListView's pre-existing fallback.
    static func resolvedOrder(
        store: GroceryStore,
        presentCategories: [String],
        learning: CategoryRankLearning
    ) -> [String] {
        let authored = store.defaultCategoryOrder
        let authoredIndex = Dictionary(uniqueKeysWithValues: authored.enumerated().map { ($1, Double($0)) })
        let unknownScore = Double(authored.count) + 1

        func score(_ category: String) -> Double {
            if let sampleCount = learning.sampleCount[category], sampleCount >= minSamplesToTrust,
               let avg = learning.averageRank[category]
            {
                return avg
            }
            return authoredIndex[category] ?? unknownScore
        }

        return presentCategories.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb {
                return sa < sb
            }
            return a < b
        }
    }

    // MARK: - Storage location guess

    /// Pre-guess a pantry storage location from a grocery category, for the
    /// Done-Shopping review sheet's default per-item picker. The user can
    /// always override before confirming.
    static func guessedStorageLocation(forCategory category: String) -> PantryStorageLocation {
        switch category {
        case "frozen": .freezer
        case "produce",
             "dairy",
             "meat",
             "seafood": .fridge
        default: .pantry
        }
    }
}
