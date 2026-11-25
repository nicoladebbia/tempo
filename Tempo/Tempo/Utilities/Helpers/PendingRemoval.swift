//
// PendingRemoval.swift
// Tempo
//
// The "hide now, remove for good when the Undo toast ends" rule, as a value type
// so it can be tested without a screen. A page hides the item the moment the user
// removes it, shows the Undo toast, and only then does the real removal (a server
// call, a file delete) that cannot be taken back.
//
// One item waits at a time. Removing a second item makes the first final, so the
// user is never holding two Undos and no item is left hidden for ever.
//

import Foundation

struct PendingRemoval<Item: Equatable> {
    /// The item that is hidden and still undoable, if any.
    private(set) var item: Item?

    /// Starts hiding `newItem`. Returns the item that was waiting before it: that
    /// one is final now, and the caller must remove it for good.
    @discardableResult
    mutating func begin(_ newItem: Item) -> Item? {
        let replaced = item
        item = newItem
        return replaced
    }

    /// Takes the pending item back (the user tapped Undo). Returns it, or nil if
    /// nothing was waiting.
    @discardableResult
    mutating func undo() -> Item? {
        defer { item = nil }
        return item
    }

    /// The Undo window ended. Returns the item to remove for good, or nil if it was
    /// already undone or finished.
    mutating func finish() -> Item? {
        defer { item = nil }
        return item
    }

    /// Whether `candidate` is the item being hidden right now.
    func hides(_ candidate: Item) -> Bool {
        item == candidate
    }
}
