//
// ShelfLifeAIEstimatorTests.swift
// Tempo
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - FakeShelfLifeAIEstimator

/// Never touches the network — records every call it received so tests can
/// assert on cache-hit behavior (no second call for an already-cached food).
private final class FakeShelfLifeAIEstimator: ShelfLifeAIEstimating, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastRequests: [ShelfLifeAIRequest] = []
    var stubbedDays: [String: Int]

    init(stubbedDays: [String: Int] = [:]) {
        self.stubbedDays = stubbedDays
    }

    func estimateDays(_ requests: [ShelfLifeAIRequest]) async throws -> [String: Int] {
        callCount += 1
        lastRequests = requests
        var result: [String: Int] = [:]
        for request in requests {
            if let days = stubbedDays[request.key] {
                result[request.key] = days
            }
        }
        return result
    }
}

// MARK: - ShelfLifeAIEstimatorTests

final class ShelfLifeAIEstimatorTests: XCTestCase {
    override func tearDown() async throws {
        await ShelfLifeAICache.shared.reset()
        try await super.tearDown()
    }

    // MARK: - ShelfLifeAICache

    func testCache_getReturnsNilWhenUnset() async {
        await ShelfLifeAICache.shared.reset()
        let value = await ShelfLifeAICache.shared.get("dragonfruit|fridge")
        XCTAssertNil(value)
    }

    func testCache_setThenGetRoundTrips() async {
        await ShelfLifeAICache.shared.reset()
        await ShelfLifeAICache.shared.set("dragonfruit|fridge", 9)
        let value = await ShelfLifeAICache.shared.get("dragonfruit|fridge")
        XCTAssertEqual(value, 9)
    }

    func testCache_resetClearsAllEntries() async {
        await ShelfLifeAICache.shared.set("dragonfruit|fridge", 9)
        await ShelfLifeAICache.shared.reset()
        let value = await ShelfLifeAICache.shared.get("dragonfruit|fridge")
        XCTAssertNil(value)
    }

    // MARK: - ShelfLifeAIRequest.key

    func testRequestKey_combinesNameAndLocation() {
        let request = ShelfLifeAIRequest(canonicalName: "dragonfruit", storageLocation: .fridge)
        XCTAssertEqual(request.key, "dragonfruit|fridge")
    }

    // MARK: - LocalPantryService.refineUseByWithAI integration (no network)

    @MainActor
    func testRefineUseByWithAI_appliesEstimatorResultToMatchingItem() async throws {
        await ShelfLifeAICache.shared.reset()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PantryItem.self, configurations: config)
        let context = container.mainContext
        let service = LocalPantryService(modelContext: context)

        let item = PantryItem(
            canonicalName: "dragonfruit smoothie mix", displayName: "Dragonfruit Smoothie Mix",
            quantity: 1, unit: .pieces, storageLocation: .fridge, useBy: nil
        )
        context.insert(item)
        try context.save()

        let fake = FakeShelfLifeAIEstimator(stubbedDays: ["dragonfruit smoothie mix|fridge": 5])
        await service.refineUseByWithAI(
            itemID: item.id, canonicalName: "dragonfruit smoothie mix",
            storageLocation: .fridge, aiEstimator: fake
        )

        XCTAssertEqual(fake.callCount, 1)
        let useBy = try XCTUnwrap(item.useBy)
        let expected = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: Calendar.current.startOfDay(for: Date())))
        // Allow a day of slack since "today" may differ by a few seconds between setup and assertion.
        XCTAssertEqual(useBy.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 86400)
    }

    @MainActor
    func testRefineUseByWithAI_usesCacheOnSecondCall_neverCallsEstimatorAgain() async throws {
        await ShelfLifeAICache.shared.reset()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PantryItem.self, configurations: config)
        let context = container.mainContext
        let service = LocalPantryService(modelContext: context)

        let itemA = PantryItem(
            canonicalName: "dragonfruit smoothie mix", displayName: "A",
            quantity: 1, unit: .pieces, storageLocation: .fridge, useBy: nil
        )
        let itemB = PantryItem(
            canonicalName: "dragonfruit smoothie mix", displayName: "B",
            quantity: 1, unit: .pieces, storageLocation: .fridge, useBy: nil
        )
        context.insert(itemA)
        context.insert(itemB)
        try context.save()

        let fake = FakeShelfLifeAIEstimator(stubbedDays: ["dragonfruit smoothie mix|fridge": 5])
        await service.refineUseByWithAI(
            itemID: itemA.id, canonicalName: "dragonfruit smoothie mix",
            storageLocation: .fridge, aiEstimator: fake
        )
        await service.refineUseByWithAI(
            itemID: itemB.id, canonicalName: "dragonfruit smoothie mix",
            storageLocation: .fridge, aiEstimator: fake
        )

        XCTAssertEqual(fake.callCount, 1, "Second lookup for the same food+location should hit the cache")
        XCTAssertNotNil(itemB.useBy, "Cached value still applies to the second item")
    }

    @MainActor
    func testRefineUseByWithAI_estimatorReturnsNothing_leavesUseByUnset() async throws {
        await ShelfLifeAICache.shared.reset()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PantryItem.self, configurations: config)
        let context = container.mainContext
        let service = LocalPantryService(modelContext: context)

        let item = PantryItem(
            canonicalName: "mystery food", displayName: "Mystery Food",
            quantity: 1, unit: .pieces, storageLocation: .fridge, useBy: nil
        )
        context.insert(item)
        try context.save()

        let fake = FakeShelfLifeAIEstimator(stubbedDays: [:])
        await service.refineUseByWithAI(
            itemID: item.id, canonicalName: "mystery food",
            storageLocation: .fridge, aiEstimator: fake
        )

        XCTAssertNil(item.useBy)
    }
}
