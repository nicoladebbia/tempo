//
// PantryItem.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - PantryUnit

enum PantryUnit: String, Codable, CaseIterable, Sendable {
    case grams = "g"
    case kilograms = "kg"
    case milliliters = "ml"
    case liters = "l"
    case pieces
    case servings
    case ounces = "oz"
    case pounds = "lb"

    var displayName: String {
        switch self {
        case .grams: "g"
        case .kilograms: "kg"
        case .milliliters: "mL"
        case .liters: "L"
        case .pieces: "pcs"
        case .servings: "servings"
        case .ounces: "oz"
        case .pounds: "lb"
        }
    }
}

// MARK: - PantryStorageLocation

enum PantryStorageLocation: String, Codable, CaseIterable, Sendable {
    case fridge
    case freezer
    case pantry
    case cupboard

    var displayName: String {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        case .cupboard: "Cupboard"
        }
    }

    var icon: String {
        switch self {
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        case .pantry: "cabinet"
        case .cupboard: "archivebox"
        }
    }

    /// Frozen storage needs defrost lead time when used in a recipe.
    var requiresDefrost: Bool {
        self == .freezer
    }
}

// MARK: - PantryPurchaseSource

enum PantryPurchaseSource: String, Codable, CaseIterable, Sendable {
    case manual
    case receiptScan = "receipt_scan"
    case groceryConfirm = "grocery_confirm"
    case prepStep = "prep_step"
}

// MARK: - PantryItem

@Model
final class PantryItem {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    /// Canonical lowercased name (output of FoodCanonicalizer.canonicalize).
    /// Indexed for fast pantry queries during receipt ingestion + recipe match.
    var canonicalName: String

    /// User-visible name with title casing preserved.
    var displayName: String

    // MARK: - Quantity

    /// Current quantity in the chosen `unit`. Non-negative — enforced at app layer.
    var quantity: Double

    /// Storage unit as raw string (PantryUnit raw value).
    var unitRaw: String

    /// Storage location as raw string (PantryStorageLocation raw value).
    var storageLocationRaw: String

    /// Whether the item has been cooked (changes expiry curve).
    var isCooked: Bool

    /// Whether the item is prepped/portioned (changes expiry curve).
    var isPrepped: Bool

    /// When the item was cooked or prepped, if applicable.
    var preppedOn: Date?

    // MARK: - Purchase metadata

    /// When the item was acquired. Drives expiry calculation downstream.
    var purchaseDate: Date?

    /// Where the item came from — receipt scan, manual entry, grocery confirm, prep.
    var purchaseSourceRaw: String

    /// Receipt line item that produced this pantry entry, if applicable.
    /// Used by the receipt-review flow to know which lines are already ingested.
    /// Phase 3 wires this up; nil until then.
    var sourceReceiptLineItemID: UUID?

    // MARK: - Expiry

    /// Best-before date (still good but quality may degrade).
    var bestBefore: Date?

    /// Hard expiry — past this, discard.
    var useBy: Date?

    /// Free-text notes (brand, label info, prep details).
    var notes: String?

    // MARK: - Timestamps

    var createdAt: Date

    var updatedAt: Date

    /// Soft-delete flag — preserves history for analytics without breaking
    /// referential integrity from past receipts.
    var isArchived: Bool

    // MARK: - Computed

    @Transient
    var unit: PantryUnit {
        get { PantryUnit(rawValue: unitRaw) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }

    @Transient
    var storageLocation: PantryStorageLocation {
        get { PantryStorageLocation(rawValue: storageLocationRaw) ?? .pantry }
        set { storageLocationRaw = newValue.rawValue }
    }

    @Transient
    var purchaseSource: PantryPurchaseSource {
        get { PantryPurchaseSource(rawValue: purchaseSourceRaw) ?? .manual }
        set { purchaseSourceRaw = newValue.rawValue }
    }

    /// Days until `useBy`. Negative when expired. Nil when no use-by set.
    @Transient
    var daysUntilUseBy: Int? {
        guard let useBy else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: Date(), to: useBy).day
    }

    /// `true` when `useBy` is in the past.
    @Transient
    var isExpired: Bool {
        guard let useBy else {
            return false
        }
        return useBy < Date()
    }

    /// `true` when item expires within the next 3 days.
    @Transient
    var isExpiringSoon: Bool {
        guard let days = daysUntilUseBy else {
            return false
        }
        return days >= 0 && days <= 3
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        canonicalName: String,
        displayName: String,
        quantity: Double,
        unit: PantryUnit = .grams,
        storageLocation: PantryStorageLocation = .pantry,
        isCooked: Bool = false,
        isPrepped: Bool = false,
        preppedOn: Date? = nil,
        purchaseDate: Date? = nil,
        purchaseSource: PantryPurchaseSource = .manual,
        sourceReceiptLineItemID: UUID? = nil,
        bestBefore: Date? = nil,
        useBy: Date? = nil,
        notes: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.displayName = displayName
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.storageLocationRaw = storageLocation.rawValue
        self.isCooked = isCooked
        self.isPrepped = isPrepped
        self.preppedOn = preppedOn
        self.purchaseDate = purchaseDate
        self.purchaseSourceRaw = purchaseSource.rawValue
        self.sourceReceiptLineItemID = sourceReceiptLineItemID
        self.bestBefore = bestBefore
        self.useBy = useBy
        self.notes = notes
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
        self.isArchived = isArchived
    }

    /// Convenience init that auto-fills canonicalName + displayName from a raw string.
    convenience init(
        rawName: String,
        quantity: Double,
        unit: PantryUnit = .grams,
        storageLocation: PantryStorageLocation = .pantry,
        purchaseSource: PantryPurchaseSource = .manual
    ) {
        self.init(
            canonicalName: FoodCanonicalizer.canonicalize(rawName),
            displayName: FoodCanonicalizer.displayName(rawName),
            quantity: quantity,
            unit: unit,
            storageLocation: storageLocation,
            purchaseSource: purchaseSource
        )
    }

    // MARK: - Mutation helpers

    /// Add `amount` to current quantity. Resets updatedAt.
    func increment(by amount: Double) {
        quantity = max(0, quantity + amount)
        updatedAt = Date()
    }

    /// Subtract `amount` from current quantity. Floors at zero. Resets updatedAt.
    func decrement(by amount: Double) {
        quantity = max(0, quantity - amount)
        updatedAt = Date()
    }
}

// MARK: - DTO

extension PantryItem {
    struct DTO: Codable, Sendable {
        let id: UUID
        let canonical_name: String
        let display_name: String
        let quantity: Double
        let unit: String
        let storage_location: String
        let is_cooked: Bool
        let is_prepped: Bool
        let prepped_on: Date?
        let purchase_date: Date?
        let purchase_source: String
        let source_receipt_line_item_id: UUID?
        let best_before: Date?
        let use_by: Date?
        let notes: String?
        let created_at: Date
        let updated_at: Date
        let is_archived: Bool
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            canonical_name: canonicalName,
            display_name: displayName,
            quantity: quantity,
            unit: unitRaw,
            storage_location: storageLocationRaw,
            is_cooked: isCooked,
            is_prepped: isPrepped,
            prepped_on: preppedOn,
            purchase_date: purchaseDate,
            purchase_source: purchaseSourceRaw,
            source_receipt_line_item_id: sourceReceiptLineItemID,
            best_before: bestBefore,
            use_by: useBy,
            notes: notes,
            created_at: createdAt,
            updated_at: updatedAt,
            is_archived: isArchived
        )
    }
}
