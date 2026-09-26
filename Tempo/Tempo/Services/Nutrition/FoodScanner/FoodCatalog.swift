//
// FoodCatalog.swift
// Tempo
//
// One entry point for everything the food search, barcode scanner and
// product screen need:
//   lookUp(barcode:)   your own added products → Open Food Facts
//   search(_:)         yours (favourites/history) + basics (Tempo's built-in
//                      table, USDA via backend) + packaged products (OFF);
//                      each source fails on its own, the rest still show
//   alternatives(for:) better-scoring products in the same category
//   history / favourites / user-added products (ScannedFood, SwiftData)
//

import Foundation
import os
import SwiftData

// MARK: - FoodCatalog

@MainActor
final class FoodCatalog {
    enum LookupResult: Equatable {
        case found(FoodProduct)
        case notFound(barcode: String)
        case failed(String)
    }

    struct SearchResults: Equatable {
        var yours: [FoodProduct] = []
        var basics: [FoodProduct] = []
        var products: [FoodProduct] = []
        /// Sources that failed, as user-facing text ("Packaged products unavailable — you're offline").
        var notices: [String] = []

        var isEmpty: Bool {
            yours.isEmpty && basics.isEmpty && products.isEmpty
        }
    }

    private let products: any FoodProductProviding
    private let generic: (any GenericFoodSearching)?
    private let logger = Logger.nutrition

    init(products: any FoodProductProviding, generic: (any GenericFoodSearching)?) {
        self.products = products
        self.generic = generic
    }

    convenience init(services: ServiceContainer) {
        self.init(products: OpenFoodFactsClient(), generic: USDAFoodClient(apiClient: services.apiClient))
    }

    // MARK: - Barcode

    func lookUp(barcode: String, in context: ModelContext) async -> LookupResult {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty else {
            return .notFound(barcode: barcode)
        }
        let saved = record(for: code, in: context)
        if let saved, saved.isUserAdded, let product = saved.product {
            recordView(product, in: context)
            return .found(product)
        }
        do {
            if let product = try await products.product(barcode: code) {
                recordView(product, in: context)
                return .found(product)
            }
            return .notFound(barcode: code)
        } catch {
            // Offline / rate-limited: a product seen before still opens.
            if let cached = saved?.product {
                return .found(cached)
            }
            return .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't look up this barcode. Try again.")
        }
    }

    // MARK: - Search

    /// Local results only — instant, shown while the network sources load.
    func localResults(for query: String, in context: ModelContext) -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 2 else {
            return SearchResults()
        }
        let saved = (try? context.fetch(FetchDescriptor<ScannedFood>(
            predicate: #Predicate { $0.searchText.contains(trimmed) },
            sortBy: [SortDescriptor(\.lastViewedAt, order: .reverse)]
        ))) ?? []
        let yours = saved
            .sorted { ($0.isFavorite ? 1 : 0, $0.viewCount) > ($1.isFavorite ? 1 : 0, $1.viewCount) }
            .prefix(6)
            .compactMap(\.product)
        return SearchResults(yours: Array(yours), basics: Self.builtInMatches(trimmed, limit: 5))
    }

    func search(_ query: String, in context: ModelContext) async -> SearchResults {
        var results = localResults(for: query, in: context)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return results
        }
        let products = products
        let generic = generic
        async let packaged = Result { try await products.search(trimmed, limit: 20) }
        async let basics = Result { try await generic?.search(trimmed, limit: 10) ?? [] }

        let known = Set(results.yours.map(\.id))
        switch await packaged {
        case let .success(found):
            results.products = found.filter { !known.contains($0.id) && $0.per100g.hasCoreMacros }
        case let .failure(error):
            logger.warning("[food] OFF search failed: \(String(describing: error), privacy: .public)")
            results.notices.append(Self.notice("Packaged products", error))
        }
        switch await basics {
        case let .success(found):
            let builtInNames = Set(results.basics.map { $0.name.lowercased() })
            results.basics += found.filter { !builtInNames.contains($0.name.lowercased()) }
        case let .failure(error):
            // Signed out → USDA is simply skipped; the built-in table still answers.
            if case APIError.unauthorized = error {
                break
            }
            logger.warning("[food] USDA search failed: \(String(describing: error), privacy: .public)")
            results.notices.append(Self.notice("Basic foods", error))
        }
        return results
    }

    // MARK: - Alternatives

    /// Up to `limit` products from the same category that score higher —
    /// ones with a photo first (a wall of blank tiles helps nobody), then by score.
    func alternatives(for product: FoodProduct, limit: Int = 5) async -> [FoodProduct] {
        guard let current = FoodScore.evaluate(product), current.rating != .excellent else {
            return []
        }
        do {
            let candidates = try await products.alternatives(for: product, limit: 30)
            return candidates
                .compactMap { candidate in FoodScore.evaluate(candidate).map { (candidate, $0.total) } }
                .filter { $0.1 > current.total }
                .sorted { lhs, rhs in
                    let lp = lhs.0.imageURL != nil, rp = rhs.0.imageURL != nil
                    return lp != rp ? lp : lhs.1 > rhs.1
                }
                .prefix(limit)
                .map(\.0)
        } catch {
            logger.warning("[food] alternatives failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: - History & favourites

    func recordView(_ product: FoodProduct, in context: ModelContext, now: Date = Date()) {
        if let existing = record(for: product.id, in: context) {
            if !existing.isUserAdded {
                existing.update(with: product)
            }
            existing.lastViewedAt = now
            existing.viewCount += 1
        } else {
            context.insert(ScannedFood(product: product, now: now))
        }
        save(context)
    }

    func isFavorite(_ product: FoodProduct, in context: ModelContext) -> Bool {
        record(for: product.id, in: context)?.isFavorite ?? false
    }

    @discardableResult
    func toggleFavorite(_ product: FoodProduct, in context: ModelContext) -> Bool {
        let row = record(for: product.id, in: context) ?? {
            let new = ScannedFood(product: product)
            context.insert(new)
            return new
        }()
        row.isFavorite.toggle()
        save(context)
        return row.isFavorite
    }

    func history(in context: ModelContext, limit: Int = 50) -> [ScannedFood] {
        var descriptor = FetchDescriptor<ScannedFood>(sortBy: [SortDescriptor(\.lastViewedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func favorites(in context: ModelContext) -> [ScannedFood] {
        (try? context.fetch(FetchDescriptor<ScannedFood>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
    }

    /// A product the user added by photographing its label.
    func saveUserAdded(_ product: FoodProduct, photo: Data?, in context: ModelContext) {
        if let existing = record(for: product.id, in: context) {
            existing.update(with: product)
            existing.isUserAdded = true
            existing.photoData = photo ?? existing.photoData
            existing.lastViewedAt = Date()
        } else {
            context.insert(ScannedFood(product: product, isUserAdded: true, photoData: photo))
        }
        save(context)
    }

    func photo(for product: FoodProduct, in context: ModelContext) -> Data? {
        record(for: product.id, in: context)?.photoData
    }

    /// The user's own picture for a product Open Food Facts has no photo of.
    func setPhoto(_ photo: Data, for product: FoodProduct, in context: ModelContext) {
        if let existing = record(for: product.id, in: context) {
            existing.photoData = photo
        } else {
            context.insert(ScannedFood(product: product, photoData: photo))
        }
        save(context)
    }

    func remove(_ row: ScannedFood, in context: ModelContext) {
        context.delete(row)
        save(context)
    }

    // MARK: - Built-in table

    static func builtInMatches(_ query: String, limit: Int) -> [FoodProduct] {
        let q = query.lowercased()
        return FoodMacroDatabase.macrosPer100g
            .filter { $0.key.contains(q) }
            .sorted { lhs, rhs in
                let lp = lhs.key.hasPrefix(q), rp = rhs.key.hasPrefix(q)
                return lp != rp ? lp : lhs.key.count < rhs.key.count
            }
            .prefix(limit)
            .map { builtInProduct(name: $0.key, macros: $0.value) }
    }

    static func builtInProduct(name: String, macros: FoodMacros) -> FoodProduct {
        FoodProduct(
            id: "builtin:\(name)",
            name: name.prefix(1).uppercased() + name.dropFirst(),
            source: .builtIn,
            per100g: FoodProduct.Nutrients(
                kcal: macros.calories, protein: macros.protein, carbs: macros.carbs,
                fat: macros.fat, fiber: macros.fiber
            )
        )
    }

    // MARK: - Private

    private func record(for id: String, in context: ModelContext) -> ScannedFood? {
        (try? context.fetch(FetchDescriptor<ScannedFood>(predicate: #Predicate { $0.productID == id })))?.first
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.error("[food] save failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func notice(_ source: String, _ error: Error) -> String {
        if let lookup = error as? FoodLookupError, lookup == .offline {
            return "\(source) unavailable — you're offline."
        }
        return "\(source) unavailable right now."
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do {
            self = try await .success(body())
        } catch {
            self = .failure(error)
        }
    }
}
