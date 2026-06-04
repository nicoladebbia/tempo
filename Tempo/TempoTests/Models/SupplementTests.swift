//
// SupplementTests.swift
// Tempo
//
// The Supplement model + its prompt-shelf rendering. The shelf is what the
// meal-plan AI reads to make a daily take/skip decision, so the contract that
// matters: creatine defaults to daily, protein carries its per-serving grams,
// running-low is flagged, and the block NEVER opens a "go buy more" path.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class SupplementTests: XCTestCase {

    // MARK: - Model

    func testCreatineDefaultsToDaily() {
        let creatine = Supplement(name: "Creatine Monohydrate", kind: .creatine)
        XCTAssertTrue(creatine.takeDaily, "Creatine is daily-by-default")
    }

    func testProteinIsConditionalByDefault() {
        let whey = Supplement(name: "Whey Isolate", kind: .protein)
        XCTAssertFalse(whey.takeDaily, "Protein is conditional (fills a gap), not daily")
    }

    func testTakeDailyOverrideRespected() {
        let omega = Supplement(name: "Fish Oil", kind: .omega3, takeDaily: true)
        XCTAssertTrue(omega.takeDaily, "Explicit override beats the kind default")
    }

    func testRunningLowThreshold() {
        let low = Supplement(name: "Whey", kind: .protein, servingsRemaining: 4)
        let fine = Supplement(name: "Whey", kind: .protein, servingsRemaining: 20)
        let unknown = Supplement(name: "Whey", kind: .protein, servingsRemaining: 0)
        XCTAssertTrue(low.isRunningLow)
        XCTAssertFalse(fine.isRunningLow)
        XCTAssertFalse(unknown.isRunningLow, "0 = unknown/empty, not 'low'")
    }

    func testInMemoryRoundTrip() throws {
        let container = try ModelContainer(
            for: Supplement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        ctx.insert(Supplement(name: "Creatine", kind: .creatine, dosePerServing: "5 g", servingsRemaining: 60))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Supplement>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Creatine")
        XCTAssertEqual(fetched.first?.kind, .creatine)
    }

    // MARK: - Shelf prompt block

    func testShelfBlock_emptyWhenNoSupplements() {
        XCTAssertEqual(MealPlanPrompts.supplementShelfBlock([]), "")
    }

    func testShelfBlock_emptyWhenAllArchived() {
        let archived = Supplement(name: "Old Whey", kind: .protein, isArchived: true)
        XCTAssertEqual(MealPlanPrompts.supplementShelfBlock([archived]), "")
    }

    func testShelfBlock_listsItemsAndProteinGrams() {
        let block = MealPlanPrompts.supplementShelfBlock([
            Supplement(name: "Whey Isolate", kind: .protein,
                       dosePerServing: "30 g", proteinGramsPerServing: 25, servingsRemaining: 40),
            Supplement(name: "Creatine", kind: .creatine, dosePerServing: "5 g"),
        ])
        XCTAssertTrue(block.contains("<supplement_shelf>"))
        XCTAssertTrue(block.contains("Whey Isolate"))
        XCTAssertTrue(block.contains("25g protein/serving"))
        XCTAssertTrue(block.contains("Creatine"))
        // Creatine reads as daily; whey reads as conditional.
        XCTAssertTrue(block.contains("daily by default"))
        XCTAssertTrue(block.contains("conditional"))
    }

    func testShelfBlock_flagsRunningLow() {
        let block = MealPlanPrompts.supplementShelfBlock([
            Supplement(name: "Whey", kind: .protein, servingsRemaining: 3),
        ])
        XCTAssertTrue(block.contains("RUNNING LOW"))
    }

    func testShelfBlock_forbidsBuyingAndOffShelf() {
        let block = MealPlanPrompts.supplementShelfBlock([
            Supplement(name: "Creatine", kind: .creatine),
        ])
        // The no-buying / shelf-only guardrail must be present.
        XCTAssertTrue(block.lowercased().contains("never suggest buying"))
        XCTAssertTrue(block.lowercased().contains("only from this list"))
    }

    func testShelfBlock_minimizesDairyWheyBias() {
        let block = MealPlanPrompts.supplementShelfBlock([
            Supplement(name: "Whey", kind: .protein, proteinGramsPerServing: 25),
        ])
        // Whey should be the top-up, not the default, because dairy is minimized.
        XCTAssertTrue(block.lowercased().contains("food first"))
    }
}
