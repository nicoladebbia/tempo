@testable import App
import Vapor

// MARK: - FakeBrandCatalogRefresher

// Test double for BrandCatalogRefreshing — proves the injection seam works
// without ever making a network call. Same shape as FakeSupplementLookupClient.

final class FakeBrandCatalogRefresher: BrandCatalogRefreshing, @unchecked Sendable {
    private(set) var calledBrands: [String] = []
    private let result: [BrandCatalogItem]

    init(result: [BrandCatalogItem] = []) {
        self.result = result
    }

    func refresh(brand: String, on _: Request) async throws -> [BrandCatalogItem] {
        calledBrands.append(brand)
        return result
    }
}
