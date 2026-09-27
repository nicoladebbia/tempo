//
// GroceryPriceEstimatorTests.swift
// Tempo
//
// BUILD item 4, price source order (1) the user's own PantryPriceEntry
// history (same store preferred, most recent, scaled by quantity) and
// GroceryPriceCache's ~30-day refresh window.
//

import Foundation
@testable import Tempo
import XCTest

final class GroceryPriceEstimatorTests: XCTestCase {
    private func entry(
        name: String,
        daysAgo: Double,
        totalUSD: Double,
        quantity: Double,
        unit: PantryUnit,
        store: String? = nil
    ) -> PantryPriceEntry {
        PantryPriceEntry(
            canonicalFoodName: name,
            displayName: name,
            purchaseDate: Date().addingTimeInterval(-daysAgo * 86400),
            totalPaidUSD: totalUSD,
            quantity: quantity,
            unit: unit,
            store: store
        )
    }

    // MARK: - No history

    func testResolveFromHistory_noMatchingHistory_returnsNil() {
        let result = GroceryPriceEstimator.resolveFromHistory(
            canonicalName: "chicken breast", quantity: 2, unit: .pieces, store: .publix, history: []
        )
        XCTAssertNil(result)
    }

    // MARK: - Same-unit ratio scaling

    func testResolveFromHistory_scalesLinearlyByQuantityRatio() {
        // Paid $6 for 1 lb; need 2 lb → $12, cross-checked via grams too
        // (1 lb ≈ 453.6g, so this also exercises the gram-conversion path).
        let history = [entry(name: "ground beef", daysAgo: 1, totalUSD: 6, quantity: 1, unit: .pounds)]
        let result = GroceryPriceEstimator.resolveFromHistory(
            canonicalName: "ground beef", quantity: 2, unit: .pounds, store: .generic, history: history
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.usd ?? -1, 12, accuracy: 0.01)
        XCTAssertEqual(result?.source, .paid)
    }

    func testResolveFromHistory_crossUnitScalingViaGrams() {
        // Paid $6 for 2 lb of ground beef (~907g); need 450g (the
        // naturalPortions "ground beef" pack size) → roughly half that.
        let history = [entry(name: "ground beef", daysAgo: 1, totalUSD: 6, quantity: 2, unit: .pounds)]
        let result = GroceryPriceEstimator.resolveFromHistory(
            canonicalName: "ground beef", quantity: 450, unit: .grams, store: .generic, history: history
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.usd ?? -1, 3, accuracy: 0.2)
    }

    // MARK: - Store preference

    func testResolveFromHistory_prefersSameStoreOverOtherStores() {
        let history = [
            entry(name: "milk", daysAgo: 1, totalUSD: 5, quantity: 1, unit: .liters, store: "Whole Foods"),
            entry(name: "milk", daysAgo: 2, totalUSD: 3, quantity: 1, unit: .liters, store: "Publix"),
        ]
        let result = GroceryPriceEstimator.resolveFromHistory(
            canonicalName: "milk", quantity: 1, unit: .liters, store: .publix, history: history
        )
        XCTAssertEqual(result?.usd ?? -1, 3, accuracy: 0.01, "Publix entry preferred even though it's older")
    }

    func testResolveFromHistory_fallsBackToOtherStoreWhenNoSameStoreHistory() {
        let history = [entry(name: "milk", daysAgo: 1, totalUSD: 5, quantity: 1, unit: .liters, store: "Whole Foods")]
        let result = GroceryPriceEstimator.resolveFromHistory(
            canonicalName: "milk", quantity: 1, unit: .liters, store: .publix, history: history
        )
        XCTAssertEqual(result?.usd ?? -1, 5, accuracy: 0.01)
    }

    func testResolveFromHistory_prefersMostRecentAmongSameStore() {
        let history = [
            entry(name: "milk", daysAgo: 10, totalUSD: 2, quantity: 1, unit: .liters, store: "Publix"),
            entry(name: "milk", daysAgo: 1, totalUSD: 4, quantity: 1, unit: .liters, store: "Publix"),
        ]
        let result = GroceryPriceEstimator.resolveFromHistory(
            canonicalName: "milk", quantity: 1, unit: .liters, store: .publix, history: history
        )
        XCTAssertEqual(result?.usd ?? -1, 4, accuracy: 0.01)
    }

    // MARK: - GroceryPriceCache TTL

    func testPriceCache_freshEntryReturnsPrice() {
        var cache = GroceryPriceCache()
        cache.set(store: .aldiTraderJoes, canonicalName: "eggs", usd: 4.5, date: Date())
        XCTAssertEqual(cache.price(store: .aldiTraderJoes, canonicalName: "eggs"), 4.5)
    }

    func testPriceCache_staleEntryPastMaxAgeReturnsNil() {
        var cache = GroceryPriceCache()
        let old = Date().addingTimeInterval(-40 * 86400) // 40 days ago
        cache.set(store: .aldiTraderJoes, canonicalName: "eggs", usd: 4.5, date: old)
        XCTAssertNil(cache.price(store: .aldiTraderJoes, canonicalName: "eggs", maxAgeDays: 30))
    }

    func testPriceCache_keysAreStoreAndNameScoped() {
        var cache = GroceryPriceCache()
        cache.set(store: .publix, canonicalName: "eggs", usd: 5.0)
        cache.set(store: .aldiTraderJoes, canonicalName: "eggs", usd: 3.0)
        XCTAssertEqual(cache.price(store: .publix, canonicalName: "eggs"), 5.0)
        XCTAssertEqual(cache.price(store: .aldiTraderJoes, canonicalName: "eggs"), 3.0)
    }

    func testPriceCache_persistsThroughUserDefaults() throws {
        let suiteName = "GroceryPriceEstimatorTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        var cache = GroceryPriceCache.load(from: suite)
        cache.set(store: .wholeFoods, canonicalName: "salmon", usd: 12.0)
        cache.save(to: suite)

        let reloaded = GroceryPriceCache.load(from: suite)
        XCTAssertEqual(reloaded.price(store: .wholeFoods, canonicalName: "salmon"), 12.0)
    }
}
