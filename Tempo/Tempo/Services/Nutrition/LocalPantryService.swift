//
// LocalPantryService.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import os
import SwiftData

@MainActor
@Observable
final class LocalPantryService: PantryServiceProtocol {
    private let modelContext: ModelContext
    private let logger = Logger.nutrition
    /// Optional AI fallback for foods the hand-authored ShelfLifeEstimator
    /// table doesn't recognize. nil (the default) simply skips the AI
    /// refinement — the generic per-location fallback estimate stands.
    /// Injected so tests never hit the network.
    private let shelfLifeAIEstimator: (any ShelfLifeAIEstimating)?

    init(modelContext: ModelContext, shelfLifeAIEstimator: (any ShelfLifeAIEstimating)? = nil) {
        self.modelContext = modelContext
        self.shelfLifeAIEstimator = shelfLifeAIEstimator
    }

    // MARK: - Fetch

    func fetchAll() throws -> [PantryItem] {
        var descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return try modelContext.fetch(descriptor)
    }

    func fetch(in location: PantryStorageLocation) throws -> [PantryItem] {
        let rawLocation = location.rawValue
        var descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false && item.storageLocationRaw == rawLocation
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return try modelContext.fetch(descriptor)
    }

    func find(canonicalName: String) throws -> PantryItem? {
        var descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false && item.canonicalName == canonicalName
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Mutate

    func add(_ item: PantryItem) throws {
        if item.useBy == nil {
            let (days, matched) = ShelfLifeEstimator.estimate(
                canonicalName: item.canonicalName,
                storageLocation: item.storageLocation,
                isCooked: item.isCooked,
                isPrepped: item.isPrepped
            )
            let base = item.purchaseDate ?? Date()
            item.useBy = Calendar.current.date(byAdding: .day, value: days, to: base)
            if !matched {
                refineUseByWithAIIfPossible(itemID: item.id, canonicalName: item.canonicalName, storageLocation: item.storageLocation)
            }
        }
        modelContext.insert(item)
        try modelContext.save()
        logger.info("Pantry add: \(item.displayName, privacy: .public) \(item.quantity)\(item.unit.displayName, privacy: .public)")
    }

    @discardableResult
    func mergeOrCreate(
        rawName: String,
        quantity: Double,
        unit: PantryUnit,
        storageLocation: PantryStorageLocation,
        purchaseDate: Date?,
        purchaseSource: PantryPurchaseSource,
        sourceReceiptLineItemID: UUID?,
        brand: String = ""
    ) throws -> PantryItem {
        let canonical = FoodCanonicalizer.canonicalize(rawName)
        let display = FoodCanonicalizer.displayName(rawName)

        // Find existing non-archived items with the same canonical name + unit,
        // then match on NORMALIZED brand in Swift (SwiftData #Predicate can't
        // call the normalize helper). Different normalized brand → separate row.
        let rawUnit = unit.rawValue
        let normBrand = PantryItem.normalizeBrand(brand)
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false
                    && item.canonicalName == canonical
                    && item.unitRaw == rawUnit
            }
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        let existing = candidates.first { PantryItem.normalizeBrand($0.brand) == normBrand }

        if let existing {
            existing.increment(by: quantity)
            if existing.purchaseDate == nil {
                existing.purchaseDate = purchaseDate
            }
            // Receipt-driven adds upgrade the source from manual to receipt_scan.
            if purchaseSource == .receiptScan {
                existing.purchaseSourceRaw = PantryPurchaseSource.receiptScan.rawValue
            }
            if sourceReceiptLineItemID != nil {
                existing.sourceReceiptLineItemID = sourceReceiptLineItemID
            }
            // Auto-expiry: this new batch joins the existing row's storage
            // location. The shorter of the two use-by dates wins — the
            // whole merged stack spoils as fast as its OLDEST portion.
            let (days, matched) = ShelfLifeEstimator.estimate(
                canonicalName: canonical,
                storageLocation: existing.storageLocation,
                isCooked: existing.isCooked,
                isPrepped: existing.isPrepped
            )
            let candidateUseBy = Calendar.current.date(
                byAdding: .day, value: days, to: purchaseDate ?? Date()
            )
            if let candidateUseBy {
                existing.useBy = [existing.useBy, candidateUseBy].compactMap(\.self).min()
            }
            if !matched {
                refineUseByWithAIIfPossible(itemID: existing.id, canonicalName: canonical, storageLocation: existing.storageLocation)
            }
            try modelContext.save()
            logger
                .info(
                    "Pantry merge: \(canonical, privacy: .public) +\(quantity)\(unit.displayName, privacy: .public) → \(existing.quantity)"
                )
            return existing
        }

        let (days, matched) = ShelfLifeEstimator.estimate(
            canonicalName: canonical,
            storageLocation: storageLocation
        )
        let computedUseBy = Calendar.current.date(byAdding: .day, value: days, to: purchaseDate ?? Date())
        let new = PantryItem(
            canonicalName: canonical,
            displayName: display.isEmpty ? rawName : display,
            brand: brand,
            quantity: quantity,
            unit: unit,
            storageLocation: storageLocation,
            purchaseDate: purchaseDate,
            purchaseSource: purchaseSource,
            sourceReceiptLineItemID: sourceReceiptLineItemID,
            useBy: computedUseBy
        )
        modelContext.insert(new)
        try modelContext.save()
        if !matched {
            refineUseByWithAIIfPossible(itemID: new.id, canonicalName: canonical, storageLocation: storageLocation)
        }
        logger.info("Pantry create: \(canonical, privacy: .public) \(quantity)\(unit.displayName, privacy: .public)")
        return new
    }

    @discardableResult
    func setOrCreate(
        rawName: String,
        quantity: Double,
        unit: PantryUnit,
        storageLocation: PantryStorageLocation,
        purchaseDate: Date?,
        purchaseSource: PantryPurchaseSource,
        brand: String = ""
    ) throws -> PantryItem {
        // SET semantics (voice stock-take, §voice-pantry): REPLACE the tracked
        // quantity of an existing canonical+unit+brand match instead of
        // incrementing. "I have 750 g of pasta" is a current-total statement,
        // not a purchase. Match rule mirrors mergeOrCreate (canonical + unit +
        // normalized brand) so different brands stay separate rows.
        let canonical = FoodCanonicalizer.canonicalize(rawName)
        let display = FoodCanonicalizer.displayName(rawName)

        let rawUnit = unit.rawValue
        let normBrand = PantryItem.normalizeBrand(brand)
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false
                    && item.canonicalName == canonical
                    && item.unitRaw == rawUnit
            }
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        let existing = candidates.first { PantryItem.normalizeBrand($0.brand) == normBrand }

        if let existing {
            let previous = existing.quantity
            existing.quantity = max(0, quantity)
            existing.updatedAt = Date()
            if existing.purchaseDate == nil {
                existing.purchaseDate = purchaseDate
            }
            // A stock-take on a row that never got an estimate (pre-dates
            // this feature) still deserves one; don't reset an existing one.
            if existing.useBy == nil {
                let (days, matched) = ShelfLifeEstimator.estimate(
                    canonicalName: canonical,
                    storageLocation: existing.storageLocation,
                    isCooked: existing.isCooked,
                    isPrepped: existing.isPrepped
                )
                existing.useBy = Calendar.current.date(byAdding: .day, value: days, to: purchaseDate ?? Date())
                if !matched {
                    refineUseByWithAIIfPossible(itemID: existing.id, canonicalName: canonical, storageLocation: existing.storageLocation)
                }
            }
            try modelContext.save()
            logger.info(
                "Pantry set: \(canonical, privacy: .public) \(previous) → \(existing.quantity)\(unit.displayName, privacy: .public)"
            )
            return existing
        }

        let (days, matched) = ShelfLifeEstimator.estimate(canonicalName: canonical, storageLocation: storageLocation)
        let computedUseBy = Calendar.current.date(byAdding: .day, value: days, to: purchaseDate ?? Date())
        let new = PantryItem(
            canonicalName: canonical,
            displayName: display.isEmpty ? rawName : display,
            brand: brand,
            quantity: max(0, quantity),
            unit: unit,
            storageLocation: storageLocation,
            purchaseDate: purchaseDate,
            purchaseSource: purchaseSource,
            sourceReceiptLineItemID: nil,
            useBy: computedUseBy
        )
        modelContext.insert(new)
        try modelContext.save()
        if !matched {
            refineUseByWithAIIfPossible(itemID: new.id, canonicalName: canonical, storageLocation: storageLocation)
        }
        logger.info("Pantry set-create: \(canonical, privacy: .public) \(quantity)\(unit.displayName, privacy: .public)")
        return new
    }

    func adjustQuantity(of item: PantryItem, by delta: Double) throws {
        if delta >= 0 {
            item.increment(by: delta)
        } else {
            item.decrement(by: -delta)
        }
        try modelContext.save()
    }

    @discardableResult
    func updateItem(
        _ item: PantryItem,
        quantity: Double?,
        unit: PantryUnit?,
        storageLocation: PantryStorageLocation?,
        useBy: Date?,
        brand: String?
    ) throws -> PantryItem {
        if let quantity {
            item.quantity = max(0, quantity)
        }
        if let unit {
            item.unit = unit
        }
        let locationChanged = storageLocation != nil && storageLocation != item.storageLocation
        if let storageLocation {
            item.storageLocation = storageLocation
        }
        if let brand {
            item.brand = brand
        }
        if let useBy {
            item.useBy = useBy
        } else if locationChanged {
            // No explicit useBy supplied alongside the move → recompute for
            // the new location (fridge → freezer extends the clock, and
            // vice versa). Anchored to today, not the original purchase
            // date: moving it today is what changes its remaining life.
            item.useBy = ShelfLifeEstimator.useByDate(
                from: Date(),
                canonicalName: item.canonicalName,
                storageLocation: item.storageLocation,
                isCooked: item.isCooked,
                isPrepped: item.isPrepped
            )
        }
        item.updatedAt = Date()
        try modelContext.save()
        logger.info("Pantry update: \(item.canonicalName, privacy: .public)")
        return item
    }

    func archive(_ item: PantryItem) throws {
        item.isArchived = true
        item.updatedAt = Date()
        try modelContext.save()
        logger.info("Pantry archive: \(item.canonicalName, privacy: .public)")
    }

    func delete(_ item: PantryItem) throws {
        modelContext.delete(item)
        try modelContext.save()
        logger.info("Pantry delete: \(item.canonicalName, privacy: .public)")
    }

    // MARK: - AI shelf-life refinement (best-effort, non-blocking)

    /// Fires a background AI estimate for a food the hand-authored table
    /// doesn't recognize, then silently tightens the item's `useBy` if the
    /// AI's answer is more specific. Never blocks the caller (mergeOrCreate
    /// etc. stay synchronous) and never throws — a failed/slow AI call just
    /// means the generic fallback estimate stands. Checks the shared cache
    /// first so the same unknown food never costs a second network call in
    /// one session.
    private func refineUseByWithAIIfPossible(
        itemID: UUID,
        canonicalName: String,
        storageLocation: PantryStorageLocation
    ) {
        guard let shelfLifeAIEstimator else {
            return
        }
        Task { [weak self] in
            await self?.refineUseByWithAI(
                itemID: itemID,
                canonicalName: canonicalName,
                storageLocation: storageLocation,
                aiEstimator: shelfLifeAIEstimator
            )
        }
    }

    /// Exposed `internal` (not `private`) so tests can `await` it directly
    /// instead of racing the fire-and-forget `Task` above.
    func refineUseByWithAI(
        itemID: UUID,
        canonicalName: String,
        storageLocation: PantryStorageLocation,
        aiEstimator: any ShelfLifeAIEstimating
    ) async {
        let request = ShelfLifeAIRequest(canonicalName: canonicalName, storageLocation: storageLocation)
        var days = await ShelfLifeAICache.shared.get(request.key)
        if days == nil {
            let results = await (try? aiEstimator.estimateDays([request])) ?? [:]
            if let fetched = results[request.key] {
                await ShelfLifeAICache.shared.set(request.key, fetched)
                days = fetched
            }
        }
        guard let days else {
            return
        }

        var descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { $0.id == itemID && $0.isArchived == false }
        )
        descriptor.fetchLimit = 1
        guard let item = (try? modelContext.fetch(descriptor))?.first else {
            return
        }
        let base = item.purchaseDate ?? item.createdAt
        guard let aiUseBy = Calendar.current.date(byAdding: .day, value: days, to: base) else {
            return
        }
        item.useBy = [item.useBy, aiUseBy].compactMap(\.self).min()
        try? modelContext.save()
    }
}
