//
// NonNegotiableAddUndo.swift
// Tempo
//
// Undo for adding non-negotiables: the setup page adds one task (or the four
// quick-start tasks) at once and offers Undo for a few seconds. Undo takes back
// exactly the tasks that were just added and leaves every other task alone.
// A task added a moment ago has no history yet, so nothing of the user's is lost.
//

import Foundation
import SwiftData

enum NonNegotiableAddUndo {
    /// Deletes the tasks with these ids. Returns how many went.
    @MainActor
    @discardableResult
    static func remove(ids: [UUID], from context: ModelContext) -> Int {
        let wanted = Set(ids)
        let all = (try? context.fetch(FetchDescriptor<NonNegotiable>())) ?? []
        var removed = 0
        for item in all where wanted.contains(item.id) {
            context.delete(item)
            removed += 1
        }
        try? context.save()
        return removed
    }
}
