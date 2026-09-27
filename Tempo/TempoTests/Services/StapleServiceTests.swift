//
// StapleServiceTests.swift
// Tempo
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class StapleServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: LocalStapleService!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PantryStaple.self, configurations: config)
        service = LocalStapleService(modelContext: container.mainContext)
    }

    override func tearDown() async throws {
        service = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Status cycling

    func testStapleStatus_next_cyclesHaveToLowToOutToHave() {
        XCTAssertEqual(StapleStatus.have.next, .runningLow)
        XCTAssertEqual(StapleStatus.runningLow.next, .out)
        XCTAssertEqual(StapleStatus.out.next, .have)
    }

    func testStapleStatus_needsRestock() {
        XCTAssertFalse(StapleStatus.have.needsRestock)
        XCTAssertTrue(StapleStatus.runningLow.needsRestock)
        XCTAssertTrue(StapleStatus.out.needsRestock)
    }

    func testCycleStatus_advancesAndPersists() throws {
        let staple = try service.addStaple(canonicalName: "salt", displayName: "Salt", status: .have)

        let next = try service.cycleStatus(staple)

        XCTAssertEqual(next, .runningLow)
        XCTAssertEqual(staple.status, .runningLow)
        let refetched = try service.fetchAll().first { $0.canonicalName == "salt" }
        XCTAssertEqual(refetched?.status, .runningLow)
    }

    // MARK: - addStaple dedup

    func testAddStaple_secondCallWithSameCanonicalName_updatesInPlaceInsteadOfDuplicating() throws {
        _ = try service.addStaple(canonicalName: "olive oil", displayName: "Olive oil", status: .have)
        _ = try service.addStaple(canonicalName: "olive oil", displayName: "Olive oil", status: .out)

        let all = try service.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .out)
    }

    // MARK: - stapleNeeds

    func testStapleNeeds_returnsOnlyLowOrOut() throws {
        _ = try service.addStaple(canonicalName: "salt", displayName: "Salt", status: .have)
        _ = try service.addStaple(canonicalName: "olive oil", displayName: "Olive oil", status: .runningLow)
        _ = try service.addStaple(canonicalName: "soy sauce", displayName: "Soy sauce", status: .out)

        let needs = try service.stapleNeeds()

        XCTAssertEqual(needs.count, 2)
        XCTAssertTrue(needs.contains { $0.canonicalName == "olive oil" })
        XCTAssertTrue(needs.contains { $0.canonicalName == "soy sauce" })
        XCTAssertFalse(needs.contains { $0.canonicalName == "salt" })
    }

    func testStapleNeeds_emptyWhenAllHave() throws {
        _ = try service.addStaple(canonicalName: "salt", displayName: "Salt", status: .have)
        XCTAssertTrue(try service.stapleNeeds().isEmpty)
    }

    // MARK: - Onboarding

    func testShouldOfferOnboarding_trueWhenEmpty() throws {
        XCTAssertTrue(try service.shouldOfferOnboarding())
    }

    func testShouldOfferOnboarding_falseOnceStaplesExist() throws {
        _ = try service.addStaple(canonicalName: "salt", displayName: "Salt", status: .have)
        XCTAssertFalse(try service.shouldOfferOnboarding())
    }

    func testAddStaples_seedsMultipleFromSuggestions() throws {
        try service.addStaples([("salt", "Salt"), ("olive oil", "Olive oil")])
        XCTAssertEqual(try service.fetchAll().count, 2)
    }

    // MARK: - Delete

    func testDelete_removesStaple() throws {
        let staple = try service.addStaple(canonicalName: "salt", displayName: "Salt", status: .have)
        try service.delete(staple)
        XCTAssertTrue(try service.fetchAll().isEmpty)
    }
}
