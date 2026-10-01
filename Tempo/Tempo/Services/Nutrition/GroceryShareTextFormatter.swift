//
// GroceryShareTextFormatter.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation

// MARK: - GroceryShareTextFormatter

/// Formats a `GroceryList` as a plain-text checklist for `ShareLink`
/// ("Share as text") — grouped by aisle, in the same store-walk order as
/// `GroceryListView.groupedCategories`, e.g.:
///
/// ```
/// Grocery List
///
/// PRODUCE
/// ☐ 2 lbs bananas
/// ☑ 1 bag spinach
///
/// DAIRY
/// ☐ 1 gal milk
/// ```
enum GroceryShareTextFormatter {
    /// Mirrors `GroceryListView.groupedCategories`'s preferred order. Kept
    /// as its own copy (rather than reaching into that view) since Lane C
    /// must not depend on Lane A's view internals.
    static let preferredCategoryOrder = [
        "produce", "meat", "seafood", "protein", "dairy", "frozen", "grains", "oils", "pantry",
    ]

    static func text(for list: GroceryList, title: String = "Grocery List") -> String {
        let items = list.activeItems
        guard !items.isEmpty else {
            return title
        }

        let present = Array(Set(items.map(\.category)))
        let known = preferredCategoryOrder.filter { present.contains($0) }
        let unknown = present.filter { !preferredCategoryOrder.contains($0) }.sorted()
        let categories = known + unknown

        var lines = [title, ""]
        for category in categories {
            let categoryItems = items
                .filter { $0.category == category }
                .sorted { $0.canonicalFoodName < $1.canonicalFoodName }
            guard !categoryItems.isEmpty else {
                continue
            }
            lines.append(category.uppercased())
            for item in categoryItems {
                let box = item.isChecked ? "☑" : "☐"
                lines.append("\(box) \(item.fullLabel)")
            }
            lines.append("")
        }

        // Trailing blank line from the last category — trim it.
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
