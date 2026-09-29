//
// GenericFoodImagesTests.swift
// Tempo
//
// Wikipedia title derivation/overrides and the on-disk hit/miss memo
// (GenericFoodImages), and the memory+disk byte cache (FoodImageCache) —
// both with an injected fetcher/loader, never live network.
//

import Foundation
@testable import Tempo
import XCTest

// MARK: - CallCounter

/// A plain `var` mutated inside a `@Sendable` closure trips Swift 6 strict
/// concurrency even when the closure only ever runs serially in a test —
/// this locks the count instead.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - GenericFoodImagesTests

final class GenericFoodImagesTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GenericFoodImagesTests-\(UUID())", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDeriveTitleStripsPercentAndFraction() {
        XCTAssertEqual(GenericFoodImages.deriveTitle(from: "Greek yogurt 0%"), "Greek_yogurt")
        XCTAssertEqual(GenericFoodImages.deriveTitle(from: "Ground beef 90/10"), "Ground_beef")
        XCTAssertEqual(GenericFoodImages.deriveTitle(from: "Chicken breast"), "Chicken_breast")
    }

    func testRewriteThumbnailWidth() {
        let narrow = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Foo.jpg/220px-Foo.jpg"
        XCTAssertEqual(
            GenericFoodImages.rewriteThumbnailWidth(narrow, to: 640),
            "https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Foo.jpg/640px-Foo.jpg"
        )
        // No width segment: left untouched rather than corrupted.
        let noWidth = "https://upload.wikimedia.org/wikipedia/commons/a/b/Foo.jpg"
        XCTAssertEqual(GenericFoodImages.rewriteThumbnailWidth(noWidth, to: 640), noWidth)
    }

    func testCuratedOverridesFixTheAwkwardTitles() {
        XCTAssertEqual(GenericFoodImages.titleOverrides["greek yogurt 0%"], "Strained_yogurt")
        XCTAssertEqual(GenericFoodImages.titleOverrides["chicken breast"], "Chicken_as_food")
        XCTAssertEqual(GenericFoodImages.titleOverrides["eggs"], "Egg_as_food")
    }

    func testResolvesAThumbnailAndRewritesItsWidth() async {
        let json = """
        {"thumbnail":{"source":"https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Chicken.jpg/220px-Chicken.jpg"}}
        """
        let fetcher = GenericFoodImages.Fetcher { _ in .success(Data(json.utf8)) }
        let product = FoodProduct(id: "builtin:chicken breast", name: "Chicken breast", source: .builtIn, per100g: .init(kcal: 165))

        let url = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertEqual(url?.absoluteString, "https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Chicken.jpg/500px-Chicken.jpg")
    }

    func testUsesTheOriginalWhenItIsNarrowerThanTheThumbnailStep() async {
        let json = """
        {"thumbnail":{"source":"https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Kiwi.jpg/330px-Kiwi.jpg","width":330},
         "originalimage":{"source":"https://upload.wikimedia.org/wikipedia/commons/a/b/Kiwi.jpg","width":400}}
        """
        let fetcher = GenericFoodImages.Fetcher { _ in .success(Data(json.utf8)) }
        let product = FoodProduct(id: "builtin:kiwi", name: "Kiwi", source: .builtIn, per100g: .init(kcal: 61))

        let url = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertEqual(url?.absoluteString, "https://upload.wikimedia.org/wikipedia/commons/a/b/Kiwi.jpg")
    }

    func testFallsBackToOriginalImageWhenNoThumbnail() async {
        let json = """
        {"originalimage":{"source":"https://upload.wikimedia.org/wikipedia/commons/a/b/Apple.jpg"}}
        """
        let fetcher = GenericFoodImages.Fetcher { _ in .success(Data(json.utf8)) }
        let product = FoodProduct(id: "builtin:apple", name: "Apple", source: .builtIn, per100g: .init(kcal: 52))

        let url = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertEqual(url?.absoluteString, "https://upload.wikimedia.org/wikipedia/commons/a/b/Apple.jpg")
    }

    /// The exact "Banana" case from picky QA: a real, plain, single-word
    /// built-in name must resolve without any title override.
    func testBananaResolvesWithNoOverrideNeeded() async {
        XCTAssertNil(GenericFoodImages.titleOverrides["banana"], "Banana needs no override — 'Banana' is the real Wikipedia title")
        let json = """
        {"thumbnail":{"source":"https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Banana.jpg/220px-Banana.jpg"}}
        """
        let fetcher = GenericFoodImages.Fetcher { _ in .success(Data(json.utf8)) }
        let product = FoodProduct(id: "builtin:banana", name: "Banana", source: .builtIn, per100g: .init(kcal: 89))

        let url = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertEqual(url?.absoluteString, "https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Banana.jpg/500px-Banana.jpg")
    }

    /// The USDA plural "Bananas" must resolve the same as the built-in
    /// singular "Banana" — both hit the network with whatever title
    /// `deriveTitle` derives, unaffected by a stale cached miss for the
    /// other spelling (they're different cache keys).
    func testUSDAPluralBananasAlsoResolves() async {
        let json = """
        {"thumbnail":{"source":"https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Banana.jpg/220px-Banana.jpg"}}
        """
        let fetcher = GenericFoodImages.Fetcher { _ in .success(Data(json.utf8)) }
        let product = FoodProduct(id: "usda:1234", name: "Bananas", source: .usda, per100g: .init(kcal: 89))

        let url = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertNotNil(url, "A USDA 'Bananas' result must still resolve a photo")
    }

    func testHitsAndMissesAreRememberedOnDisk() async {
        let callCount = CallCounter()
        let json = """
        {"thumbnail":{"source":"https://upload.wikimedia.org/x/220px-Foo.jpg"}}
        """
        let fetcher = GenericFoodImages.Fetcher { _ in
            callCount.increment()
            return .success(Data(json.utf8))
        }
        let product = FoodProduct(id: "builtin:banana", name: "Banana", source: .builtIn, per100g: .init(kcal: 89))

        _ = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        _ = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertEqual(callCount.count, 1, "Second lookup should hit the disk cache, not the network")
    }

    func testADefinitiveMissIsRememberedOnDisk() async {
        let callCount = CallCounter()
        let fetcher = GenericFoodImages.Fetcher { _ in
            callCount.increment()
            return .definitiveMiss
        }
        let product = FoodProduct(id: "builtin:mystery food", name: "Mystery food", source: .builtIn, per100g: .init(kcal: 10))

        let first = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        let second = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(callCount.count, 1, "A confirmed miss must not be re-queried")
    }

    /// Swift's synthesized `Decodable` does NOT fall back to a stored
    /// property's default value for a merely-absent key — it throws. A cache
    /// file written before `isDefinitive` existed has no such key at all;
    /// decoding it must not throw (which would silently wipe the whole
    /// cache on first launch after the update) and the entry must be
    /// trusted as already-settled, not re-queried.
    func testEntryFromBeforeIsDefinitiveExistedIsTrustedNotRetried() async throws {
        let title = GenericFoodImages.deriveTitle(from: "Mystery food")
        let json = """
        {"\(title)":{"urlString":null,"checkedAt":\(Date().timeIntervalSinceReferenceDate)}}
        """
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: tempDir.appendingPathComponent("wikipedia-titles-v2.json"))

        let callCount = CallCounter()
        let fetcher = GenericFoodImages.Fetcher { _ in
            callCount.increment()
            return .definitiveMiss
        }
        let product = FoodProduct(id: "builtin:mystery food", name: "Mystery food", source: .builtIn, per100g: .init(kcal: 10))

        let url = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir)
        XCTAssertNil(url)
        XCTAssertEqual(
            callCount.count,
            0,
            "An old-format entry must decode successfully and be trusted, not silently dropped and re-queried"
        )
    }

    /// The bug behind "Banana never gets its photo": a transient failure
    /// (429 / timeout / a 200 Wikipedia couldn't be decoded) must NOT be
    /// memoized as a permanent miss — once the retry window has passed, the
    /// next lookup tries again. `retryAfter: 0` stands in for "later" so the
    /// test doesn't need to sleep for real minutes.
    func testATransientFailureIsNotMemoizedAsAPermanentMiss() async {
        let callCount = CallCounter()
        let fetcher = GenericFoodImages.Fetcher { _ in
            callCount.increment()
            return .transientFailure
        }
        let product = FoodProduct(id: "builtin:banana", name: "Banana", source: .builtIn, per100g: .init(kcal: 89))

        let first = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 0)
        let second = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 0)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(callCount.count, 2, "A transient failure (429/timeout) must be retried, not trusted as a permanent miss")
    }

    /// Within the retry window, a transient miss is trusted rather than
    /// re-queried on every render — protects Wikipedia from being hammered.
    func testATransientFailureIsNotRetriedBeforeTheWindowElapses() async {
        let callCount = CallCounter()
        let fetcher = GenericFoodImages.Fetcher { _ in
            callCount.increment()
            return .transientFailure
        }
        let product = FoodProduct(id: "builtin:banana", name: "Banana", source: .builtIn, per100g: .init(kcal: 89))

        _ = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 3600)
        _ = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 3600)
        XCTAssertEqual(callCount.count, 1, "Still within the retry window — must not hit the network again yet")
    }

    /// Once a transient failure finally succeeds, the good result replaces
    /// the transient placeholder and is trusted from then on.
    func testATransientFailureThenSuccessSticks() async {
        let callCount = CallCounter()
        let json = """
        {"thumbnail":{"source":"https://upload.wikimedia.org/x/220px-Banana.jpg"}}
        """
        let fetcher = GenericFoodImages.Fetcher { _ in
            let call = callCount.increment()
            return call == 1 ? .transientFailure : .success(Data(json.utf8))
        }
        let product = FoodProduct(id: "builtin:banana", name: "Banana", source: .builtIn, per100g: .init(kcal: 89))

        let first = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 0)
        let second = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 0)
        XCTAssertNil(first)
        XCTAssertEqual(second?.absoluteString, "https://upload.wikimedia.org/x/500px-Banana.jpg")
        XCTAssertEqual(callCount.count, 2)
    }

    /// A 200 whose body doesn't decode as the expected Wikipedia summary
    /// shape is treated as transient, not "confirmed no photo".
    func testAnUndecodableSuccessBodyIsTreatedAsTransient() async {
        let callCount = CallCounter()
        let fetcher = GenericFoodImages.Fetcher { _ in
            callCount.increment()
            return .success(Data("not json".utf8))
        }
        let product = FoodProduct(id: "builtin:banana", name: "Banana", source: .builtIn, per100g: .init(kcal: 89))

        _ = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 0)
        _ = await GenericFoodImages.imageURL(for: product, fetcher: fetcher, cacheDirectory: tempDir, retryAfter: 0)
        XCTAssertEqual(callCount.count, 2, "An undecodable 200 body must be retried, not memoized as a miss")
    }
}

// MARK: - FoodImageCacheTests

final class FoodImageCacheTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FoodImageCacheTests-\(UUID())", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testFetchesOnceThenServesFromMemory() async throws {
        let callCount = CallCounter()
        let loader = FoodImageCache.Loader { _ in
            callCount.increment()
            return Data([1, 2, 3])
        }
        let cache = FoodImageCache(directory: tempDir, loader: loader)
        let url = try XCTUnwrap(URL(string: "https://example.com/a.jpg"))

        let first = await cache.data(for: url)
        let second = await cache.data(for: url)
        XCTAssertEqual(first, Data([1, 2, 3]))
        XCTAssertEqual(second, Data([1, 2, 3]))
        XCTAssertEqual(callCount.count, 1)
    }

    func testDiskSurvivesACacheInstanceRestart() async throws {
        let loader = FoodImageCache.Loader { _ in Data([9, 9, 9]) }
        let url = try XCTUnwrap(URL(string: "https://example.com/b.jpg"))
        _ = await FoodImageCache(directory: tempDir, loader: loader).data(for: url)

        // A fresh instance (simulating a relaunch) with a loader that must
        // never be called — the file on disk should answer instead.
        let neverCalled = FoodImageCache.Loader { _ in
            XCTFail("Should have served from disk")
            return nil
        }
        let restarted = FoodImageCache(directory: tempDir, loader: neverCalled)
        let result = await restarted.data(for: url)
        XCTAssertEqual(result, Data([9, 9, 9]))
    }

    func testFailedFetchReturnsNilAndIsNotCached() async throws {
        let callCount = CallCounter()
        let loader = FoodImageCache.Loader { _ in
            callCount.increment()
            return nil
        }
        let cache = FoodImageCache(directory: tempDir, loader: loader)
        let url = try XCTUnwrap(URL(string: "https://example.com/missing.jpg"))

        let first = await cache.data(for: url)
        let second = await cache.data(for: url)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(callCount.count, 2, "A failure isn't remembered — the next attempt tries again")
    }

    func testDifferentURLsGetDifferentCacheKeys() throws {
        let a = try FoodImageCache.cacheKey(for: XCTUnwrap(URL(string: "https://example.com/a.jpg")))
        let b = try FoodImageCache.cacheKey(for: XCTUnwrap(URL(string: "https://example.com/b.jpg")))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 64, "SHA-256 hex digest")
    }

    func testTrimsOldestFilesWhenOverBudget() async throws {
        let loader = FoodImageCache.Loader { _ in Data(repeating: 0, count: 1024) }
        let cache = FoodImageCache(directory: tempDir, loader: loader, maxDiskBytes: 2048)

        for index in 0 ..< 5 {
            _ = try await cache.data(for: XCTUnwrap(URL(string: "https://example.com/\(index).jpg")))
        }
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let totalBytes = try files.reduce(0) { try $0 + (Data(contentsOf: $1).count) }
        XCTAssertLessThanOrEqual(totalBytes, 2048, "Old entries should have been trimmed to stay under budget")
    }
}
