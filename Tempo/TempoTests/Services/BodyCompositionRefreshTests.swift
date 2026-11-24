//
// BodyCompositionRefreshTests.swift
// Tempo
//
// Opening Body progress keeps Health's newest reading as today's snapshot,
// one row per day, and never blanks a stored day with an empty read.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class BodyCompositionRefreshTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func data(kg: Double? = nil, fat: Double? = nil, lean: Double? = nil) -> BodyCompositionData {
        BodyCompositionData(weightKg: kg, bodyFatPercent: fat, leanMassKg: lean, heightCm: nil, measurementDate: Date())
    }

    private func rows() throws -> [BodyComposition] {
        try context.fetch(FetchDescriptor<BodyComposition>())
    }

    func testTodaysReadingIsStored() throws {
        XCTAssertTrue(BodyCompositionRefresh.store(data(kg: 80.2, fat: 18.1, lean: 65.7), in: context))
        let row = try XCTUnwrap(rows().first)
        XCTAssertEqual(row.weightKg, 80.2)
        XCTAssertEqual(row.bodyFatPercent, 18.1)
        XCTAssertEqual(row.leanMassKg, 65.7)
        XCTAssertEqual(row.date, Calendar.current.startOfDay(for: Date()))
    }

    func testASecondReadingTheSameDayUpdatesTheRow() throws {
        BodyCompositionRefresh.store(data(kg: 80.2), in: context)
        BodyCompositionRefresh.store(data(kg: 79.8, fat: 18.0), in: context)
        let all = try rows()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.weightKg, 79.8)
        XCTAssertEqual(all.first?.bodyFatPercent, 18.0)
    }

    func testAnEmptyReadWritesNothingAndKeepsTheStoredDay() throws {
        BodyCompositionRefresh.store(data(kg: 80.2), in: context)
        XCTAssertFalse(BodyCompositionRefresh.store(data(), in: context))
        XCTAssertEqual(try rows().first?.weightKg, 80.2)
    }

    func testAnotherDayGetsItsOwnRow() throws {
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        BodyCompositionRefresh.store(data(kg: 80.5), on: yesterday, in: context)
        BodyCompositionRefresh.store(data(kg: 80.2), in: context)
        XCTAssertEqual(try rows().count, 2)
    }

    func testRefreshReadsTheHealthService() async throws {
        await BodyCompositionRefresh.refresh(from: MockHealthKitService(), in: context)
        let row = try XCTUnwrap(rows().first)
        XCTAssertEqual(row.weightKg, 75.2)
        XCTAssertEqual(row.bodyFatPercent, 14.5)
        XCTAssertEqual(row.leanMassKg, 64.3)
    }
}
