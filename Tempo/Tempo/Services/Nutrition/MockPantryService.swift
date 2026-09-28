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
        sourceReceiptLineItemID: UUID?,
        brand: String = ""
    ) throws -> PantryItem {
        let canonical = FoodCanonicalizer.canonicalize(rawName)
        let normBrand = PantryItem.normalizeBrand(brand)
        if let existing = items.first(where: {
            !$0.isArchived && $0.canonicalName == canonical && $0.unit == unit
                && PantryItem.normalizeBrand($0.brand) == normBrand
        }) {
            existing.increment(by: quantity)
            if existing.purchaseDate == nil {
                existing.purchaseDate = purchaseDate
            }
            if purchaseSource == .receiptScan {
                existing.purchaseSourceRaw = PantryPurchaseSource.receiptScan.rawValue
            }
            if existing.useBy == nil {
                existing.useBy = ShelfLifeEstimator.useByDate(
                    from: purchaseDate ?? Date(),
                    canonicalName: canonical,
                    storageLocation: existing.storageLocation
                )
            }
            return existing
        }
        let display = FoodCanonicalizer.displayName(rawName)
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
            useBy: ShelfLifeEstimator.useByDate(
                from: purchaseDate ?? Date(),
                canonicalName: canonical,
                storageLocation: storageLocation
            )
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
        purchaseSource: PantryPurchaseSource,
        brand: String = ""
    ) throws -> PantryItem {
        let canonical = FoodCanonicalizer.canonicalize(rawName)
        let normBrand = PantryItem.normalizeBrand(brand)
        if let existing = items.first(where: {
            !$0.isArchived && $0.canonicalName == canonical && $0.unit == unit
                && PantryItem.normalizeBrand($0.brand) == normBrand
        }) {
            existing.quantity = max(0, quantity)
            existing.updatedAt = Date()
            if existing.purchaseDate == nil {
                existing.purchaseDate = purchaseDate
            }
            if existing.useBy == nil {
                existing.useBy = ShelfLifeEstimator.useByDate(
                    from: purchaseDate ?? Date(),
                    canonicalName: canonical,
                    storageLocation: existing.storageLocation
                )
            }
            return existing
        }
        let display = FoodCanonicalizer.displayName(rawName)
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
            useBy: ShelfLifeEstimator.useByDate(
                from: purchaseDate ?? Date(),
                canonicalName: canonical,
                storageLocation: storageLocation
            )
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
            item.useBy = ShelfLifeEstimator.useByDate(
                from: Date(),
                canonicalName: item.canonicalName,
                storageLocation: item.storageLocation,
                isCooked: item.isCooked,
                isPrepped: item.isPrepped
            )
        }
        item.updatedAt = Date()
        return item
    }

    func archive(_ item: PantryItem) throws {
        item.isArchived = true
        item.updatedAt = Date()
    }

    func delete(_ item: PantryItem) throws {
        items.removeAll { $0.id == item.id }
    }
}
