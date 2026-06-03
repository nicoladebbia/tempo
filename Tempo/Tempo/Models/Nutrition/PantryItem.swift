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
    // Container units — added once the grocery flow started using
    // FoodMacroDatabase.naturalPortions purchase units. Pantry rows now
    // speak the same language as the grocery list ("1 can of black beans"
    // stays "1 can" everywhere instead of being flattened to `.pieces`).
    case cans
    case bottles
    case jars
    case packs

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
        case .cans: "cans"
        case .bottles: "bottles"
        case .jars: "jars"
        case .packs: "packs"
        }
    }

    /// True when the unit counts whole containers / pieces (no fractional
    /// grams). Used by callers that need to round up gram totals into
    /// whole purchase units (grocery list, pantry decrement).
    var isCountable: Bool {
        switch self {
        case .pieces, .servings, .cans, .bottles, .jars, .packs: true
        default: false
        }
    }

    /// Convert a quantity in this unit to grams, when possible. Used by
    /// cross-unit reconciliation (grocery list dedup against pantry where
    /// the user might have logged "1 pack" while the list says "500g").
    /// Returns nil when conversion would require food-specific knowledge
    /// we don't have here (e.g. `.servings` of "pasta" vs `.servings` of
    /// "olive oil" → caller must pass `foodName` for those).
    ///
    /// `foodName` enables container-unit conversion via
    /// FoodMacroDatabase.naturalPortions[foodName].purchaseGrams — "1 pack
    /// of pasta" resolves to its known purchase weight.
    func gramsApprox(quantity: Double, foodName: String? = nil) -> Double? {
        switch self {
        case .grams: return quantity
        case .kilograms: return quantity * 1000
        case .milliliters: return quantity // 1mL ≈ 1g for most liquid foods
        case .liters: return quantity * 1000
        case .ounces: return quantity * 28.3495
        case .pounds: return quantity * 453.592
        case .pieces, .servings, .cans, .bottles, .jars, .packs:
            // Look up the per-unit gram weight for this food (e.g. one
            // "pack" of pasta = 500g per naturalPortions). Without the
            // food name we can't disambiguate "1 piece" of an apple
            // (~150g) from "1 piece" of a chip (~2g).
            guard let foodName,
                  let portion = FoodMacroDatabase.naturalPortions[foodName.lowercased()]
            else { return nil }
            let unitGrams = self == .packs ? portion.purchaseGrams : portion.grams
            return quantity * unitGrams
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

    /// Brand or distinguishing description as the user spoke it (e.g.
    /// "Land O'Lakes", "50% more protein"). Stored verbatim for display.
    /// Empty string = generic / no brand. Two items with the SAME canonical
    /// name + unit but DIFFERENT normalized brands stay separate rows so
    /// distinct products aren't conflated. Default "" so existing rows and the
    /// scan/manual flows (which pass no brand) merge exactly as before.
    var brand: String = ""

    /// Normalizes a brand for merge-key comparison: lowercased, only
    /// alphanumerics. "Land O'Lakes" and "Land O Lakes" both → "landolakes",
    /// so spoken-spelling variance of the same brand still merges. Stored
    /// brand stays verbatim; only the comparison uses this.
    static func normalizeBrand(_ brand: String) -> String {
        brand.lowercased().filter { $0.isLetter || $0.isNumber }
    }

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

    /// Days until `useBy`, computed on calendar-day boundaries (not sub-day
    /// precision) so it agrees with `isExpired`. Negative when expired.
    /// Nil when no use-by set.
    @Transient
    var daysUntilUseBy: Int? {
        guard let useBy else {
            return nil
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: useBy)
        return calendar.dateComponents([.day], from: today, to: target).day
    }

    /// `true` when `useBy`'s calendar day is strictly before today.
    /// Matches `daysUntilUseBy` precision so the two flags can't disagree.
    @Transient
    var isExpired: Bool {
        guard let days = daysUntilUseBy else {
            return false
        }
        return days < 0
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
        brand: String = "",
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
        self.brand = brand
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
