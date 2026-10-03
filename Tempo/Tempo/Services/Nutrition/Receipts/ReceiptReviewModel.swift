//
// ReceiptReviewModel.swift
// Tempo
//
// Pure logic behind the receipt review screen: which lines "need a look",
// how lines are grouped and sorted, which lines go to the pantry, and when a
// product photo may be shown. No SwiftUI in here so it is unit-testable.
//

import Foundation
import Observation

// MARK: - ReceiptReviewSection

enum ReceiptReviewSection: Int, CaseIterable, Hashable, Sendable {
    case needsLook
    case fridge
    case freezer
    case pantry
    case notFood

    var title: String {
        switch self {
        case .needsLook: "Needs a look"
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        case .notFood: "Not food"
        }
    }

    var icon: String {
        switch self {
        case .needsLook: "exclamationmark.circle.fill"
        case .fridge: PantryStorageLocation.fridge.icon
        case .freezer: PantryStorageLocation.freezer.icon
        case .pantry: PantryStorageLocation.pantry.icon
        case .notFood: "cart.badge.minus"
        }
    }

    static func food(for location: PantryStorageLocation) -> ReceiptReviewSection {
        switch location {
        case .fridge: .fridge
        case .freezer: .freezer
        case .pantry,
             .cupboard: .pantry
        }
    }
}

// MARK: - ReceiptLineEdits

/// Per-line choices made on the review screen. Kept off the SwiftData line
/// so tapping around never mutates the receipt until "Add to pantry".
struct ReceiptLineEdits: Equatable, Sendable {
    var storage: PantryStorageLocation?
    var useBy: Date?
    /// Explicit include/exclude. nil = default (food in, non-food out).
    var included: Bool?
    var removed = false
    /// The user opened and saved the row, so it no longer "needs a look".
    var reviewed = false
    /// The user picked the product themselves in the edit sheet.
    var pickedProduct = false
}

// MARK: - ReceiptProductPhoto

/// A product photo is shown ONLY for a confident match to a real product
/// that has an image. Never a guessed photo — otherwise a category icon.
enum ReceiptProductPhoto {
    static let minimumMatchConfidence = 0.6

    static func url(imageURL: String?, barcode: String?, matchConfidence: Double?, userPicked: Bool) -> URL? {
        guard let barcode, !barcode.trimmingCharacters(in: .whitespaces).isEmpty,
              let imageURL, let url = URL(string: imageURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            return nil
        }
        if userPicked || (matchConfidence ?? 0) >= minimumMatchConfidence {
            return url
        }
        return nil
    }

    /// SF Symbol per food category, shown whenever there is no photo.
    static func categoryIcon(forCanonicalName name: String, isNonFood: Bool) -> String {
        if isNonFood {
            return "house.fill"
        }
        switch GroceryListGenerator.category(for: name) {
        case "produce": return "leaf.fill"
        case "meat": return "fork.knife"
        case "seafood": return "fish.fill"
        case "dairy": return "drop.fill"
        case "grains": return "basket.fill"
        case "frozen": return "snowflake"
        case "oils": return "drop.triangle.fill"
        default: return "bag.fill"
        }
    }
}

// MARK: - ReceiptIngestOverride

struct ReceiptIngestOverride: Sendable {
    var storage: PantryStorageLocation?
    var useBy: Date?
}

// MARK: - ReceiptReviewModel

@MainActor
@Observable
final class ReceiptReviewModel {
    static let lowConfidenceThreshold = 0.75

    let receipt: Receipt
    private(set) var edits: [UUID: ReceiptLineEdits] = [:]
    /// Last swiped-away line, for the Undo bar.
    private(set) var lastRemoved: ReceiptLineItem?

    init(receipt: Receipt) {
        self.receipt = receipt
    }

    // MARK: Per-line state

    func edit(for line: ReceiptLineItem) -> ReceiptLineEdits {
        edits[line.id] ?? ReceiptLineEdits()
    }

    func update(_ line: ReceiptLineItem, _ change: (inout ReceiptLineEdits) -> Void) {
        var value = edit(for: line)
        change(&value)
        edits[line.id] = value
    }

    func storage(for line: ReceiptLineItem) -> PantryStorageLocation {
        edit(for: line).storage ?? PantryStorageGuesser.guess(forName: line.canonicalFoodName)
    }

    func isNotFood(_ line: ReceiptLineItem) -> Bool {
        line.isNonFood || line.isFee
    }

    func isIncluded(_ line: ReceiptLineItem) -> Bool {
        let value = edit(for: line)
        if value.removed || line.isIngested {
            return false
        }
        return value.included ?? !isNotFood(line)
    }

    /// Rules: a food line needs a look when OCR was unsure, the name is
    /// missing/too short, the price or quantity did not parse, or a product
    /// match exists but is weak. Reviewing the row clears it.
    func needsLook(_ line: ReceiptLineItem) -> Bool {
        let value = edit(for: line)
        if isNotFood(line) || value.reviewed || value.removed || line.isIngested {
            return false
        }
        if line.displayName.trimmingCharacters(in: .whitespaces).count < 2 {
            return true
        }
        if line.confidence < Self.lowConfidenceThreshold {
            return true
        }
        if line.totalPrice <= 0 || line.quantity <= 0 {
            return true
        }
        if let match = line.matchConfidence, line.barcode != nil, match < 0.4 {
            return true
        }
        return false
    }

    func section(for line: ReceiptLineItem) -> ReceiptReviewSection {
        if isNotFood(line) {
            return .notFood
        }
        if needsLook(line) {
            return .needsLook
        }
        return .food(for: storage(for: line))
    }

    func photoURL(for line: ReceiptLineItem) -> URL? {
        ReceiptProductPhoto.url(
            imageURL: line.imageURL,
            barcode: line.barcode,
            matchConfidence: line.matchConfidence,
            userPicked: edit(for: line).pickedProduct
        )
    }

    // MARK: Grouping

    /// Sections in display order (empty ones dropped). Needs-a-look sorts the
    /// least certain first; everything else alphabetically.
    func sections() -> [(section: ReceiptReviewSection, lines: [ReceiptLineItem])] {
        let visible = receipt.orderedLineItems.filter { !edit(for: $0).removed && !$0.isIngested }
        var buckets: [ReceiptReviewSection: [ReceiptLineItem]] = [:]
        for line in visible {
            buckets[section(for: line), default: []].append(line)
        }
        return ReceiptReviewSection.allCases.compactMap { section in
            guard var lines = buckets[section], !lines.isEmpty else {
                return nil
            }
            if section == .needsLook {
                lines.sort { ($0.confidence, $0.displayName) < ($1.confidence, $1.displayName) }
            } else {
                lines.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            return (section, lines)
        }
    }

    // MARK: Totals

    var includedLines: [ReceiptLineItem] {
        receipt.orderedLineItems.filter(isIncluded)
    }

    var includedCount: Int {
        includedLines.count
    }

    var needsLookCount: Int {
        receipt.orderedLineItems.filter(needsLook).count
    }

    // MARK: Remove / undo

    func remove(_ line: ReceiptLineItem) {
        update(line) { $0.removed = true }
        lastRemoved = line
    }

    func undoRemove() {
        if let line = lastRemoved {
            update(line) { $0.removed = false }
        }
        lastRemoved = nil
    }

    func dismissUndo() {
        lastRemoved = nil
    }

    // MARK: Commit

    /// Marks exactly the included lines as confirmed (everything else not)
    /// and returns the per-line storage/expiry choices for ingest.
    func commit() -> [UUID: ReceiptIngestOverride] {
        var overrides: [UUID: ReceiptIngestOverride] = [:]
        for line in receipt.orderedLineItems where !line.isIngested {
            let included = isIncluded(line)
            line.userConfirmed = included
            if included {
                overrides[line.id] = ReceiptIngestOverride(storage: storage(for: line), useBy: edit(for: line).useBy)
            }
        }
        return overrides
    }
}
