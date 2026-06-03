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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
            try modelContext.save()
            logger
                .info(
                    "Pantry merge: \(canonical, privacy: .public) +\(quantity)\(unit.displayName, privacy: .public) → \(existing.quantity)"
                )
            return existing
        }

        let new = PantryItem(
            canonicalName: canonical,
            displayName: display.isEmpty ? rawName : display,
            brand: brand,
            quantity: quantity,
            unit: unit,
            storageLocation: storageLocation,
            purchaseDate: purchaseDate,
            purchaseSource: purchaseSource,
            sourceReceiptLineItemID: sourceReceiptLineItemID
        )
        modelContext.insert(new)
        try modelContext.save()
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
            try modelContext.save()
            logger.info(
                "Pantry set: \(canonical, privacy: .public) \(previous) → \(existing.quantity)\(unit.displayName, privacy: .public)"
            )
            return existing
        }

        let new = PantryItem(
            canonicalName: canonical,
            displayName: display.isEmpty ? rawName : display,
            brand: brand,
            quantity: max(0, quantity),
            unit: unit,
            storageLocation: storageLocation,
            purchaseDate: purchaseDate,
            purchaseSource: purchaseSource,
            sourceReceiptLineItemID: nil
        )
        modelContext.insert(new)
        try modelContext.save()
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
}
