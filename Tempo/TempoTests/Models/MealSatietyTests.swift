//
// MealSatietyTests.swift
// Tempo
//
// The satiety signal on MealFeedback — captured at mark-eaten, read back by the
// plan digest to scale portions (mainly DOWN). Locks the model contract: the
// enum round-trips, satiety counts as a feedback signal, and the scale-change
// flag is right.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class MealSatietyTests: XCTestCase {

    func testSatietyRoundTripsThroughRawValue() {
        let fb = MealFeedback(plannedMeal: nil, satiety: .tooMuch)
        XCTAssertEqual(fb.satiety, .tooMuch)
        XCTAssertEqual(fb.satietyRaw, "too_much")

        fb.satiety = .stillHungry
        XCTAssertEqual(fb.satietyRaw, "still_hungry")

        fb.satiety = nil
        XCTAssertNil(fb.satietyRaw)
    }

    func testSatietyCountsAsHasSignal() {
        // A satiety-only row must register as actionable feedback (else the
        // digest would skip it and the scale-down loop never fires).
        let fb = MealFeedback(plannedMeal: nil, satiety: .didntFinish)
        XCTAssertTrue(fb.hasSignal)
    }

    func testNoSatietyNoSignal() {
        let fb = MealFeedback(plannedMeal: nil)
        XCTAssertFalse(fb.hasSignal)
    }

    func testRequestsPortionChange() {
        // Everything except just-right asks the planner to change the portion.
        XCTAssertTrue(MealSatiety.tooMuch.requestsPortionChange)
        XCTAssertTrue(MealSatiety.didntFinish.requestsPortionChange)
        XCTAssertTrue(MealSatiety.stillHungry.requestsPortionChange)
        XCTAssertFalse(MealSatiety.justRight.requestsPortionChange)
    }

    func testPersistsInContainer() throws {
        let container = try ModelContainer(
            for: MealFeedback.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        ctx.insert(MealFeedback(plannedMeal: nil, satiety: .tooMuch))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<MealFeedback>())
        XCTAssertEqual(fetched.first?.satiety, .tooMuch)
    }
}
