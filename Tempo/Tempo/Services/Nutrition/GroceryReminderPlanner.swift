//
// GroceryReminderPlanner.swift
// Tempo
//
// Pure planning layer for Reminders export (BUILD item 1c: no duplicates —
// reuse/update/remove instead of re-adding). EventKit itself can't be
// meaningfully unit-tested (no in-memory EKEventStore), so the DECISION of
// what to do with each item is pulled out here where it CAN be unit-tested.
// LocalGroceryListService.exportToReminders executes the plan against the
// real EKEventStore.
//

import Foundation

// MARK: - GroceryReminderAction

enum GroceryReminderAction: Equatable {
    /// No reminder exists yet for this item — create one and store its
    /// identifier back onto the item.
    case create(itemID: UUID)
    /// A reminder already exists (`reminderIdentifier` set) — update its
    /// title/completed state in place rather than creating a duplicate.
    case update(itemID: UUID, reminderIdentifier: String)
    /// The item was bought (pushed to pantry) and has a reminder — remove
    /// the reminder instead of leaving a stale "buy milk" around forever.
    case remove(itemID: UUID, reminderIdentifier: String)
}

// MARK: - GroceryReminderPlanner

enum GroceryReminderPlanner {
    /// One action per item that should touch Reminders. Manual items are
    /// included (the user explicitly added them — they expect them on the
    /// list export same as generated ones).
    static func plan(items: [GroceryListItem]) -> [GroceryReminderAction] {
        items.map { item in
            if let identifier = item.reminderIdentifier {
                return item.isBought
                    ? .remove(itemID: item.id, reminderIdentifier: identifier)
                    : .update(itemID: item.id, reminderIdentifier: identifier)
            }
            // No reminder yet: only create one for items still to buy —
            // don't create-then-immediately-need-removal for an
            // already-bought item.
            return .create(itemID: item.id)
        }.filter { action in
            if case let .create(itemID) = action {
                // Skip create for bought items with no prior reminder.
                return !(items.first { $0.id == itemID }?.isBought ?? false)
            }
            return true
        }
    }
}
