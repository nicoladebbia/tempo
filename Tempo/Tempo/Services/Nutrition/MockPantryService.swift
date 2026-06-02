//
// MockPantryService.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

@MainActor
@Observable
final class MockPantryService: PantryServiceProtocol {
    private(set) var items: [PantryItem]

    init(items: [PantryItem] = []) {
        self.items = items
    }

    func fetchAll() throws -> [PantryItem] {
        items.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetch(in location: PantryStorageLocation) throws -> [PantryItem] {
        try fetchAll().filter { $0.storageLocation == location }
    }

    func find(canonicalName: String) throws -> PantryItem? {
        try fetchAll().first { $0.canonicalName == canonicalName }
    }

    func add(_ item: PantryItem) throws {
        items.append(item)
    }

    @discardableResult
    func mergeOrCreate(
        rawName: String,
        quantity: Double,
        unit: PantryUnit,
        storageLocation: PantryStorageLocation,
        purchaseDate: Date?,
        purchaseSource: PantryPurchaseSource,
        sourceReceiptLineItemID: UUID?
    ) throws -> PantryItem {
        let canonical = FoodCanonicalizer.canonicalize(rawName)
        if let existing = items.first(where: {
            !$0.isArchived && $0.canonicalName == canonical && $0.unit == unit
        }) {
            existing.increment(by: quantity)
            if existing.purchaseDate == nil {
                existing.purchaseDate = purchaseDate
            }
            if purchaseSource == .receiptScan {
                existing.purchaseSourceRaw = PantryPurchaseSource.receiptScan.rawValue
            }
            return existing
        }
        let display = FoodCanonicalizer.displayName(rawName)
        let new = PantryItem(
            canonicalName: canonical,
            displayName: display.isEmpty ? rawName : display,
            quantity: quantity,
            unit: unit,
            storageLocation: storageLocation,
            purchaseDate: purchaseDate,
            purchaseSource: purchaseSource,
            sourceReceiptLineItemID: sourceReceiptLineItemID
        )
        items.append(new)
        return new
    }

    @discardableResult
    func setOrCreate(
        rawName: String,
        quantity: Double,
        unit: PantryUnit,
        storageLocation: PantryStorageLocation,
        purchaseDate: Date?,
        purchaseSource: PantryPurchaseSource
    ) throws -> PantryItem {
        let canonical = FoodCanonicalizer.canonicalize(rawName)
        if let existing = items.first(where: {
            !$0.isArchived && $0.canonicalName == canonical && $0.unit == unit
        }) {
            existing.quantity = max(0, quantity)
            existing.updatedAt = Date()
            if existing.purchaseDate == nil {
                existing.purchaseDate = purchaseDate
            }
            return existing
        }
        let display = FoodCanonicalizer.displayName(rawName)
        let new = PantryItem(
            canonicalName: canonical,
            displayName: display.isEmpty ? rawName : display,
            quantity: max(0, quantity),
            unit: unit,
            storageLocation: storageLocation,
            purchaseDate: purchaseDate,
            purchaseSource: purchaseSource,
            sourceReceiptLineItemID: nil
        )
        items.append(new)
        return new
    }

    func adjustQuantity(of item: PantryItem, by delta: Double) throws {
        if delta >= 0 {
            item.increment(by: delta)
        } else {
            item.decrement(by: -delta)
        }
    }

    func archive(_ item: PantryItem) throws {
        item.isArchived = true
        item.updatedAt = Date()
    }

    func delete(_ item: PantryItem) throws {
        items.removeAll { $0.id == item.id }
    }
}
