//
// SupplementTodayBoardTests.swift
// Tempo
//
// Today's supplement card data: grouping by time of day, order, taken state
// and counts, macros line, running-low flag, and the taken-time store read.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SupplementTodayBoardTests: XCTestCase {
    private func dose(
        _ name: String,
        kind: SupplementKind = .vitamin,
        minutes: Int,
        anchor: SupplementTimingAnchor?,
        take: Bool = true
    ) -> SupplementDose {
        SupplementDose(
            supplementID: UUID(), name: name, kind: kind, dosePerServing: "1",
            take: take, minutes: minutes, anchor: anchor, reason: "Daily"
        )
    }

    func testGroupsByTimeOfDayAndSortsByClock() {
        let creatine = dose("Creatine", minutes: 8 * 60, anchor: .breakfast)
        let omega = dose("Omega", minutes: 19 * 60 + 30, anchor: .dinner)
        let magnesium = dose("Magnesium", minutes: 22 * 60, anchor: .bedtime)
        let vitD = dose("D3", minutes: 7 * 60 + 30, anchor: .wake)
        let board = SupplementTodayBoard.build(doses: [magnesium, omega, creatine, vitD], takenAt: [:])
        XCTAssertEqual(board.sections.map(\.period), [.morning, .withMeals, .evening])
        XCTAssertEqual(board.sections[0].rows.map(\.dose.name), ["D3", "Creatine"])
        XCTAssertEqual(board.sections[1].rows.map(\.dose.name), ["Omega"])
        XCTAssertEqual(board.sections[2].rows.map(\.dose.name), ["Magnesium"])
    }

    func testTrainingAndPinnedDosesGoByTheClock() {
        XCTAssertEqual(SupplementPeriod.period(for: dose("a", minutes: 9 * 60, anchor: .preTraining)), .morning)
        XCTAssertEqual(SupplementPeriod.period(for: dose("b", minutes: 15 * 60, anchor: nil)), .withMeals)
        XCTAssertEqual(SupplementPeriod.period(for: dose("c", minutes: 18 * 60, anchor: .postTraining)), .evening)
    }

    func testEmptyPeriodsAreDroppedAndSkipsAreSeparate() {
        let take = dose("Creatine", minutes: 8 * 60, anchor: .breakfast)
        let skip = dose("Whey", minutes: 18 * 60, anchor: .postTraining, take: false)
        let board = SupplementTodayBoard.build(doses: [take, skip], takenAt: [:])
        XCTAssertEqual(board.sections.map(\.period), [.morning])
        XCTAssertEqual(board.total, 1)
        XCTAssertEqual(board.skipped.map(\.name), ["Whey"])
    }

    func testTakenCountAndTime() {
        let a = dose("A", minutes: 8 * 60, anchor: .breakfast)
        let b = dose("B", minutes: 9 * 60, anchor: .breakfast)
        let when = Date(timeIntervalSince1970: 1_000_000)
        var board = SupplementTodayBoard.build(doses: [a, b], takenAt: [a.supplementID: when])
        XCTAssertEqual(board.takenCount, 1)
        XCTAssertFalse(board.allTaken)
        XCTAssertEqual(board.sections[0].rows[0].takenAt, when)
        board = SupplementTodayBoard.build(doses: [a, b], takenAt: [a.supplementID: when, b.supplementID: when])
        XCTAssertTrue(board.allTaken)
    }

    func testMacrosLineAndLowFlag() {
        let whey = dose("Whey", kind: .protein, minutes: 18 * 60, anchor: .postTraining)
        let board = SupplementTodayBoard.build(
            doses: [whey],
            takenAt: [:],
            macros: [whey.supplementID: MealMacros(calories: 120, protein: 25, carbs: 2, fat: 1)],
            daysLeft: [whey.supplementID: 3]
        )
        XCTAssertEqual(board.sections[0].rows[0].macrosLine, "25 g protein · 120 kcal")
        XCTAssertEqual(board.lowRows.count, 1)
        let plain = SupplementTodayBoard.build(doses: [whey], takenAt: [:])
        XCTAssertNil(plain.sections[0].rows[0].macrosLine)
        XCTAssertTrue(plain.lowRows.isEmpty)
    }

    func testTakenTimesFollowTicks() throws {
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let creatine = Supplement(name: "Creatine", kind: .creatine, dosePerServing: "5 g", servingsRemaining: 30)
        context.insert(creatine)
        try context.save()
        XCTAssertTrue(SupplementIntakeStore.takenTimes(on: Date(), in: context).isEmpty)
        SupplementIntakeStore.toggle(supplementID: creatine.id, name: creatine.name, in: context)
        XCTAssertNotNil(SupplementIntakeStore.takenTimes(on: Date(), in: context)[creatine.id])
        SupplementIntakeStore.toggle(supplementID: creatine.id, name: creatine.name, in: context)
        XCTAssertTrue(SupplementIntakeStore.takenTimes(on: Date(), in: context).isEmpty)
    }
}
