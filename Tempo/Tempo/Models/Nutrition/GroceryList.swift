//
// GroceryList.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - GroceryList

@Model
final class GroceryList {
    @Attribute(.unique)
    var id: UUID

    /// Week-start date (Monday at 00:00, normalized).
    var weekStartDate: Date

    /// Originating meal plan, if any. Nullified on delete.
    var sourceMealPlanID: UUID?

    var generatedAt: Date

    /// `true` when the user has exported this list to Reminders.
    var exportedToReminders: Bool

    var exportedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \GroceryListItem.list)
    var items: [GroceryListItem]?

    /// Plan foods the user deleted from this list. A pantry sync never adds
    /// them back; a fresh Generate starts over. Optional for lightweight
    /// migration.
    var dismissedFoods: [String]?

    @Transient
    var orderedItems: [GroceryListItem] {
        (items ?? []).sorted {
            ($0.category, $0.canonicalFoodName) < ($1.category, $1.canonicalFoodName)
        }
    }

    /// Items still "to shop" — excludes anything already pushed into the
    /// pantry via "Done shopping". Store Mode and the header counters work
    /// off this, not the raw `items` array, so a bought item doesn't keep
    /// inflating "N items" after the trip that bought it is long over.
    @Transient
    var activeItems: [GroceryListItem] {
        orderedItems.filter { !$0.isBought }
    }

    /// Items already confirmed into the pantry — kept as a "bought" record
    /// rather than deleted (per BUILD item 3).
    @Transient
    var boughtItems: [GroceryListItem] {
        orderedItems.filter(\.isBought)
    }

    @Transient
    var itemCount: Int {
        activeItems.count
    }

    @Transient
    var checkedCount: Int {
        activeItems.filter(\.isChecked).count
    }

    @Transient
    var isComplete: Bool {
        let active = activeItems
        guard !active.isEmpty else {
            return false
        }
        return active.allSatisfy(\.isChecked)
    }

    /// Sum of `estimatedPriceUSD` across items still to buy. nil items
    /// (price not resolved yet — no network round trip has completed)
    /// contribute 0, so the total is always displayable, just possibly
    /// incomplete; `hasUnresolvedPrices` tells the UI whether to caveat it.
    @Transient
    var estimatedTotalUSD: Double {
        activeItems.reduce(0) { $0 + ($1.estimatedPriceUSD ?? 0) }
    }

    /// `true` when at least one active item has no price yet (still loading,
    /// offline, or the AI batch hasn't run). Lets the UI show "prices still
    /// loading" instead of implying the total above is final.
    @Transient
    var hasUnresolvedPrices: Bool {
        activeItems.contains { $0.estimatedPriceUSD == nil }
    }

    /// `true` when every priced item's source is an AI guess rather than the
    /// user's own paid history — the UI labels the total "approx" in that case.
    @Transient
    var totalIsApproximate: Bool {
        let priced = activeItems.filter { $0.estimatedPriceUSD != nil }
        guard !priced.isEmpty else {
            return false
        }
        return priced.contains { $0.priceSource == .estimate }
    }

    init(
        id: UUID = UUID(),
        weekStartDate: Date,
        sourceMealPlanID: UUID? = nil
    ) {
        self.id = id
        self.weekStartDate = Calendar.current.startOfDay(for: weekStartDate)
        self.sourceMealPlanID = sourceMealPlanID
        self.generatedAt = Date()
        self.exportedToReminders = false
        self.exportedAt = nil
    }
}

// MARK: - GroceryPriceSource

/// Where an item's `estimatedPriceUSD` came from. "paid" = derived from the
/// user's own PantryPriceEntry history (their real receipt/manual prices);
/// "estimate" = an AI-guessed typical price at the selected chain. The list
/// UI labels "estimate" rows "approx" so a guess is never mistaken for a
/// tracked price.
enum GroceryPriceSource: String, Codable, CaseIterable, Sendable {
    case paid
    case estimate
}

// MARK: - GroceryListItem

@Model
final class GroceryListItem {
    @Attribute(.unique)
    var id: UUID

    @Relationship(deleteRule: .nullify)
    var list: GroceryList?

    /// FoodCanonicalizer.canonicalize output.
    var canonicalFoodName: String

    /// Display label.
    var displayName: String

    /// Aggregated quantity needed (in `unit`).
    var quantity: Double

    var unitRaw: String

    /// Grocery category for sort/group ("produce", "protein", "dairy", "grains", "pantry").
    var category: String

    /// User-checked in the in-app list.
    var isChecked: Bool

    /// `true` for a one-off item the user typed in ("oh, also: olive oil")
    /// rather than one derived from the meal plan. Manual items don't come
    /// from `GroceryListGenerator`, so a regenerate must carry them forward
    /// verbatim instead of dropping them (they'd never be reproduced by
    /// re-aggregating the plan).
    var isManual: Bool = false

    /// `true` once "Done shopping" has pushed this item into the pantry.
    /// The item stays on the list (as a record — "bought") instead of being
    /// deleted, so the shopping trip has a receipt-like trail.
    var isBought: Bool = false

    /// When `isBought` was set. nil until then.
    var boughtAt: Date?

    /// Apple Reminders identifier for this item's exported reminder
    /// (`EKReminder.calendarItemIdentifier`). Set on first export; reused on
    /// re-export so the list updates/removes the SAME reminder instead of
    /// creating a duplicate every time "Export to Reminders" is tapped.
    var reminderIdentifier: String?

    /// Estimated (or actual paid-history-derived) total USD cost for this
    /// line at the currently selected store, for `quantity` units. nil until
    /// GroceryPriceEstimator/GroceryPriceAIService fills it in — pricing
    /// never blocks list generation or display.
    var estimatedPriceUSD: Double?

    /// Raw `GroceryPriceSource`. nil alongside a nil `estimatedPriceUSD`.
    var priceSourceRaw: String?

    /// Optional notes (brand preference, substitutions).
    var notes: String?

    var createdAt: Date

    @Transient
    var unit: PantryUnit {
        get { PantryUnit(rawValue: unitRaw) ?? .grams }
        set { unitRaw = newValue.rawValue }
    }

    @Transient
    var priceSource: GroceryPriceSource? {
        get { priceSourceRaw.flatMap(GroceryPriceSource.init(rawValue:)) }
        set { priceSourceRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        list: GroceryList? = nil,
        canonicalFoodName: String,
        displayName: String,
        quantity: Double,
        unit: PantryUnit,
        category: String = "pantry",
        isChecked: Bool = false,
        isManual: Bool = false,
        isBought: Bool = false,
        boughtAt: Date? = nil,
        reminderIdentifier: String? = nil,
        estimatedPriceUSD: Double? = nil,
        priceSource: GroceryPriceSource? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.list = list
        self.canonicalFoodName = canonicalFoodName
        self.displayName = displayName
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.category = category
        self.isChecked = isChecked
        self.isManual = isManual
        self.isBought = isBought
        self.boughtAt = boughtAt
        self.reminderIdentifier = reminderIdentifier
        self.estimatedPriceUSD = estimatedPriceUSD
        self.priceSourceRaw = priceSource?.rawValue
        self.notes = notes
        self.createdAt = Date()
    }
}

// MARK: - Pantry-restock marker

extension GroceryListItem {
    /// `notes` value stamped on rows `PantryGroceryBridge` creates ("I'm out
    /// of rice", a depleted ingredient). Lets the service tell those apart
    /// from items the user typed in themselves, which a pantry restock must
    /// never delete.
    static let pantryRestockNote = "pantry-restock"

    @Transient
    var isPantryRestock: Bool {
        isManual && notes == Self.pantryRestockNote
    }
}

// MARK: - Display names

extension GroceryListItem {
    /// `true` when `displayName` already leads with the amount ("3 medium
    /// carrots", "1 bag spinach") — purchase-unit rows built by
    /// `GroceryListGenerator`. Showing `quantity + unit` next to it again read
    /// "3 pcs 3 medium carrots" in the share text, the share page and Instacart.
    ///
    /// Only generator-built rows (never `isManual`) qualify: a name the user
    /// typed ("7 up soda", "12 oz coffee", "1 kg bag rice") is theirs and
    /// keeps its separate quantity/unit.
    @Transient
    var displayNameEmbedsQuantity: Bool {
        !isManual && displayName.range(of: #"^\d+(?:[.,]\d+)?\s+\S"#, options: .regularExpression) != nil
    }

    /// Name with no amount in it — what share page / Instacart pair with the
    /// separate quantity + unit fields.
    @Transient
    var quantityFreeName: String {
        guard displayNameEmbedsQuantity else {
            return displayName
        }
        let canonical = FoodCanonicalizer.displayName(canonicalFoodName)
        if !canonical.isEmpty {
            return canonical
        }
        return displayName.replacingOccurrences(of: #"^\d+(?:[.,]\d+)?\s+"#, with: "", options: .regularExpression)
    }

    /// One self-contained line: "3 medium carrots", "500 g Chicken breast".
    @Transient
    var fullLabel: String {
        if displayNameEmbedsQuantity {
            return displayName
        }
        return "\(PantryQuantityFormatter.number(quantity)) \(unit.displayName) \(displayName)"
    }
}
