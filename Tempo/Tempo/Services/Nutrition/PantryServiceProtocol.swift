//
// PantryServiceProtocol.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - PantryServiceProtocol

@MainActor
protocol PantryServiceProtocol: Sendable {
    /// Fetch all active (non-archived) pantry items.
    func fetchAll() throws -> [PantryItem]

    /// Fetch items in a specific storage location.
    func fetch(in location: PantryStorageLocation) throws -> [PantryItem]

    /// Look up a pantry item by canonical name. Returns the first match,
    /// or nil if not found. Useful for receipt ingest dedup.
    func find(canonicalName: String) throws -> PantryItem?

    /// Insert a new pantry item. Canonicalization is the caller's responsibility
    /// (use `PantryItem(rawName:...)` for the convenience init).
    func add(_ item: PantryItem) throws

    /// Merge a raw scanned line into the pantry. If a non-archived item with the
    /// same canonical name + unit exists, its quantity is incremented. Otherwise
    /// a new item is created. Returns the resulting item.
    @discardableResult
    func mergeOrCreate(
        rawName: String,
        quantity: Double,
        unit: PantryUnit,
        storageLocation: PantryStorageLocation,
        purchaseDate: Date?,
        purchaseSource: PantryPurchaseSource,
        sourceReceiptLineItemID: UUID?
    ) throws -> PantryItem

    /// Update a tracked item's quantity. Pass a negative delta to decrement.
    /// Floors quantity at zero.
    func adjustQuantity(of item: PantryItem, by delta: Double) throws

    /// Archive an item (soft-delete). The row stays for analytics/history.
    func archive(_ item: PantryItem) throws

    /// Hard-delete an item — used only when the user explicitly removes a
    /// receipt-driven entry they don't want tracked at all.
    func delete(_ item: PantryItem) throws
}
