//
// PantryShelfLifeBackfillService.swift
// Tempo
//
// One-shot-per-launch backfill: pantry rows created before the shelf-life
// estimator existed (or any row that somehow ended up without a `useBy`)
// get one estimated from their `purchaseDate` (falling back to `createdAt`
// when no purchase date was recorded). Idempotent — only touches rows where
// `useBy == nil`, so it never overwrites a value the user deliberately
// edited or cleared... except a cleared value reads as nil too; that's an
// accepted tradeoff (an explicitly-cleared useBy is rare and re-estimating
// it is safer than silently losing expiry tracking forever).
//

import Foundation
import os
import SwiftData

@MainActor
enum PantryShelfLifeBackfillService {
    private static let logger = Logger(subsystem: "app.tempo", category: "PantryShelfLifeBackfill")

    /// Runs the backfill and returns the number of rows updated.
    @discardableResult
    static func run(modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false && item.useBy == nil
            }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        guard !rows.isEmpty else {
            return 0
        }

        for item in rows {
            let base = item.purchaseDate ?? item.createdAt
            item.useBy = ShelfLifeEstimator.useByDate(
                from: base,
                canonicalName: item.canonicalName,
                storageLocation: item.storageLocation,
                isCooked: item.isCooked,
                isPrepped: item.isPrepped
            )
        }
        do {
            try modelContext.save()
            logger.info("Backfilled useBy for \(rows.count) pantry item(s)")
        } catch {
            logger.error("Backfill save failed: \(error.localizedDescription, privacy: .public)")
        }
        return rows.count
    }
}
