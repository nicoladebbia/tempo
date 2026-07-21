//
// TrainingSplitOnboardingTests.swift
// Tempo
//
// Pins the requirement-(a) onboarding-split rescue: the split the user picks at
// signup was captured then discarded (every new user silently got PPL). These
// cover the two pure mappers ContentView now seeds UserSettings.trainingSplit
// from — an explicit chip label, and the days/week fallback for "I Don't Know".
//

@testable import Tempo
import XCTest

final class TrainingSplitOnboardingTests: XCTestCase {

    func testExplicitChipLabelsMapToCanonicalSplits() {
        XCTAssertEqual(TrainingSplit.fromOnboardingLabel("PPL"), .pushPullLegs)
        XCTAssertEqual(TrainingSplit.fromOnboardingLabel("Upper/Lower"), .upperLower)
        XCTAssertEqual(TrainingSplit.fromOnboardingLabel("Full Body"), .fullBody)
        XCTAssertEqual(TrainingSplit.fromOnboardingLabel("Bro Split"), .bro)
    }

    func testIDontKnowAndUnknownReturnNilSoCallerCanFallBack() {
        XCTAssertNil(TrainingSplit.fromOnboardingLabel("I Don't Know"),
                     "\"I Don't Know\" must be nil so the caller falls back to days/week")
        XCTAssertNil(TrainingSplit.fromOnboardingLabel(""),
                     "Empty (no pick persisted) is nil, not a forced guess")
        XCTAssertNil(TrainingSplit.fromOnboardingLabel("nonsense"))
    }

    func testDaysPerWeekInfersSensibleSplit() {
        XCTAssertEqual(TrainingSplit.forDaysPerWeek(2), .fullBody, "≤3 days → full body")
        XCTAssertEqual(TrainingSplit.forDaysPerWeek(3), .fullBody)
        XCTAssertEqual(TrainingSplit.forDaysPerWeek(4), .upperLower, "4 days → upper/lower")
        XCTAssertEqual(TrainingSplit.forDaysPerWeek(5), .bro, "5 days → bro split")
        XCTAssertEqual(TrainingSplit.forDaysPerWeek(6), .pushPullLegs, "6+ days → PPL")
        XCTAssertEqual(TrainingSplit.forDaysPerWeek(7), .pushPullLegs)
    }

    func testChipLabelsMatchTheOnboardingSource() {
        // Guards against the picker labels drifting from the mapper. These four are
        // the mappable entries of TrainingSetupView.splits; if that list changes,
        // this test should be updated in lockstep.
        for label in ["PPL", "Upper/Lower", "Full Body", "Bro Split"] {
            XCTAssertNotNil(TrainingSplit.fromOnboardingLabel(label),
                            "Onboarding chip \"\(label)\" must map to a split")
        }
    }
}
