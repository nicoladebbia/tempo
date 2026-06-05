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

    // MARK: - WeeklyMealPlan.supplementDecisions round-trip

    func testPlanSupplementDecisions_roundTrip() throws {
        let container = try ModelContainer(
            for: WeeklyMealPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let plan = WeeklyMealPlan(
            startDate: Date(), endDate: Date(),
            dayTypeAssignments: [:], isActive: true
        )
        // Key 1 = Monday (the plan's dayIndex+1 convention).
        plan.supplementDecisions = [
            1: [
                SupplementDecision(name: "Creatine", take: true, timing: "with breakfast", reason: "creatine daily"),
                SupplementDecision(name: "Whey", take: false, timing: nil, reason: "protein met by food"),
            ],
        ]
        ctx.insert(plan)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WeeklyMealPlan>())
        let decisions = fetched.first?.supplementDecisions[1] ?? []
        XCTAssertEqual(decisions.count, 2)
        XCTAssertEqual(decisions.first?.name, "Creatine")
        XCTAssertEqual(decisions.first?.take, true)
        XCTAssertEqual(decisions.first?.timing, "with breakfast",
                       "Timing (when to take it) must persist")
        XCTAssertEqual(decisions.last?.take, false)
    }

    func testShelfBlock_requestsTiming() {
        let block = MealPlanPrompts.supplementShelfBlock([
            Supplement(name: "Creatine", kind: .creatine),
        ])
        // The AI must be told to say WHEN to take each one — the user shouldn't
        // have to decide timing.
        XCTAssertTrue(block.uppercased().contains("TIMING"))
        XCTAssertTrue(block.lowercased().contains("when"))
    }

    func testPlanSupplementDecisions_emptyWhenAbsent() throws {
        let container = try ModelContainer(
            for: WeeklyMealPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let plan = WeeklyMealPlan(
            startDate: Date(), endDate: Date(),
            dayTypeAssignments: [:], isActive: true
        )
        // Never set → decoding a nil blob yields an empty map, not a crash.
        XCTAssertTrue(plan.supplementDecisions.isEmpty)
    }

    // MARK: - SupplementIntakeLog ("I took it" persistence)
    //
    // The insert/fetch/delete + date-isolation contract is exercised end-to-end
    // by the toggle tests in NutritionTabViewModelTests
    // (testToggleSupplementTaken_*), which use the shared multi-model setUp
    // container — the SAME path the app uses. A per-test single-purpose
    // container for this model traps in SwiftData's Date persistence
    // (SupplementIntakeLog.takenAt getter) — a test-container quirk, not a
    // product bug, so we don't duplicate the round-trip here. Only the pure
    // start-of-day normalization (no container) is asserted below.

    func testIntakeLog_normalizesToStartOfDay() throws {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: Date())!
        let log = SupplementIntakeLog(supplementName: "Creatine", day: noon)
        XCTAssertEqual(log.day, Calendar.current.startOfDay(for: noon),
                       "day must be start-of-day so any time today matches")
    }
}
