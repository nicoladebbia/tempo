//
// ScannedFood.swift
// Tempo
//
// A product the user has looked at (scanned or opened from search), marked
// as a favourite, or added themselves by photographing its label. Holds the
// full FoodProduct as JSON, so history, favourites and user-added products
// work offline and show up first in food search.
//

import Foundation
import SwiftData

@Model
final class ScannedFood {
    /// FoodProduct.id — the barcode for packaged products.
    @Attribute(.unique)
    var productID: String

    var name: String
    var brand: String?
    /// Lowercased name + brand, for local search.
    var searchText: String

    var productJSON: Data
    var lastViewedAt: Date
    var viewCount: Int
    var isFavorite: Bool
    /// Scanned in the app and not found in any database — added by the user.
    var isUserAdded: Bool
    /// The cleaned-up product photo (white background) for user-added items.
    @Attribute(.externalStorage)
    var photoData: Data?

    init(product: FoodProduct, isUserAdded: Bool = false, photoData: Data? = nil, now: Date = Date()) {
        productID = product.id
        name = product.name
        brand = product.brand
        searchText = Self.searchText(for: product)
        productJSON = (try? JSONEncoder().encode(product)) ?? Data()
        lastViewedAt = now
        viewCount = 1
        isFavorite = false
        self.isUserAdded = isUserAdded
        self.photoData = photoData
    }

    var product: FoodProduct? {
        try? JSONDecoder().decode(FoodProduct.self, from: productJSON)
    }

    func update(with product: FoodProduct) {
        name = product.name
        brand = product.brand
        searchText = Self.searchText(for: product)
        if let data = try? JSONEncoder().encode(product) {
            productJSON = data
        }
    }

    static func searchText(for product: FoodProduct) -> String {
        [product.name, product.brand ?? ""].joined(separator: " ").lowercased()
    }
}
