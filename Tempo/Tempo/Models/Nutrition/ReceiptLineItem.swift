//
// ReceiptLineItem.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - ReceiptLineUnit

// Receipt prints almost always use lb/oz/each; gram/kilogram are rare on US
// receipts but supported for parity with PantryUnit.

enum ReceiptLineUnit: String, Codable, CaseIterable, Sendable {
    case pounds = "lb"
    case ounces = "oz"
    case kilograms = "kg"
    case grams = "g"
    case milliliters = "ml"
    case liters = "l"
    case each
    case unit
    // Container/multipack units. The backend structuring prompt can emit
    // these for items the receipt sells by package rather than by weight
    // (e.g. a 4-pack of Oikos, a can of beans, a jar of salsa, a bottle
    // of oil). Without these cases the decoder fell back to `.unit` →
    // `.pieces`, collapsing "4-pack" into "4 pieces" and losing the
    // package semantics.
    case pack
    case can
    case bottle
    case jar

    /// Map to a PantryUnit for ingest. Weight units (lb/oz/kg/g) and
    /// volume units (ml/l) convert later via quantityGrams, but the chosen
    /// pantry unit follows the receipt verbatim — a `lb` receipt line
    /// creates a `pounds` pantry entry, a `pack` line creates a `packs`
    /// entry, etc.
    var asPantryUnit: PantryUnit {
        switch self {
        case .pounds: .pounds
        case .ounces: .ounces
        case .kilograms: .kilograms
        case .grams: .grams
        case .milliliters: .milliliters
        case .liters: .liters
        case .each,
             .unit: .pieces
        case .pack: .packs
        case .can: .cans
        case .bottle: .bottles
        case .jar: .jars
        }
    }
}

// MARK: - ReceiptLineItem

@Model
final class ReceiptLineItem {
    @Attribute(.unique)
    var id: UUID

    /// Parent receipt (nullify on delete — cascade owns lifecycle from Receipt side).
    @Relationship(deleteRule: .nullify)
    var receipt: Receipt?

    // MARK: - Raw text + canonical

    /// Exactly as printed: "GV CHKN BRST 1.32LB", "BANANAS 0.69 LB".
    var rawText: String

    /// Output of FoodCanonicalizer.canonicalize.
    var canonicalFoodName: String

    /// Output of FoodCanonicalizer.displayName.
    var displayName: String

    // MARK: - Quantity + price

    var quantity: Double

    var unitRaw: String

    /// Normalized grams when known — used for $/kg trend analytics.
    var quantityGrams: Double?

    var unitPrice: Double?

    var totalPrice: Double

    var pricePerKg: Double?

    // MARK: - Sale info

    var onSale: Bool

    /// "BOGO", "2 for $5", etc. Free-text.
    var saleNote: String?

    // MARK: - Confidence + review

    /// OCR / Haiku confidence in this line. 0.0–1.0.
    var confidence: Double

    /// Becomes `true` when the user approves this line in the review UI.
    var userConfirmed: Bool

    /// Household/pharmacy/gift-card/etc — not a pantry food item. Shown
    /// with a "not food" chip in review and excluded from ingest by default.
    var isNonFood: Bool = false

    /// Deposit/CRV/bag fee line — not food, not a discount.
    var isFee: Bool = false

    /// Printed tax flag as-is ("F", "T", "FT", "N"...). Free-text, store-specific.
    var taxFlag: String?

    /// Department/category header seen nearest above this line ("PRODUCE"...).
    var categoryHint: String?

    /// Per-line discount already folded into totalPrice, surfaced separately
    /// for display ("−$1.00 coupon applied").
    var lineDiscount: Double?

    /// Pantry item ID created from this line on confirm. Lets us undo the
    /// ingestion (and prevent double-ingest if the user confirms twice).
    var linkedPantryItemID: UUID?

    var createdAt: Date

    // MARK: - Product match (ReceiptProductMatcher, run in the background

    // after structuring; all optional — nil until/unless a confident match
    // is found, so review never blocks on this and older rows with none of
    // these set keep working exactly as before).

    /// Open Food Facts barcode of the matched product, when found.
    var barcode: String?

    /// Matched product's brand, distinct from `ReceiptResolvedItem.matchedBrand`
    /// (a store-prefix guess) — this one is the OFF product's own brand field.
    var brand: String?

    /// Package size value inferred or matched, e.g. 32 from "32 oz".
    var sizeValue: Double?

    /// Package size unit paired with `sizeValue`, e.g. "oz", "l", "kg".
    var sizeUnit: String?

    /// Pack/multipack count, e.g. 4 from a 4-pack of yogurt cups.
    var packCount: Int?

    /// Matched product's photo URL (OFF image), for the review row + picker.
    var imageURL: String?

    /// 0...1 confidence from `ReceiptProductMatcher.compositeScore` — distinct
    /// from `confidence` (OCR/structuring confidence) above.
    var matchConfidence: Double?

    // MARK: - Computed

    @Transient
    var unit: ReceiptLineUnit {
        get { ReceiptLineUnit(rawValue: unitRaw) ?? .unit }
        set { unitRaw = newValue.rawValue }
    }

    @Transient
    var isIngested: Bool {
        linkedPantryItemID != nil
    }

    // MARK: - Pantry unit resolution

    /// Resolves the right `PantryUnit` to use when ingesting this line into
    /// the pantry. Receipt OCR units (`each` / `unit` / `lb` / `oz` / `kg`
    /// / `g`) are coarse — `1 EA` of black beans is almost certainly a can,
    /// not "a piece." This method upgrades `.pieces` rows to the
    /// container-shaped `PantryUnit` (`.cans`, `.bottles`, `.jars`,
    /// `.packs`) when the canonical name has a container `purchaseUnit`
    /// in `FoodMacroDatabase.naturalPortions`.
    ///
    /// Conservative on purpose: only upgrades when the natural portion's
    /// `purchaseUnit` is a container word. Piece-like purchase units
    /// (egg, banana, breast, slice) stay as `.pieces` — that's already
    /// the honest semantic for those foods.
    var resolvedPantryUnit: PantryUnit {
        let base = unit.asPantryUnit
        guard base == .pieces else {
            return base
        }
        guard let portion = FoodMacroDatabase.naturalPortions[canonicalFoodName.lowercased()] else {
            return base
        }
        return Self.containerPantryUnit(for: portion.purchaseUnit) ?? base
    }

    /// The pantry unit to ingest with when `ReceiptProductMatcher`/size
    /// inference found a package size (`sizeValue` + `sizeUnit`) — a more
    /// specific, product-accurate unit than the receipt's own printed unit
    /// (which is often just "EA"). Falls back to `resolvedPantryUnit` when
    /// no size is known, or the size's unit has no `PantryUnit` equivalent.
    @Transient
    var ingestPantryUnit: PantryUnit {
        guard let sizeUnit else {
            return resolvedPantryUnit
        }
        switch sizeUnit.lowercased() {
        case "g": return .grams
        case "kg": return .kilograms
        case "ml": return .milliliters
        case "l": return .liters
        case "oz": return .ounces
        case "lb": return .pounds
        default: return resolvedPantryUnit
        }
    }

    /// The quantity to ingest with, in `ingestPantryUnit`'s terms — "size ×
    /// count" when a package size is known: e.g. a 4-pack of 5.3oz cups
    /// bought ×1 (`quantity`) ingests as 4 × 5.3 = 21.2 oz, not "1 piece".
    /// Falls back to the receipt's own printed `quantity` when no size is
    /// known (unchanged behavior for lines with no product match).
    @Transient
    var ingestQuantity: Double {
        guard let sizeValue, sizeUnit != nil else {
            return quantity
        }
        let unitsPurchased = quantity > 0 ? quantity : 1
        return sizeValue * Double(packCount ?? 1) * unitsPurchased
    }

    /// Map a natural-portion `purchaseUnit` string → the matching
    /// container `PantryUnit`. Returns nil for piece-like words so the
    /// caller knows the receipt line genuinely is a "piece" (one egg,
    /// one banana, one breast).
    private static func containerPantryUnit(for purchaseUnit: String) -> PantryUnit? {
        let word = purchaseUnit.lowercased()
        if word.contains("can") {
            return .cans
        }
        if word.contains("bottle") {
            return .bottles
        }
        if word.contains("jar") {
            return .jars
        }
        if word.contains("pack") || word.contains("box") || word.contains("bag") || word.contains("tub") || word.contains("tube") || word
            .contains("tin")
        {
            return .packs
        }
        return nil
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        receipt: Receipt? = nil,
        rawText: String,
        canonicalFoodName: String,
        displayName: String,
        quantity: Double,
        unit: ReceiptLineUnit,
        quantityGrams: Double? = nil,
        unitPrice: Double? = nil,
        totalPrice: Double,
        pricePerKg: Double? = nil,
        onSale: Bool = false,
        saleNote: String? = nil,
        confidence: Double = 1.0,
        userConfirmed: Bool = false,
        linkedPantryItemID: UUID? = nil,
        isNonFood: Bool = false,
        isFee: Bool = false,
        taxFlag: String? = nil,
        categoryHint: String? = nil,
        lineDiscount: Double? = nil,
        barcode: String? = nil,
        brand: String? = nil,
        sizeValue: Double? = nil,
        sizeUnit: String? = nil,
        packCount: Int? = nil,
        imageURL: String? = nil,
        matchConfidence: Double? = nil
    ) {
        self.id = id
        self.receipt = receipt
        self.rawText = rawText
        self.canonicalFoodName = canonicalFoodName
        self.displayName = displayName
        // Receipts can't have negative quantities; clamp to keep pantry math sound.
        self.quantity = max(0, quantity)
        self.unitRaw = unit.rawValue
        self.quantityGrams = quantityGrams
        self.unitPrice = unitPrice
        self.totalPrice = totalPrice
        self.pricePerKg = pricePerKg
        self.onSale = onSale
        self.saleNote = saleNote
        self.confidence = max(0, min(1, confidence))
        self.userConfirmed = userConfirmed
        self.linkedPantryItemID = linkedPantryItemID
        self.isNonFood = isNonFood
        self.isFee = isFee
        self.taxFlag = taxFlag
        self.categoryHint = categoryHint
        self.lineDiscount = lineDiscount
        self.barcode = barcode
        self.brand = brand
        self.sizeValue = sizeValue
        self.sizeUnit = sizeUnit
        self.packCount = packCount
        self.imageURL = imageURL
        self.matchConfidence = matchConfidence
        self.createdAt = Date()
    }
}

// MARK: - DTO

extension ReceiptLineItem {
    struct DTO: Codable, Sendable {
        let id: UUID
        let raw_text: String
        let canonical_food_name: String
        let display_name: String
        let quantity: Double
        let unit: String
        let quantity_grams: Double?
        let unit_price: Double?
        let total_price: Double
        let price_per_kg: Double?
        let on_sale: Bool
        let sale_note: String?
        let confidence: Double
        let user_confirmed: Bool
        let linked_pantry_item_id: UUID?
        let is_non_food: Bool
        let is_fee: Bool
        let tax_flag: String?
        let category_hint: String?
        let line_discount: Double?
        let created_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            raw_text: rawText,
            canonical_food_name: canonicalFoodName,
            display_name: displayName,
            quantity: quantity,
            unit: unitRaw,
            quantity_grams: quantityGrams,
            unit_price: unitPrice,
            total_price: totalPrice,
            price_per_kg: pricePerKg,
            on_sale: onSale,
            sale_note: saleNote,
            confidence: confidence,
            user_confirmed: userConfirmed,
            linked_pantry_item_id: linkedPantryItemID,
            is_non_food: isNonFood,
            is_fee: isFee,
            tax_flag: taxFlag,
            category_hint: categoryHint,
            line_discount: lineDiscount,
            created_at: createdAt
        )
    }
}
