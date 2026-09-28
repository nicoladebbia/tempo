//
// SupplementNearbyStoresTests.swift
// Tempo
//
// Pure-logic tests for `SupplementNearbyStores.sortedDeduped` — the only part
// of the Nearby section that doesn't require a live MKLocalSearch call.
// Covers nearest-first ordering, same-store deduping across chain queries,
// and the result-count cap.
//

@testable import Tempo
import XCTest

final class SupplementNearbyStoresTests: XCTestCase {
    private func store(_ name: String, distance: Double, lat: Double = 25.7617, lon: Double = -80.1918) -> NearbyStoreResult {
        NearbyStoreResult(id: "\(name)|\(lat)|\(lon)|\(distance)", name: name, latitude: lat, longitude: lon, distanceMeters: distance)
    }

    func testSortsByDistanceAscending() {
        let results = [
            store("Walgreens", distance: 2000),
            store("GNC", distance: 500),
            store("CVS Pharmacy", distance: 1200),
        ]
        let sorted = SupplementNearbyStores.sortedDeduped(results, limit: 10)
        XCTAssertEqual(sorted.map(\.name), ["GNC", "CVS Pharmacy", "Walgreens"])
    }

    func testDropsSameNameDuplicateWithin50Meters() {
        // Same physical Whole Foods matched by two different chain queries
        // (e.g. "Whole Foods Market" and a generic "vitamins" query) —
        // near-identical coordinates, same name.
        let results = [
            store("Whole Foods Market", distance: 800, lat: 25.7617, lon: -80.1918),
            store("Whole Foods Market", distance: 810, lat: 25.76175, lon: -80.19185),
        ]
        let deduped = SupplementNearbyStores.sortedDeduped(results, limit: 10)
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.distanceMeters, 800)
    }

    func testKeepsSameNameStoresFartherThan50MetersApart() {
        // Two genuinely different CVS locations should both survive.
        let results = [
            store("CVS Pharmacy", distance: 500, lat: 25.7617, lon: -80.1918),
            store("CVS Pharmacy", distance: 1500, lat: 25.7800, lon: -80.2100),
        ]
        let deduped = SupplementNearbyStores.sortedDeduped(results, limit: 10)
        XCTAssertEqual(deduped.count, 2)
    }

    func testDedupeIsCaseInsensitive() {
        let results = [
            store("GNC", distance: 300),
            store("gnc", distance: 320),
        ]
        let deduped = SupplementNearbyStores.sortedDeduped(results, limit: 10)
        XCTAssertEqual(deduped.count, 1)
    }

    func testRespectsLimit() {
        let results = (0 ..< 20).map { store("Store \($0)", distance: Double($0) * 100) }
        let limited = SupplementNearbyStores.sortedDeduped(results, limit: 5)
        XCTAssertEqual(limited.count, 5)
        XCTAssertEqual(limited.first?.name, "Store 0")
    }

    func testEmptyInputReturnsEmptyOutput() {
        XCTAssertTrue(SupplementNearbyStores.sortedDeduped([], limit: 10).isEmpty)
    }
}
