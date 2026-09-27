//
// GroceryReminderPlannerTests.swift
// Tempo
//
// BUILD item 1c: Reminders export must not duplicate. GroceryReminderPlanner
// is the pure decision layer (create/update/remove) that
// LocalGroceryListService.exportToReminders executes against EventKit.
//

import Foundation
@testable import Tempo
import XCTest

// MARK: - GroceryReminderPlannerTests

@MainActor
final class GroceryReminderPlannerTests: XCTestCase {
    private func item(
        name: String,
        isChecked: Bool = false,
        isBought: Bool = false,
        reminderIdentifier: String? = nil
    ) -> GroceryListItem {
        GroceryListItem(
            canonicalFoodName: name.lowercased(),
            displayName: name,
            quantity: 1,
            unit: .pieces,
            isChecked: isChecked,
            isBought: isBought,
            reminderIdentifier: reminderIdentifier
        )
    }

    func testPlan_itemWithNoIdentifier_createsReminder() {
        let plan = GroceryReminderPlanner.plan(items: [item(name: "Rice")])
        XCTAssertEqual(plan, [.create(itemID: plan[0].itemIDForTest)])
    }

    func testPlan_itemWithExistingIdentifier_updatesInsteadOfCreating() {
        let i = item(name: "Rice", reminderIdentifier: "abc-123")
        let plan = GroceryReminderPlanner.plan(items: [i])
        XCTAssertEqual(plan, [.update(itemID: i.id, reminderIdentifier: "abc-123")])
    }

    func testPlan_reexport_neverCreatesASecondReminderForTheSameItem() {
        // Simulates: export once (gets an identifier), tick more items,
        // export again — the already-exported item must UPDATE, not CREATE.
        let exported = item(name: "Rice", reminderIdentifier: "abc-123")
        let fresh = item(name: "Oats")
        let plan = GroceryReminderPlanner.plan(items: [exported, fresh])

        let creates = plan.filter {
            if case .create = $0 {
                true
            } else {
                false
            }
        }
        let updates = plan.filter {
            if case .update = $0 {
                true
            } else {
                false
            }
        }
        XCTAssertEqual(creates.count, 1, "Only the never-exported item creates")
        XCTAssertEqual(updates.count, 1, "The already-exported item updates")
    }

    func testPlan_boughtItemWithIdentifier_removesReminder() {
        let i = item(name: "Rice", isBought: true, reminderIdentifier: "abc-123")
        let plan = GroceryReminderPlanner.plan(items: [i])
        XCTAssertEqual(plan, [.remove(itemID: i.id, reminderIdentifier: "abc-123")])
    }

    func testPlan_boughtItemWithNoIdentifier_doesNothing() {
        // Never exported AND already bought — no point creating a reminder
        // just to immediately need removal.
        let i = item(name: "Rice", isBought: true)
        let plan = GroceryReminderPlanner.plan(items: [i])
        XCTAssertTrue(plan.isEmpty)
    }

    func testPlan_checkedButNotBought_stillUpdatesOrCreates() {
        // Checked (in cart) but not yet pushed to pantry — still wants a
        // reminder, just completed. Create/update path, not remove.
        let i = item(name: "Rice", isChecked: true)
        let plan = GroceryReminderPlanner.plan(items: [i])
        XCTAssertEqual(plan, [.create(itemID: i.id)])
    }
}

/// Small helper so the "create" case (which doesn't carry the item's real ID
/// in the case payload — it does, but this documents the intent to compare by
/// the item's own id) is easy to assert against in tests.
private extension GroceryReminderAction {
    var itemIDForTest: UUID {
        switch self {
        case let .create(itemID),
             let .update(itemID, _),
             let .remove(itemID, _):
            itemID
        }
    }
}
