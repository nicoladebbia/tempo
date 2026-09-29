//
// ReceiptProductMatcherTests.swift
// Tempo
//
// Covers ReceiptProductMatcher.findExactMatch (ranking, threshold, size
// bonus, caching) against an injected fake FoodProductProviding — no real
// network calls, so the suite stays deterministic and offline — plus
// ReceiptSizeInference.infer (catalog-seed exact match, price-based
// ranking, ambiguous-pair handling).
//

@testable import Tempo
import XCTest

// MARK: - Fixtures

private extension FoodProduct {
    static func sample(
        id: String = "1",
        name: String = "Greek Yogurt 0% Fat",
        brand: String? = "Publix",
        quantityLabel: String? = nil
    ) -> FoodProduct {
        FoodProduct(
            id: id,
            barcode: id,
            name: name,
            brand: brand,
            source: .openFoodFacts,
            quantityLabel: quantityLabel,
            per100g: .init(kcal: 60, protein: 10, carbs: 4, sugars: 4, fat: 0.2, saturatedFat: 0.1, fiber: 0, salt: 0.1)
        )
    }
}

// MARK: - FakeProductProvider

/// Injected fake — no network. Returns `resultsByQuery[query]` if present,
/// else `defaultResults`; counts calls so tests can assert on caching.
private final class FakeProductProvider: FoodProductProviding, @unchecked Sendable {
    var resultsByQuery: [String: [FoodProduct]] = [:]
    var defaultResults: [FoodProduct] = []
    var searchCallCount = 0

    func product(barcode _: String) async throws -> FoodProduct? {
        nil
    }

    func search(_ query: String, limit _: Int) async throws -> [FoodProduct] {
        searchCallCount += 1
        return resultsByQuery[query] ?? defaultResults
    }

    func alternatives(for _: FoodProduct, limit _: Int) async throws -> [FoodProduct] {
        []
    }
}

// MARK: - ReceiptProductMatcherRankingTests

final class ReceiptProductMatcherRankingTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await ReceiptProductMatcher.resetCacheForTesting()
    }

    func testCorrectCandidateScoresHighestAndClearsThreshold() async throws {
        let provider = FakeProductProvider()
        let good = FoodProduct.sample(id: "good", name: "Greek Yogurt 0% Fat", brand: "Publix")
        let unrelated = FoodProduct.sample(id: "bad", name: "Chocolate Bar", brand: "Hershey")
        provider.defaultResults = [unrelated, good]

        let result = try await ReceiptProductMatcher.findExactMatch(
            readableName: "Publix Greek Yogurt 0% Fat",
            matchedBrand: "Publix",
            rawText: "PUB GRK YOG 0%",
            sizeValue: nil,
            sizeUnit: nil,
            paidPrice: 4.99,
            storeChain: "publix",
            provider: provider
        )

        let candidate = try XCTUnwrap(result)
        XCTAssertEqual(candidate.product.id, "good")
        XCTAssertGreaterThanOrEqual(candidate.matchScore, 0.6)
    }

    func testAllBadCandidatesReturnNilRatherThanForceAMatch() async throws {
        let provider = FakeProductProvider()
        provider.defaultResults = [
            FoodProduct.sample(id: "1", name: "Chocolate Bar", brand: "Hershey"),
            FoodProduct.sample(id: "2", name: "Frozen Pizza", brand: "DiGiorno"),
        ]

        let result = try await ReceiptProductMatcher.findExactMatch(
            readableName: "Publix Greek Yogurt 0% Fat",
            matchedBrand: "Publix",
            rawText: "PUB GRK YOG 0% NIL",
            sizeValue: nil,
            sizeUnit: nil,
            paidPrice: 4.99,
            storeChain: "publix",
            provider: provider
        )

        XCTAssertNil(result, "Stays at food-level rather than forcing a wrong exact match")
    }

    func testSizeMatchBreaksTheTieBetweenIdenticallyNamedCandidates() async throws {
        let provider = FakeProductProvider()
        let wrongSize = FoodProduct.sample(id: "small", name: "Greek Yogurt 0% Fat", brand: "Publix", quantityLabel: "150 g")
        let rightSize = FoodProduct.sample(id: "big", name: "Greek Yogurt 0% Fat", brand: "Publix", quantityLabel: "907 g")
        provider.defaultResults = [wrongSize, rightSize]

        let result = try await ReceiptProductMatcher.findExactMatch(
            readableName: "Publix Greek Yogurt 0% Fat",
            matchedBrand: "Publix",
            rawText: "PUB GRK YOG 0% SIZE",
            sizeValue: 32,
            sizeUnit: "oz",
            paidPrice: 4.99,
            storeChain: "publix",
            provider: provider
        )

        let candidate = try XCTUnwrap(result)
        XCTAssertEqual(candidate.product.id, "big", "907 g ≈ 32 oz should outscore the 150 g candidate")
        XCTAssertEqual(candidate.sizeSource, "printed_on_receipt")
    }

    func testRepeatedLookupForSameLineOnlyQueriesProviderOnce() async throws {
        let provider = FakeProductProvider()
        provider.defaultResults = [FoodProduct.sample(id: "good", name: "Greek Yogurt 0% Fat", brand: "Publix")]

        func lookup() async throws -> ReceiptProductCandidate? {
            try await ReceiptProductMatcher.findExactMatch(
                readableName: "Publix Greek Yogurt 0% Fat",
                matchedBrand: "Publix",
                rawText: "PUB GRK YOG 0% CACHE",
                sizeValue: nil,
                sizeUnit: nil,
                paidPrice: 4.99,
                storeChain: "publix",
                provider: provider
            )
        }

        let first = try await lookup()
        let callsAfterFirst = provider.searchCallCount
        XCTAssertGreaterThan(callsAfterFirst, 0)

        let second = try await lookup()
        XCTAssertEqual(provider.searchCallCount, callsAfterFirst, "Second lookup for the same line hits the cache, not the provider")
        XCTAssertEqual(first?.product.id, second?.product.id)
    }

    func testRepeatedMissForSameLineOnlyQueriesProviderOnce() async throws {
        let provider = FakeProductProvider()
        provider.defaultResults = [FoodProduct.sample(id: "1", name: "Chocolate Bar", brand: "Hershey")]

        func lookup() async throws -> ReceiptProductCandidate? {
            try await ReceiptProductMatcher.findExactMatch(
                readableName: "Publix Greek Yogurt 0% Fat",
                matchedBrand: "Publix",
                rawText: "PUB GRK YOG 0% MISS",
                sizeValue: nil,
                sizeUnit: nil,
                paidPrice: 4.99,
                storeChain: "publix",
                provider: provider
            )
        }

        let first = try await lookup()
        XCTAssertNil(first)
        let callsAfterFirst = provider.searchCallCount

        let second = try await lookup()
        XCTAssertNil(second)
        XCTAssertEqual(provider.searchCallCount, callsAfterFirst, "A cached negative result doesn't re-query the provider")
    }

    func testBrandIsStrippedBackOutOfTheReadableNameBeforeQuerying() {
        let queries = ReceiptProductMatcher.searchQueries(readableName: "Publix Greek Yogurt 0% Fat", matchedBrand: "Publix")
        XCTAssertTrue(queries.contains("Publix Greek Yogurt 0% Fat"), "With-brand query keeps the brand exactly once")
        XCTAssertTrue(queries.contains("Greek Yogurt 0% Fat"), "Falls back to a brand-less query")
        XCTAssertFalse(queries.contains("Publix Publix Greek Yogurt 0% Fat"), "Never double-prepends the brand")
    }
}

// MARK: - ReceiptSizeInferenceTests

final class ReceiptSizeInferenceTests: XCTestCase {
    private let yogurtFamily = BrandCatalogSeed.familyCandidates(forFamilyKey: "publix-greek-yogurt-nonfat-plain")
    private let milkFamily = BrandCatalogSeed.familyCandidates(forFamilyKey: "gv-whole-milk")

    func testCatalogSeedLoadsAtLeastSixFamilies() {
        let familyKeys = Set(BrandCatalogSeed.all.map(\.familyKey))
        XCTAssertGreaterThanOrEqual(familyKeys.count, 6)
        for key in familyKeys {
            XCTAssertGreaterThanOrEqual(BrandCatalogSeed.familyCandidates(forFamilyKey: key).count, 2, "Family \(key) should have 2+ sizes")
        }
    }

    func testExactSizeMatchFromCatalogWinsAtFullConfidenceWhenSizeIsPrinted() {
        XCTAssertFalse(yogurtFamily.isEmpty)
        let candidates = ReceiptSizeInference.infer(
            canonicalFoodName: "greek yogurt",
            paidPrice: 4.99,
            familyCandidates: yogurtFamily,
            storeChain: "publix",
            printedSizeValue: 32,
            printedSizeUnit: "oz"
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.sizeValue, 32)
        XCTAssertEqual(candidates.first?.sizeUnit, "oz")
        XCTAssertEqual(candidates.first?.confidence, 1.0)
    }

    func testPriceBasedInferencePicksTheCloserSeededSizeWhenNoSizeIsPrinted() {
        XCTAssertFalse(milkFamily.isEmpty)
        // 1 gal whole milk at ~$0.007/g ≈ 3785g × 0.007 ≈ $26.5 — pick a price
        // close to the half-gallon's expected value (~$13.25) instead.
        let candidates = ReceiptSizeInference.infer(
            canonicalFoodName: "whole milk",
            paidPrice: 3.49,
            familyCandidates: milkFamily,
            storeChain: "walmart"
        )

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(candidates.first?.sizeValue, 0.5, "The half-gallon's expected price is closer to what was paid")
        XCTAssertEqual(candidates.first?.sizeUnit, "gal")
    }

    func testAmbiguousPriceReturnsBothCandidatesWithinFifteenPercent() {
        // Rig two synthetic family candidates whose expected prices land
        // within 15% of each other for a food with a seeded price table.
        let family = [
            BrandCatalogSeedEntry(
                brand: "Test",
                chain: "test",
                familyKey: "x",
                name: "Test Milk A",
                sizeValue: 900,
                sizeUnit: "g",
                packCount: nil,
                barcode: nil
            ),
            BrandCatalogSeedEntry(
                brand: "Test",
                chain: "test",
                familyKey: "x",
                name: "Test Milk B",
                sizeValue: 950,
                sizeUnit: "g",
                packCount: nil,
                barcode: nil
            ),
        ]
        // Expected @ $0.007/g: A = $6.30, B = $6.65 — within 15% of each other.
        let candidates = ReceiptSizeInference.infer(
            canonicalFoodName: "milk",
            paidPrice: 6.45,
            familyCandidates: family,
            storeChain: nil
        )

        XCTAssertEqual(candidates.count, 2, "Two candidates within ~15% of each other in expected price stay ambiguous")
    }

    func testEmptyFamilyCandidatesReturnsNoSizeCandidates() {
        let candidates = ReceiptSizeInference.infer(
            canonicalFoodName: "greek yogurt",
            paidPrice: 4.99,
            familyCandidates: [],
            storeChain: "publix"
        )
        XCTAssertTrue(candidates.isEmpty)
    }
}

// MARK: - ReceiptSizeMathTests

final class ReceiptSizeMathTests: XCTestCase {
    func testGramsEquivalentConvertsCommonUnits() throws {
        XCTAssertEqual(ReceiptSizeMath.gramsEquivalent(value: 1, unit: "kg"), 1000)
        XCTAssertEqual(try XCTUnwrap(ReceiptSizeMath.gramsEquivalent(value: 1, unit: "gal")), 3785.41, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(ReceiptSizeMath.gramsEquivalent(value: 32, unit: "oz")), 907.184, accuracy: 0.01)
        XCTAssertNil(ReceiptSizeMath.gramsEquivalent(value: 1, unit: "smoots"))
    }

    func testGramsEquivalentFromLabelParsesFreeTextAndMultipacks() throws {
        XCTAssertEqual(ReceiptSizeMath.gramsEquivalent(fromLabel: "500 g"), 500)
        XCTAssertEqual(ReceiptSizeMath.gramsEquivalent(fromLabel: "1 L"), 1000)
        XCTAssertEqual(try XCTUnwrap(ReceiptSizeMath.gramsEquivalent(fromLabel: "32 fl oz")), 907.184, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(ReceiptSizeMath.gramsEquivalent(fromLabel: "6 x 33 cl")), 6 * 330, accuracy: 0.01)
        XCTAssertNil(ReceiptSizeMath.gramsEquivalent(fromLabel: ""))
    }
}
