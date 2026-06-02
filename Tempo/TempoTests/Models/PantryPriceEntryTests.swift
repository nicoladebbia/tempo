//
// PantryPriceEntryTests.swift
// Tempo
//
// Pantry price-history guard. Price entries are keyed by canonicalFoodName
// (stable food identity), one INSERT per purchase, so a food's price time
// series survives the PantryItem being consumed/archived and re-bought. These
// pin: per-purchase rows accumulate (restock never overwrites), the history
// survives item archival/deletion (denormalized key, no cascade), and the
// per-unit derivation is correct for "savings over time".
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PantryPriceEntryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PantryPriceEntry.self, PantryItem.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testPerUnitPriceDerivation() {
        let entry = PantryPriceEntry(
            canonicalFoodName: "eggs",
            displayName: "Eggs",
            purchaseDate: day(2026, 5, 1),
            totalPaidUSD: 3.60,
            quantity: 12,
            unit: .pieces
        )
        XCTAssertEqual(entry.pricePerUnitUSD ?? 0, 0.30, accuracy: 0.0001)
    }

    func testPerUnitNilWhenQuantityZero() {
        let entry = PantryPriceEntry(
            canonicalFoodName: "eggs", displayName: "Eggs",
            purchaseDate: Date(), totalPaidUSD: 3.60, quantity: 0, unit: .pieces
        )
        XCTAssertNil(entry.pricePerUnitUSD, "No divide-by-zero garbage")
    }

    func testCanonicalNameLowercasedOnWrite() {
        let entry = PantryPriceEntry(
            canonicalFoodName: "Greek Yogurt", displayName: "Greek Yogurt",
            purchaseDate: Date(), totalPaidUSD: 5, quantity: 1, unit: .pieces
        )
        XCTAssertEqual(entry.canonicalFoodName, "greek yogurt")
    }

    func testHistoryAccumulatesPerPurchase() throws {
        // Two purchases of the same food at different prices/dates.
        context.insert(PantryPriceEntry(
            canonicalFoodName: "eggs", displayName: "Eggs",
            purchaseDate: day(2026, 5, 1), totalPaidUSD: 3.20, quantity: 12, unit: .pieces
        ))
        context.insert(PantryPriceEntry(
            canonicalFoodName: "eggs", displayName: "Eggs",
            purchaseDate: day(2026, 5, 20), totalPaidUSD: 3.60, quantity: 12, unit: .pieces
        ))
        try context.save()

        let all = try context.fetch(FetchDescriptor<PantryPriceEntry>(
            predicate: #Predicate { $0.canonicalFoodName == "eggs" }
        ))
        XCTAssertEqual(all.count, 2, "Each purchase is its own row — restock never overwrites")
        // The price changed over time — the whole point of the history.
        let prices = Set(all.map(\.totalPaidUSD))
        XCTAssertEqual(prices, [3.20, 3.60])
    }

    func testHistorySurvivesPantryItemDeletion() throws {
        // Buy eggs (item + price entry), then consume/delete the item.
        let item = PantryItem(
            canonicalName: "eggs", displayName: "Eggs",
            quantity: 12, unit: .pieces, storageLocation: .fridge
        )
        context.insert(item)
        context.insert(PantryPriceEntry(
            canonicalFoodName: "eggs", displayName: "Eggs",
            purchaseDate: day(2026, 5, 1), totalPaidUSD: 3.20, quantity: 12, unit: .pieces,
            sourcePantryItemID: item.id
        ))
        try context.save()

        // The eggs are eaten — the PantryItem is deleted.
        context.delete(item)
        try context.save()

        // Price history must remain — it's keyed by food, not the item.
        let surviving = try context.fetch(FetchDescriptor<PantryPriceEntry>(
            predicate: #Predicate { $0.canonicalFoodName == "eggs" }
        ))
        XCTAssertEqual(surviving.count, 1,
                       "Price history survives the PantryItem being consumed/deleted")
    }
}
