//
// GroceryPriceEstimator.swift
// Tempo
//
// Price resolution order (BUILD item 4): (1) the user's own PantryPriceEntry
// history for that canonical food — same store preferred, most recent,
// scaled to the needed quantity; (2) a locally cached AI estimate (refreshed
// every ~30 days); (3) nothing — the caller (GroceryPriceAIService) then
// does ONE batched AI call for everything still unresolved. Pure/static so
// it's fully unit-testable without SwiftData or the network.
//

import Foundation

// MARK: - GroceryPriceResolution

struct GroceryPriceResolution: Equatable {
    let usd: Double
    let source: GroceryPriceSource
}

// MARK: - GroceryPriceEstimator

enum GroceryPriceEstimator {
    /// Resolve a line-item price from the user's own purchase history.
    /// Returns nil when no history exists for this food — caller falls
    /// through to the cache, then the AI estimator.
    ///
    /// Scaling: prefers converting both the historical purchase and the
    /// needed quantity to grams (via `PantryUnit.gramsApprox`, the same
    /// cross-unit path the generator/reapply logic already uses) so "1 lb of
    /// chicken for $6" correctly prices "900g of chicken" even though the
    /// units differ. Falls back to a same-unit ratio when gram conversion
    /// isn't available (e.g. a food with no naturalPortions entry).
    static func resolveFromHistory(
        canonicalName: String,
        quantity: Double,
        unit: PantryUnit,
        store: GroceryStore,
        history: [PantryPriceEntry]
    ) -> GroceryPriceResolution? {
        let name = canonicalName.lowercased()
        let candidates = history.filter { $0.canonicalFoodName == name && $0.totalPaidUSD > 0 && $0.quantity > 0 }
        guard !candidates.isEmpty else {
            return nil
        }

        // Prefer entries from the SAME chain; fall back to any store when
        // there's no same-store history yet.
        let sameStore = candidates.filter { store.matches(storeName: $0.store) }
        let pool = sameStore.isEmpty ? candidates : sameStore

        guard let best = pool.max(by: { $0.purchaseDate < $1.purchaseDate }) else {
            return nil
        }

        if let entryGrams = best.unit.gramsApprox(quantity: best.quantity, foodName: name), entryGrams > 0,
           let targetGrams = unit.gramsApprox(quantity: quantity, foodName: name)
        {
            let perGram = best.totalPaidUSD / entryGrams
            return GroceryPriceResolution(usd: max(0, perGram * targetGrams), source: .paid)
        }

        // Fallback: ratio in the entry's own unit (assumes comparable units;
        // better than no price at all, and still labeled "paid" since it's
        // still derived from a real receipt/purchase, not a guess).
        let ratio = quantity / best.quantity
        return GroceryPriceResolution(usd: max(0, best.totalPaidUSD * ratio), source: .paid)
    }
}

// MARK: - GroceryPriceCache

/// Local cache of AI-estimated prices, keyed by store + canonical food name,
/// so the same batched Haiku call isn't re-paid every time the list
/// re-renders. Refreshes every `maxAgeDays` (~30) per BUILD item 4. Backed by
/// `UserDefaults` (a plain JSON blob) rather than SwiftData — this is
/// disposable, re-derivable data, not a record worth a schema migration.
struct GroceryPriceCache: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let usd: Double
        let date: Date
    }

    var entries: [String: Entry] = [:]

    static func key(store: GroceryStore, canonicalName: String) -> String {
        "\(store.rawValue)|\(canonicalName.lowercased())"
    }

    /// Cached price for this store+food, or nil if absent or stale.
    func price(store: GroceryStore, canonicalName: String, maxAgeDays: Int = 30, now: Date = Date()) -> Double? {
        guard let entry = entries[Self.key(store: store, canonicalName: canonicalName)] else {
            return nil
        }
        let ageDays = Calendar.current.dateComponents([.day], from: entry.date, to: now).day ?? Int.max
        guard ageDays <= maxAgeDays else {
            return nil
        }
        return entry.usd
    }

    mutating func set(store: GroceryStore, canonicalName: String, usd: Double, date: Date = Date()) {
        entries[Self.key(store: store, canonicalName: canonicalName)] = Entry(usd: usd, date: date)
    }

    // MARK: - Persistence

    private static let defaultsKey = "tempo.grocery.price_cache.v1"

    static func load(from defaults: UserDefaults = .standard) -> GroceryPriceCache {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(GroceryPriceCache.self, from: data)
        else {
            return GroceryPriceCache()
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
