//
// GroceryStoreLayoutTests.swift
// Tempo
//
// BUILD item 2: per-chain aisle order (Publix / Aldi-Trader Joe's / Whole
// Foods / generic) plus the tick-order learning that biases future ordering
// toward how the user's actual store is laid out.
//

@testable import Tempo
import XCTest

final class GroceryStoreLayoutTests: XCTestCase {
    // MARK: - Store matching

    func testGroceryStore_matchesStoreNameCaseInsensitively() {
        XCTAssertTrue(GroceryStore.publix.matches(storeName: "PUBLIX #1234"))
        XCTAssertTrue(GroceryStore.aldiTraderJoes.matches(storeName: "Trader Joe's"))
        XCTAssertTrue(GroceryStore.aldiTraderJoes.matches(storeName: "aldi"))
        XCTAssertTrue(GroceryStore.wholeFoods.matches(storeName: "Whole Foods Market"))
        XCTAssertFalse(GroceryStore.publix.matches(storeName: "Whole Foods Market"))
        XCTAssertFalse(GroceryStore.generic.matches(storeName: "Publix"), "generic never claims a match")
    }

    // MARK: - Default order

    func testDefaultCategoryOrder_isDistinctPerStore() {
        // Not asserting exact orders (those are editorial calls) — just that
        // each store's authored list contains every category exactly once
        // and the three real chains aren't all identical to each other.
        let allCategories: Set = ["produce", "meat", "seafood", "dairy", "frozen", "grains", "oils", "pantry"]
        for store: GroceryStore in [.publix, .aldiTraderJoes, .wholeFoods] {
            XCTAssertEqual(Set(store.defaultCategoryOrder), allCategories, "\(store) must cover every category once")
        }
        XCTAssertNotEqual(GroceryStore.publix.defaultCategoryOrder, GroceryStore.aldiTraderJoes.defaultCategoryOrder)
        XCTAssertNotEqual(GroceryStore.publix.defaultCategoryOrder, GroceryStore.wholeFoods.defaultCategoryOrder)
    }

    // MARK: - resolvedOrder without learning

    func testResolvedOrder_withNoLearning_usesAuthoredDefault() {
        let present = ["pantry", "produce", "dairy"]
        let order = GroceryStoreLayout.resolvedOrder(
            store: .publix, presentCategories: present, learning: .init()
        )
        // Publix authored order: produce, grains, meat, seafood, dairy, frozen, oils, pantry.
        XCTAssertEqual(order, ["produce", "dairy", "pantry"])
    }

    func testResolvedOrder_unknownCategorySortsToEndAlphabetically() {
        let order = GroceryStoreLayout.resolvedOrder(
            store: .publix, presentCategories: ["produce", "zzz-new-category", "aaa-new-category"], learning: .init()
        )
        XCTAssertEqual(order, ["produce", "aaa-new-category", "zzz-new-category"])
    }

    // MARK: - Learning

    func testRecordTripOrder_singleTripSetsAverageRankToObservedPosition() {
        var learning = GroceryStoreLayout.CategoryRankLearning()
        GroceryStoreLayout.recordTripOrder(["dairy", "produce", "pantry"], into: &learning)
        XCTAssertEqual(learning.averageRank["dairy"], 0)
        XCTAssertEqual(learning.averageRank["produce"], 1)
        XCTAssertEqual(learning.averageRank["pantry"], 2)
        XCTAssertEqual(learning.sampleCount["dairy"], 1)
    }

    func testRecordTripOrder_multipleTripsAverage() {
        var learning = GroceryStoreLayout.CategoryRankLearning()
        // Trip 1: dairy ticked first (rank 0). Trip 2: dairy ticked third (rank 2).
        GroceryStoreLayout.recordTripOrder(["dairy", "produce"], into: &learning)
        GroceryStoreLayout.recordTripOrder(["produce", "pantry", "dairy"], into: &learning)
        // dairy: (0*1 + 2) / 2 = 1.0
        XCTAssertEqual(learning.averageRank["dairy"] ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(learning.sampleCount["dairy"], 2)
    }

    func testResolvedOrder_ignoresLearningBelowTrustThreshold() {
        // Authored Publix order puts dairy AFTER produce/grains/meat/seafood.
        // Two trips (below the 3-trip trust threshold) recording dairy FIRST
        // must NOT override the authored order yet.
        var learning = GroceryStoreLayout.CategoryRankLearning()
        GroceryStoreLayout.recordTripOrder(["dairy", "produce"], into: &learning)
        GroceryStoreLayout.recordTripOrder(["dairy", "produce"], into: &learning)
        XCTAssertLessThan(learning.sampleCount["dairy"] ?? 0, GroceryStoreLayout.minSamplesToTrust)

        let order = GroceryStoreLayout.resolvedOrder(store: .publix, presentCategories: ["dairy", "produce"], learning: learning)
        XCTAssertEqual(order, ["produce", "dairy"], "Still authored order below the trust threshold")
    }

    func testResolvedOrder_learningOverridesAuthoredOrderOnceTrusted() {
        // Three trips (meets the threshold) consistently ticking dairy BEFORE
        // produce must flip the resolved order for THIS store, even though
        // Publix's authored default puts produce first.
        var learning = GroceryStoreLayout.CategoryRankLearning()
        for _ in 0 ..< GroceryStoreLayout.minSamplesToTrust {
            GroceryStoreLayout.recordTripOrder(["dairy", "produce"], into: &learning)
        }
        let order = GroceryStoreLayout.resolvedOrder(store: .publix, presentCategories: ["dairy", "produce"], learning: learning)
        XCTAssertEqual(order, ["dairy", "produce"], "Trusted learning overrides the authored default")
    }

    // MARK: - Storage-location guess

    func testGuessedStorageLocation_matchesExpectedCategoryMapping() {
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "frozen"), .freezer)
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "dairy"), .fridge)
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "meat"), .fridge)
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "seafood"), .fridge)
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "produce"), .fridge)
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "pantry"), .pantry)
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "grains"), .pantry)
        XCTAssertEqual(GroceryStoreLayout.guessedStorageLocation(forCategory: "oils"), .pantry)
    }
}
