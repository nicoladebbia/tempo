//
// GroceryRound1Tests.swift
// Tempo
//
// Round 1 (Lane C): the shopping list is right.
//  - pantry is subtracted exactly once, however often it syncs
//  - only still-planned meals from today on are shopped for
//  - regenerate updates the list IN PLACE (share link + shopper ticks survive)
//  - labels never double the quantity; storage/category use whole words
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GroceryRound1Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var grocery: LocalGroceryListService!
    private var pantry: LocalPantryService!
    private let cal = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
        grocery = LocalGroceryListService(modelContext: context)
        pantry = LocalPantryService(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil; context = nil; grocery = nil; pantry = nil
        try await super.tearDown()
    }

    private func today() -> Date {
        cal.startOfDay(for: Date())
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today())!
    }

    @discardableResult
    private func meal(
        in plan: WeeklyMealPlan, number: Int, dayOffset: Int = 0,
        status: MealStatus = .planned, _ foods: [(String, Double)]
    ) -> PlannedMeal {
        let m = PlannedMeal(
            dayDate: day(dayOffset), mealNumber: number, mealName: "Meal \(number)", scheduledTime: "12:00",
            foods: foods.map { PlannedFood(name: $0.0, quantityGrams: $0.1, calories: 0, proteinG: 0, carbsG: 0, fatG: 0) },
            status: status, mealPlan: plan
        )
        context.insert(m)
        return m
    }

    private func plan() -> WeeklyMealPlan {
        let p = WeeklyMealPlan(startDate: today(), endDate: day(7))
        context.insert(p)
        return p
    }

    private func addPantry(_ name: String, _ qty: Double, _ unit: PantryUnit) throws {
        _ = try pantry.mergeOrCreate(
            rawName: name, quantity: qty, unit: unit, storageLocation: .pantry,
            purchaseDate: nil, purchaseSource: .manual, sourceReceiptLineItemID: nil
        )
    }

    // MARK: - 1. Pantry subtracted once

    func testSyncNeverSubtractsPantryTwice() throws {
        let p = plan()
        meal(in: p, number: 1, [("Oats", 500)])
        try addPantry("Oats", 300, .grams)
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let before = try XCTUnwrap(list.items?.first { $0.canonicalFoodName == "oats" })
        let qtyAfterGenerate = before.quantity, unitAfterGenerate = before.unit

        // Sync 3 times (pantry add/set, "Sync with Pantry", receipt ingest).
        for _ in 0 ..< 3 {
            XCTAssertEqual(try grocery.reapplyPantry(pantry), 0, "200 g still needed → row must not be deleted")
        }
        let after = try XCTUnwrap(list.items?.first { $0.canonicalFoodName == "oats" })
        XCTAssertEqual(after.quantity, qtyAfterGenerate)
        XCTAssertEqual(after.unit, unitAfterGenerate)
    }

    func testSyncDoesNotShrinkRoundedPurchaseUnits() throws {
        // 195 g carrots = 3 medium; with 150 g on hand the list needs 45 g → 1.
        // Re-syncing must keep that 1, and must not apply the pantry again.
        let p = plan()
        meal(in: p, number: 1, [("Carrot", 195)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        XCTAssertEqual(list.items?.first?.quantity, 3)
        try addPantry("Carrot", 150, .grams)
        try grocery.reapplyPantry(pantry)
        let carrots = try XCTUnwrap(list.items?.first)
        XCTAssertEqual(carrots.quantity, 1)
        try grocery.reapplyPantry(pantry)
        XCTAssertEqual(carrots.quantity, 1)
        XCTAssertEqual(carrots.displayName, "1 medium carrot", "Label follows the quantity")
    }

    func testSyncLeavesManualItemsAlone() throws {
        let p = plan()
        meal(in: p, number: 1, [("Oats", 500)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let manual = try grocery.addItem(name: "Oats", quantity: 2, unit: .packs)
        XCTAssertTrue(manual.isManual)
        try addPantry("Oats", 5000, .grams)
        try grocery.reapplyPantry(pantry)
        XCTAssertTrue(list.items?.contains { $0.id == manual.id } == true, "User-typed item survives a pantry sync")
        XCTAssertEqual(manual.quantity, 2)
    }

    func testSyncRemovesPantryRestockRowOnceBackInStock() throws {
        let p = plan()
        meal(in: p, number: 1, [("Salmon", 200)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let restock = try PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: "rice", displayName: "Rice", quantity: 1, unit: .packs, modelContext: context
        )
        XCTAssertTrue(restock.isPantryRestock)
        try addPantry("Rice", 1, .packs)
        let removed = try grocery.reapplyPantry(pantry)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(list.items?.contains { $0.canonicalFoodName == "rice" } == true)
    }

    func testFullyCoveredRowIsRemovedAndNeededRowGrowsBack() throws {
        let p = plan()
        meal(in: p, number: 1, [("Oats", 500), ("Salmon", 340)])
        try addPantry("Oats", 1000, .grams)
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        XCTAssertFalse(list.items?.contains { $0.canonicalFoodName == "oats" } == true)
        // Salmon row, pantry changes → recomputed from the plan, not shrunk twice.
        let salmon = try XCTUnwrap(list.items?.first { $0.canonicalFoodName == "salmon" })
        let original = salmon.quantity
        try addPantry("Salmon", 170, .grams)
        try grocery.reapplyPantry(pantry)
        XCTAssertLessThan(salmon.quantity, original)
        try pantry.archive(try XCTUnwrap(pantry.find(canonicalName: "salmon")))
        try grocery.reapplyPantry(pantry)
        XCTAssertEqual(salmon.quantity, original, "Pantry change in the other direction grows the row back")
    }

    func testRowRemovedByStockComesBackWhenPantryIsEmptied() throws {
        let p = plan()
        meal(in: p, number: 1, [("Oats", 500), ("Salmon", 340)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        XCTAssertTrue(list.items?.contains { $0.canonicalFoodName == "oats" } == true)
        try addPantry("Oats", 1000, .grams)
        XCTAssertEqual(try grocery.reapplyPantry(pantry), 1, "Fully covered → removed")
        XCTAssertFalse(list.items?.contains { $0.canonicalFoodName == "oats" } == true)

        try pantry.archive(try XCTUnwrap(pantry.find(canonicalName: "oats")))
        try grocery.reapplyPantry(pantry)
        XCTAssertEqual(list.items?.filter { $0.canonicalFoodName == "oats" }.count, 1, "Need is back → row is back, once")
        try grocery.reapplyPantry(pantry)
        XCTAssertEqual(list.items?.filter { $0.canonicalFoodName == "oats" }.count, 1, "Re-sync never duplicates it")
    }

    func testDeletedRowStaysDeletedAcrossPantrySyncs() throws {
        let p = plan()
        meal(in: p, number: 1, [("Oats", 500), ("Salmon", 340)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        try grocery.deleteItem(try XCTUnwrap(list.items?.first { $0.canonicalFoodName == "salmon" }))
        try addPantry("Oats", 100, .grams)
        try grocery.reapplyPantry(pantry)
        XCTAssertFalse(list.items?.contains { $0.canonicalFoodName == "salmon" } == true, "User removed it — stays removed")
        // A fresh Generate starts over.
        _ = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        XCTAssertTrue(list.items?.contains { $0.canonicalFoodName == "salmon" } == true)
    }

    func testReplacedPlanNeverAddsRows() throws {
        let p = plan()
        meal(in: p, number: 1, [("Oats", 500), ("Salmon", 340)])
        try addPantry("Oats", 1000, .grams)
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        XCTAssertFalse(list.items?.contains { $0.canonicalFoodName == "oats" } == true)
        p.isActive = false
        try pantry.archive(try XCTUnwrap(pantry.find(canonicalName: "oats")))
        try grocery.reapplyPantry(pantry)
        XCTAssertFalse(list.items?.contains { $0.canonicalFoodName == "oats" } == true)
    }

    func testCapitalisedPantryNameStillNets() throws {
        let p = plan()
        meal(in: p, number: 1, [("Oats", 500)])
        let row = PantryItem(canonicalName: "Oats", displayName: "Oats", quantity: 1000, unit: .grams, storageLocation: .pantry)
        let entries = GroceryListGenerator.generate(from: .init(
            mealPlan: p, pantry: [row], weekStartDate: today(), onOrAfter: today()
        ))
        XCTAssertFalse(entries.contains { $0.canonicalName == "oats" && $0.quantity > 0 })
    }

    // MARK: - 3. Only still-planned meals from today

    func testGeneratorSkipsEatenSkippedAndPastMeals() {
        let p = plan()
        meal(in: p, number: 1, dayOffset: -2, [("Rice", 1000)]) // past
        meal(in: p, number: 2, dayOffset: 0, status: .eaten, [("Chicken Breast", 500)])
        meal(in: p, number: 3, dayOffset: 0, status: .skipped, [("Oats", 500)])
        meal(in: p, number: 4, dayOffset: 1, [("Salmon", 200)])
        let names = GroceryListGenerator.generate(from: .init(
            mealPlan: p, pantry: [], weekStartDate: today(), onOrAfter: today()
        )).map(\.canonicalName)
        XCTAssertEqual(names, ["salmon"])
    }

    func testGeneratorWithoutDateStillSkipsEatenMeals() {
        let p = plan()
        meal(in: p, number: 1, status: .eaten, [("Rice", 1000)])
        meal(in: p, number: 2, [("Salmon", 200)])
        let names = GroceryListGenerator.generate(from: .init(mealPlan: p, pantry: [], weekStartDate: today())).map(\.canonicalName)
        XCTAssertEqual(names, ["salmon"])
    }

    func testUpcomingWeekCountsAllItsMeals() {
        let p = WeeklyMealPlan(startDate: day(7), endDate: day(14))
        context.insert(p)
        meal(in: p, number: 1, dayOffset: 7, [("Rice", 300)])
        meal(in: p, number: 2, dayOffset: 13, [("Salmon", 200)])
        let names = Set(GroceryListGenerator.generate(from: .init(
            mealPlan: p, pantry: [], weekStartDate: day(7), onOrAfter: today()
        )).map(\.canonicalName))
        XCTAssertEqual(names, ["rice", "salmon"])
    }

    func testEatingAMealShrinksListOnNextSync() throws {
        let p = plan()
        let m1 = meal(in: p, number: 1, [("Salmon", 340)])
        meal(in: p, number: 2, dayOffset: 1, [("Oats", 500)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        XCTAssertTrue(list.items?.contains { $0.canonicalFoodName == "salmon" } == true)
        m1.status = .eaten
        try context.save()
        try grocery.reapplyPantry(pantry)
        XCTAssertFalse(list.items?.contains { $0.canonicalFoodName == "salmon" } == true, "Eaten meal no longer needs shopping")
        XCTAssertTrue(list.items?.contains { $0.canonicalFoodName == "oats" } == true)
    }

    // MARK: - 3b. Regenerate updates in place

    func testRegenerateKeepsListIDItemIDsAndShare() throws {
        let p = plan()
        meal(in: p, number: 1, [("Salmon", 340), ("Oats", 500)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let listID = list.id
        let salmon = try XCTUnwrap(list.items?.first { $0.canonicalFoodName == "salmon" })
        let salmonID = salmon.id
        try grocery.toggleChecked(salmon)
        let manual = try grocery.addItem(name: "Olive Oil", quantity: 1, unit: .bottles)
        context.insert(GroceryShare(listID: listID, token: "tok", url: "https://x/g/tok", expiresAt: Date().addingTimeInterval(86400)))
        try context.save()

        meal(in: p, number: 2, dayOffset: 1, [("Salmon", 170)])
        let again = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())

        XCTAssertEqual(again.id, listID, "Same list → the share link keeps working")
        let all = try context.fetch(FetchDescriptor<GroceryList>())
        XCTAssertEqual(all.count, 1)
        let salmon2 = try XCTUnwrap(again.items?.first { $0.canonicalFoodName == "salmon" })
        XCTAssertEqual(salmon2.id, salmonID, "Same item id → shopper ticks stay matched")
        XCTAssertTrue(salmon2.isChecked)
        XCTAssertGreaterThan(salmon2.quantity, salmon.quantity - 0.001)
        XCTAssertTrue(again.items?.contains { $0.id == manual.id } == true, "Manual items survive")
        let shares = try context.fetch(FetchDescriptor<GroceryShare>())
        XCTAssertEqual(shares.first?.listID, again.id)
    }

    func testRegenerateDropsRowsNoLongerNeeded() throws {
        let p = plan()
        let m = meal(in: p, number: 1, [("Salmon", 340)])
        meal(in: p, number: 2, [("Oats", 500)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        m.status = .skipped
        let again = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        XCTAssertEqual(again.id, list.id)
        XCTAssertEqual(again.items?.map(\.canonicalFoodName), ["oats"])
    }

    func testBoughtRowKeptAsRecordAndNewShortfallGetsFreshRow() throws {
        let p = plan()
        meal(in: p, number: 1, [("Salmon", 340)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let salmon = try XCTUnwrap(list.items?.first)
        try grocery.markBought([salmon], boughtAt: Date())
        let again = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let rows = again.items?.filter { $0.canonicalFoodName == "salmon" } ?? []
        XCTAssertEqual(rows.filter(\.isBought).count, 1, "Trip record kept")
        XCTAssertEqual(rows.filter { !$0.isBought }.count, 1, "Still-needed amount is a fresh active row")
    }

    // MARK: - 6. labels / categories

    func testLabelsNeverDoubleTheQuantity() throws {
        let p = plan()
        meal(in: p, number: 1, [("Carrot", 195), ("Salmon", 200)])
        let list = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let carrots = try XCTUnwrap(list.items?.first { $0.canonicalFoodName.contains("carrot") })
        XCTAssertEqual(carrots.fullLabel, "3 medium carrots")
        XCTAssertFalse(carrots.quantityFreeName.first?.isNumber ?? true, "Instacart/share-page name has no amount")
        XCTAssertFalse(GroceryShareTextFormatter.text(for: list).contains("pcs 3 medium"))
        XCTAssertTrue(GroceryShareTextFormatter.text(for: list).contains("☐ 3 medium carrots"))
        XCTAssertEqual(LocalGroceryListService.reminderTitle(name: "3 medium carrots", quantity: 3, unit: .pieces), "3 medium carrots")
        XCTAssertEqual(LocalGroceryListService.reminderTitle(name: "Oats", quantity: 1.5, unit: .kilograms), "Oats — 1.5kg")
    }

    func testManualAddCanonicalisesAndPicksAisle() throws {
        let p = plan()
        meal(in: p, number: 1, [("Salmon", 200)])
        _ = try grocery.generate(from: p, pantry: pantry, weekStartDate: today())
        let apple = try grocery.addItem(name: "  Apples ", quantity: 4, unit: .pieces)
        XCTAssertEqual(apple.category, "produce")
        XCTAssertEqual(apple.canonicalFoodName, FoodCanonicalizer.canonicalize("Apples"))
        let oil = try grocery.addItem(name: "Olive Oil", quantity: 1, unit: .bottles)
        XCTAssertEqual(oil.category, "oils")
        let explicit = try grocery.addItem(name: "Chicken", quantity: 1, unit: .packs, category: "meat")
        XCTAssertEqual(explicit.category, "meat")
    }

    func testCategoryUsesWholeWordsForShortKeywords() {
        XCTAssertNotEqual(GroceryListGenerator.category(for: "orange juice"), "frozen")
        XCTAssertNotEqual(GroceryListGenerator.category(for: "mixed spices"), "frozen")
        XCTAssertEqual(GroceryListGenerator.category(for: "ice cream"), "frozen")
        XCTAssertEqual(GroceryListGenerator.category(for: "eggplant"), "produce")
        XCTAssertEqual(GroceryListGenerator.category(for: "eggs"), "dairy")
    }

    func testStorageGuessUsesWholeWords() {
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "rice"), .pantry)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "orange juice"), .pantry)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "spices"), .pantry)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "fresh berries"), .fridge)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "frozen berries"), .freezer)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "ice cream"), .freezer)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "peanut butter"), .pantry)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "butter"), .fridge)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "steak"), .fridge)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "chicken breast"), .fridge)
    }

    // MARK: - 6. weekly spend

    func testWeeklySpendIgnoresUnreviewedAndDuplicateReceipts() {
        let now = Date()
        func receipt(_ total: Double, reviewed: Bool, key: String?, createdOffset: TimeInterval) -> Receipt {
            let r = Receipt(store: "Publix", purchaseDate: now, totalAmount: total, userReviewed: reviewed)
            r.duplicateKey = key
            r.createdAt = now.addingTimeInterval(createdOffset)
            return r
        }
        let receipts = [
            receipt(50, reviewed: true, key: "k1", createdOffset: 0),
            receipt(50, reviewed: true, key: "k1", createdOffset: 10), // same shop scanned twice
            receipt(30, reviewed: false, key: "k2", createdOffset: 0), // never confirmed
            receipt(20, reviewed: true, key: nil, createdOffset: 0),
        ]
        let weeks = GroceryWeeklySpendCalculator.compute(priceEntries: [], receipts: receipts, weeks: 1, budgetCapUSD: nil, now: now)
        XCTAssertEqual(weeks.last?.totalUSD ?? 0, 70, accuracy: 0.001)
        receipts[1].duplicateWarningDismissed = true // "yes, two real shops"
        let again = GroceryWeeklySpendCalculator.compute(priceEntries: [], receipts: receipts, weeks: 1, budgetCapUSD: nil, now: now)
        XCTAssertEqual(again.last?.totalUSD ?? 0, 120, accuracy: 0.001)
    }
}
