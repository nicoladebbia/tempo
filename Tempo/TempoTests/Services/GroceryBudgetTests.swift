//
// GroceryBudgetTests.swift
// Tempo
//
// BUILD item 4: the list's estimated total, "approx" labeling, and
// bought-item exclusion from the active count/total.
//

@testable import Tempo
import XCTest

@MainActor
final class GroceryBudgetTests: XCTestCase {
    private func makeList() -> GroceryList {
        GroceryList(weekStartDate: .now)
    }

    func testEstimatedTotalUSD_sumsActiveItemsOnly() {
        let list = makeList()
        let a = GroceryListItem(
            list: list, canonicalFoodName: "rice", displayName: "Rice", quantity: 1, unit: .packs,
            estimatedPriceUSD: 3
        )
        let b = GroceryListItem(
            list: list, canonicalFoodName: "milk", displayName: "Milk", quantity: 1, unit: .liters,
            estimatedPriceUSD: 2
        )
        // Bought — must NOT count toward the active total.
        let c = GroceryListItem(
            list: list, canonicalFoodName: "eggs", displayName: "Eggs", quantity: 1, unit: .pieces,
            isBought: true, estimatedPriceUSD: 100
        )
        list.items = [a, b, c]
        XCTAssertEqual(list.estimatedTotalUSD, 5)
        XCTAssertEqual(list.itemCount, 2, "Bought items excluded from the active count")
    }

    func testEstimatedTotalUSD_unpricedItemsContributeZero() {
        let list = makeList()
        let priced = GroceryListItem(
            list: list,
            canonicalFoodName: "rice",
            displayName: "Rice",
            quantity: 1,
            unit: .packs,
            estimatedPriceUSD: 3
        )
        let unpriced = GroceryListItem(list: list, canonicalFoodName: "milk", displayName: "Milk", quantity: 1, unit: .liters)
        list.items = [priced, unpriced]
        XCTAssertEqual(list.estimatedTotalUSD, 3)
        XCTAssertTrue(list.hasUnresolvedPrices)
    }

    func testHasUnresolvedPrices_falseWhenEveryActiveItemPriced() {
        let list = makeList()
        let a = GroceryListItem(list: list, canonicalFoodName: "rice", displayName: "Rice", quantity: 1, unit: .packs, estimatedPriceUSD: 3)
        list.items = [a]
        XCTAssertFalse(list.hasUnresolvedPrices)
    }

    func testTotalIsApproximate_trueWhenAnyPricedItemIsAnEstimate() {
        let list = makeList()
        let paid = GroceryListItem(
            list: list, canonicalFoodName: "rice", displayName: "Rice", quantity: 1, unit: .packs,
            estimatedPriceUSD: 3, priceSource: .paid
        )
        let estimated = GroceryListItem(
            list: list, canonicalFoodName: "milk", displayName: "Milk", quantity: 1, unit: .liters,
            estimatedPriceUSD: 2, priceSource: .estimate
        )
        list.items = [paid, estimated]
        XCTAssertTrue(list.totalIsApproximate)
    }

    func testTotalIsApproximate_falseWhenAllPricedItemsArePaid() {
        let list = makeList()
        let a = GroceryListItem(
            list: list, canonicalFoodName: "rice", displayName: "Rice", quantity: 1, unit: .packs,
            estimatedPriceUSD: 3, priceSource: .paid
        )
        list.items = [a]
        XCTAssertFalse(list.totalIsApproximate)
    }

    func testActiveAndBoughtItemsPartitionCorrectly() {
        let list = makeList()
        let active = GroceryListItem(list: list, canonicalFoodName: "rice", displayName: "Rice", quantity: 1, unit: .packs)
        let bought = GroceryListItem(list: list, canonicalFoodName: "milk", displayName: "Milk", quantity: 1, unit: .liters, isBought: true)
        list.items = [active, bought]
        XCTAssertEqual(list.activeItems.map(\.canonicalFoodName), ["rice"])
        XCTAssertEqual(list.boughtItems.map(\.canonicalFoodName), ["milk"])
    }
}
