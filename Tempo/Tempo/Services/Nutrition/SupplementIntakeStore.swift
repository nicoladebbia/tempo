//
// SupplementIntakeStore.swift
// Tempo
//
// Created by Tempo on 30/09/2026.
//
//

import Foundation
import SwiftData

/// Everything that reads or writes "was this supplement taken today", keyed by
/// `Supplement.id` — with a name fallback for rows (and already-scheduled
/// notifications) that predate the ID. Used by the Today toggle, the
/// notification "Taken" action and the reminder scheduler, so they can never
/// disagree about what counts as taken.
@MainActor
enum SupplementIntakeStore {
    /// Does `log` belong to this shelf item? By ID when the row has one. A
    /// legacy (ID-less) row can't tell same-named items apart, so it belongs
    /// to ONE of them only: `legacyOwner`, the first by stable order.
    static func matches(_ log: SupplementIntakeLog, id: UUID?, name: String, legacyOwner: UUID?) -> Bool {
        if let logID = log.supplementID {
            return logID == id
        }
        return log.supplementName == name && id == legacyOwner
    }

    /// Non-archived shelf items called `name`, in a stable order (oldest first).
    static func shelfItems(named name: String, in modelContext: ModelContext) -> [Supplement] {
        let descriptor = FetchDescriptor<Supplement>(
            predicate: #Predicate<Supplement> { $0.name == name && !$0.isArchived }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
    }

    static func logs(on day: Date, in modelContext: ModelContext) -> [SupplementIntakeLog] {
        let start = Calendar.current.startOfDay(for: day)
        let descriptor = FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day == start }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// The shelf row a (id, name) pair refers to: by ID, else the first
    /// non-archived item with that name.
    static func supplement(id: UUID?, name: String, in modelContext: ModelContext) -> Supplement? {
        if let id {
            var descriptor = FetchDescriptor<Supplement>(predicate: #Predicate<Supplement> { $0.id == id })
            descriptor.fetchLimit = 1
            if let found = (try? modelContext.fetch(descriptor))?.first {
                return found
            }
        }
        let byName = FetchDescriptor<Supplement>(
            predicate: #Predicate<Supplement> { $0.name == name && !$0.isArchived }
        )
        return (try? modelContext.fetch(byName))?.first
    }

    /// IDs of shelf items taken on `day`. A legacy name-only row marks only the
    /// first shelf item of that name (it can't tell them apart).
    static func takenIDs(on day: Date, in modelContext: ModelContext) -> Set<UUID> {
        let rows = logs(on: day, in: modelContext)
        guard !rows.isEmpty else {
            return []
        }
        var ids = Set(rows.compactMap(\.supplementID))
        let legacyNames = Set(rows.filter { $0.supplementID == nil }.map(\.supplementName))
        if !legacyNames.isEmpty {
            for name in legacyNames {
                if let owner = shelfItems(named: name, in: modelContext).first {
                    ids.insert(owner.id)
                }
            }
        }
        return ids
    }

    /// One-off upgrade of legacy name-only rows to IDs where the name maps to
    /// exactly one shelf item — keeps history attached through a later rename.
    static func backfillIDs(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<SupplementIntakeLog>(predicate: #Predicate<SupplementIntakeLog> { $0.supplementID == nil })
        guard let legacy = try? modelContext.fetch(descriptor), !legacy.isEmpty else {
            return
        }
        let shelf = (try? modelContext.fetch(FetchDescriptor<Supplement>())) ?? []
        let byName = Dictionary(grouping: shelf, by: \.name)
        var changed = false
        for row in legacy {
            if let matches = byName[row.supplementName], matches.count == 1 {
                row.supplementID = matches[0].id
                changed = true
            }
        }
        if changed {
            try? modelContext.save()
        }
    }

    /// Toggle taken ↔ not taken for `day`. Returns the new state. Applies the
    /// reorder decrement / undo to the shelf item. Does NOT post the
    /// `.tempoSupplementsChanged` notification (callers do).
    @discardableResult
    static func toggle(
        supplementID: UUID?,
        name: String,
        day: Date = Date(),
        in modelContext: ModelContext
    ) -> Bool {
        let today = Calendar.current.startOfDay(for: day)
        let shelfItem = supplement(id: supplementID, name: name, in: modelContext)
        let resolvedID = supplementID ?? shelfItem?.id
        let siblings = shelfItems(named: name, in: modelContext)
        let existing = logs(on: today, in: modelContext)
            .filter { matches($0, id: resolvedID, name: name, legacyOwner: siblings.first?.id) }
        let nowTaken: Bool
        if existing.isEmpty {
            let log = SupplementIntakeLog(supplementName: name, supplementID: resolvedID, day: today)
            modelContext.insert(log)
            if let shelfItem {
                log.stockDecrement = SupplementReorderService.applyTaken(to: shelfItem)
            }
            nowTaken = true
        } else {
            for row in existing {
                // A legacy name-only row with several same-named items can't
                // say which one it decremented — don't guess, leave the stock.
                let ambiguous = row.supplementID == nil && siblings.count > 1
                if let shelfItem, !ambiguous {
                    SupplementReorderService.applyUndo(to: shelfItem, amount: row.stockDecrement)
                }
                modelContext.delete(row)
            }
            nowTaken = false
        }
        try? modelContext.save()
        return nowTaken
    }

    /// Idempotent "mark taken" (the notification action). Returns whether a
    /// new row was written.
    @discardableResult
    static func markTaken(
        supplementID: UUID?,
        name: String,
        day: Date = Date(),
        in modelContext: ModelContext
    ) -> Bool {
        let today = Calendar.current.startOfDay(for: day)
        let shelfItem = supplement(id: supplementID, name: name, in: modelContext)
        let resolvedID = supplementID ?? shelfItem?.id
        let owner = shelfItems(named: name, in: modelContext).first?.id
        if logs(on: today, in: modelContext).contains(where: { matches($0, id: resolvedID, name: name, legacyOwner: owner) }) {
            return false
        }
        let log = SupplementIntakeLog(supplementName: name, supplementID: resolvedID, day: today)
        modelContext.insert(log)
        if let shelfItem {
            log.stockDecrement = SupplementReorderService.applyTaken(to: shelfItem)
        }
        return true
    }
}
