//
// KitchenUndoTests.swift
// Tempo
//
// Undo in the Kitchen must put back exactly what was removed: a grocery row
// with every field (and off the "dismissed" shelf the delete put its food on),
// a pantry row with the quantity it had, a supplement on the shelf, and a
// receipt that was never deleted while its Undo was open.
//

import SwiftData
@testable import Tempo
import UIKit
import XCTest

@MainActor
final class KitchenUndoTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: Grocery

    private func list(with items: [GroceryListItem]) -> GroceryList {
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        for item in items {
            item.list = list
            context.insert(item)
        }
        try? context.save()
        return list
    }

    private func groceryItems() -> [GroceryListItem] {
        (try? context.fetch(FetchDescriptor<GroceryListItem>())) ?? []
    }

    func testDeletedPlanRowComesBackWithEveryFieldAndLeavesTheDismissedShelf() throws {
        let item = GroceryListItem(
            canonicalFoodName: "Chicken Breast", displayName: "Chicken breast", quantity: 1.5, unit: .packs,
            category: "meat", isChecked: true, estimatedPriceUSD: 9.25, priceSource: .estimate, notes: "thin cut"
        )
        let list = list(with: [item])
        let originalID = item.id
        let originalCreatedAt = item.createdAt
        let snapshot = GroceryItemSnapshot(item)
        XCTAssertTrue(snapshot.addedToDismissed)

        // The same delete the Groceries page does.
        try LocalGroceryListService(modelContext: context).deleteItem(item)
        XCTAssertTrue(groceryItems().isEmpty)
        XCTAssertEqual(list.dismissedFoods, ["chicken breast"])

        let back = try XCTUnwrap(snapshot.restore(in: context))
        XCTAssertEqual(groceryItems().count, 1)
        XCTAssertEqual(back.id, originalID)
        XCTAssertEqual(back.list?.id, list.id)
        XCTAssertEqual(back.canonicalFoodName, "Chicken Breast")
        XCTAssertEqual(back.displayName, "Chicken breast")
        XCTAssertEqual(back.quantity, 1.5)
        XCTAssertEqual(back.unit, .packs)
        XCTAssertEqual(back.category, "meat")
        XCTAssertTrue(back.isChecked)
        XCTAssertFalse(back.isManual)
        XCTAssertEqual(back.estimatedPriceUSD, 9.25)
        XCTAssertEqual(back.priceSourceRaw, GroceryPriceSource.estimate.rawValue)
        XCTAssertEqual(back.notes, "thin cut")
        XCTAssertEqual(back.createdAt, originalCreatedAt)
        XCTAssertEqual(list.dismissedFoods, [], "a pantry sync must not treat the food as dismissed any more")
        // The page draws from the list's own items, so the row must be on it, once.
        XCTAssertEqual((list.items ?? []).filter { $0.id == originalID }.count, 1)
        XCTAssertTrue(list.activeItems.contains { $0.id == originalID })
    }

    func testRestoringTwiceDoesNotDuplicateTheRow() throws {
        let item = GroceryListItem(canonicalFoodName: "rice", displayName: "Rice", quantity: 1, unit: .packs)
        let list = list(with: [item])
        let snapshot = GroceryItemSnapshot(item)
        try LocalGroceryListService(modelContext: context).deleteItem(item)

        snapshot.restore(in: context)
        snapshot.restore(in: context)
        XCTAssertEqual(groceryItems().count, 1)
        XCTAssertEqual((list.items ?? []).count, 1)
    }

    func testManualRowDoesNotTouchTheDismissedShelf() throws {
        let item = GroceryListItem(
            canonicalFoodName: "oat milk", displayName: "Oat milk", quantity: 2, unit: .packs, isManual: true
        )
        let list = list(with: [item])
        list.dismissedFoods = ["tofu"]
        let snapshot = GroceryItemSnapshot(item)
        XCTAssertFalse(snapshot.addedToDismissed)

        try LocalGroceryListService(modelContext: context).deleteItem(item)
        XCTAssertEqual(list.dismissedFoods, ["tofu"])
        let back = try XCTUnwrap(snapshot.restore(in: context))
        XCTAssertTrue(back.isManual)
        XCTAssertEqual(list.dismissedFoods, ["tofu"], "a food dismissed earlier stays dismissed")
    }

    func testAFoodThatWasAlreadyDismissedStaysDismissedAfterUndo() throws {
        let item = GroceryListItem(canonicalFoodName: "tofu", displayName: "Tofu", quantity: 1, unit: .packs)
        let list = list(with: [item])
        list.dismissedFoods = ["tofu"]
        let snapshot = GroceryItemSnapshot(item)
        XCTAssertFalse(snapshot.addedToDismissed, "the delete did not add it, so undo must not remove it")

        try LocalGroceryListService(modelContext: context).deleteItem(item)
        snapshot.restore(in: context)
        XCTAssertEqual(list.dismissedFoods, ["tofu"])
    }

    func testNothingIsRestoredWhenTheListIsGone() throws {
        let item = GroceryListItem(canonicalFoodName: "rice", displayName: "Rice", quantity: 1, unit: .packs)
        let list = list(with: [item])
        let snapshot = GroceryItemSnapshot(item)
        context.delete(list)
        try context.save()

        XCTAssertNil(snapshot.restore(in: context))
        XCTAssertTrue(groceryItems().isEmpty)
    }

    // MARK: Pantry

    private func pantryItem(_ name: String, quantity: Double) -> PantryItem {
        let item = PantryItem(canonicalName: name, displayName: name, quantity: quantity, unit: .packs)
        context.insert(item)
        try? context.save()
        return item
    }

    func testArchivedPantryRowComesBackWithItsQuantity() throws {
        let item = pantryItem("rice", quantity: 2.5)
        let states = KitchenUndo.pantryStates(of: [item])

        try LocalPantryService(modelContext: context).archive(item)
        XCTAssertTrue(item.isArchived)

        XCTAssertEqual(KitchenUndo.restorePantry(states, in: context), 1)
        XCTAssertFalse(item.isArchived)
        XCTAssertEqual(item.quantity, 2.5)
    }

    func testUsedUpPantryRowGetsItsQuantityBack() throws {
        let item = pantryItem("eggs", quantity: 0.6)
        let states = KitchenUndo.pantryStates(of: [item])

        item.quantity = 0
        try context.save()
        KitchenUndo.restorePantry(states, in: context)
        XCTAssertEqual(item.quantity, 0.6)
        XCTAssertFalse(item.isArchived)
    }

    func testEmptyingThePantryIsUndoneRowByRowAndKeepsWhatWasAlreadyArchived() throws {
        let one = pantryItem("rice", quantity: 1)
        let two = pantryItem("oats", quantity: 3)
        let gone = pantryItem("old jam", quantity: 1)
        gone.isArchived = true
        let states = KitchenUndo.pantryStates(of: [one, two, gone])

        let service = LocalPantryService(modelContext: context)
        try service.archive(one)
        try service.archive(two)
        try service.archive(gone)

        XCTAssertEqual(KitchenUndo.restorePantry(states, in: context), 3)
        XCTAssertFalse(one.isArchived)
        XCTAssertFalse(two.isArchived)
        XCTAssertTrue(gone.isArchived, "an item removed before stays removed")
        XCTAssertEqual(two.quantity, 3)
    }

    func testRestoringARowThatIsGoneSkipsIt() throws {
        let item = pantryItem("rice", quantity: 1)
        let states = KitchenUndo.pantryStates(of: [item])
        context.delete(item)
        try context.save()

        XCTAssertEqual(KitchenUndo.restorePantry(states, in: context), 0)
    }

    // MARK: Supplements

    func testDeletedSupplementIsBackOnTheShelfAndAnnounced() throws {
        let supplement = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30)
        context.insert(supplement)
        supplement.isArchived = true
        try context.save()

        let announced = expectation(forNotification: .tempoSupplementsChanged, object: nil)
        XCTAssertTrue(KitchenUndo.restoreSupplement(id: supplement.id, in: context))
        XCTAssertFalse(supplement.isArchived)
        XCTAssertEqual(supplement.servingsRemaining, 30)
        wait(for: [announced], timeout: 1)
    }

    func testRestoringAMissingSupplementSaysSo() {
        XCTAssertFalse(KitchenUndo.restoreSupplement(id: UUID(), in: context))
    }

    // MARK: Receipts

    func testDeletedReceiptIsHiddenAtOnceAndNotDeletedWhileUndoIsOpen() async {
        let pending = KitchenPendingReceipts(center: NotificationCenter())
        let id = UUID()
        var deleted = 0
        pending.schedule(id: id, window: 0.2, delete: { deleted += 1 }, finished: {})

        XCTAssertTrue(pending.isHidden(id))
        XCTAssertEqual(deleted, 0)

        XCTAssertTrue(pending.undo(id))
        XCTAssertFalse(pending.isHidden(id))
        try? await Task.sleep(for: .seconds(0.9))
        XCTAssertEqual(deleted, 0, "an undone delete never runs")
    }

    func testReceiptIsDeletedOnceTheWindowHasPassed() async {
        let pending = KitchenPendingReceipts(center: NotificationCenter())
        let id = UUID()
        var deleted = 0
        var finished = 0
        pending.schedule(id: id, window: 0.1, delete: { deleted += 1 }, finished: { finished += 1 })

        try? await Task.sleep(for: .seconds(0.9))
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(pending.isHidden(id))
        XCTAssertFalse(pending.undo(id), "too late: it is gone")
    }

    func testLeavingTheAppDeletesWhatWaits() {
        let center = NotificationCenter()
        let pending = KitchenPendingReceipts(center: center)
        let id = UUID()
        var deleted = 0
        pending.schedule(id: id, window: 60, delete: { deleted += 1 }, finished: {})

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(pending.isHidden(id))
    }

    func testTheRealReceiptDeleteTakesItsLinesAlongOnlyAfterTheWindow() async throws {
        let receipt = Receipt(store: "Publix", purchaseDate: Date(), totalAmount: 20, ocrStatus: .confirmed, userReviewed: true)
        context.insert(receipt)
        context.insert(ReceiptLineItem(
            receipt: receipt, rawText: "MILK", canonicalFoodName: "milk", displayName: "Milk",
            quantity: 1, unit: .each, totalPrice: 3
        ))
        try context.save()
        let context = try XCTUnwrap(context)

        let pending = KitchenPendingReceipts(center: NotificationCenter())
        // What `ReceiptServiceProtocol.delete` does to the rows (it also removes the photo file).
        pending.schedule(id: receipt.id, window: 0.1, delete: {
            context.delete(receipt)
            try? context.save()
        }, finished: {})
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Receipt>()), 1, "still there while Undo is open")

        // Poll rather than sleep a fixed time: a loaded machine runs the timer late.
        for _ in 0 ..< 100 where try context.fetchCount(FetchDescriptor<Receipt>()) > 0 {
            try await Task.sleep(for: .seconds(0.1))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Receipt>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReceiptLineItem>()), 0)
    }
}
