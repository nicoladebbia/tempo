//
// TrainingSessionDisplayMathTests.swift
// Tempo
//
// §15 — a bodyweight lift must never log 0 kg, and a PR's displayed weight
// must always come from `pr.value` converted to the user's unit, never from
// TrainingEngine's kg-only, unit-unaware `context` string.
//

@testable import Tempo
import XCTest

final class TrainingSessionDisplayMathTests: XCTestCase {
    // MARK: - BodyweightLiftMath

    func testEffectiveLoadFallsBackToPromptWhenProfileWeightUnknown() {
        // Before the fix this case only ever had `profileBodyweightKg`
        // (0, unknown) + addedLoadKg (0) = 0 — a bodyweight lift logged at
        // 0 kg. The prompt fallback is what closes that gap.
        let effective = BodyweightLiftMath.effectiveLoadKg(
            profileBodyweightKg: 0,
            promptBodyweightKg: 70,
            addedLoadKg: 0
        )
        XCTAssertEqual(effective, 70, "Must fall back to the inline prompt, never silently log 0 kg")
    }

    func testEffectiveLoadPrefersKnownProfileWeightOverPrompt() {
        let effective = BodyweightLiftMath.effectiveLoadKg(
            profileBodyweightKg: 82,
            promptBodyweightKg: 999, // stale/irrelevant once the profile has a real value
            addedLoadKg: 5
        )
        XCTAssertEqual(effective, 87, "A known profile weight always wins over the prompt")
    }

    func testEffectiveLoadNeverGoesNegativeWithHeavyAssistance() {
        let effective = BodyweightLiftMath.effectiveLoadKg(
            profileBodyweightKg: 0,
            promptBodyweightKg: 40,
            addedLoadKg: -60
        )
        XCTAssertEqual(effective, 0)
    }

    // MARK: - PRDisplay

    func testWeightLabelConvertsFromKgToUsersUnitNeverFromContext() {
        let pr = PersonalRecord(type: .oneRepMax, value: 100, date: Date(), context: "999kg x 5 reps")
        // The context string is deliberately garbage/wrong here — the label
        // must ignore it entirely and derive everything from pr.value.
        let kgLabel = PRDisplay.weightLabel(pr, unit: .kg, decimals: 0)
        XCTAssertEqual(kgLabel, "100 kg")

        let lbsLabel = PRDisplay.weightLabel(pr, unit: .lbs, decimals: 0)
        XCTAssertEqual(lbsLabel, "220 lbs", "100 kg is ~220 lbs, not '999' anything")
    }

    func testSubtitleParsesRepsFromContextForRepMaxOnly() {
        let repMax = PersonalRecord(type: .repMax, value: 82.5, date: Date(), context: "82kg x 5 reps")
        XCTAssertEqual(PRDisplay.subtitle(repMax), "New 5-rep max")

        let oneRM = PersonalRecord(type: .oneRepMax, value: 105, date: Date(), context: "82kg x 5 reps")
        XCTAssertEqual(
            PRDisplay.subtitle(oneRM), "New estimated 1RM",
            "1RM is a derived number, not the literal set performed — must not echo the raw context reps/weight"
        )
    }

    func testSubtitleHandlesMissingOrUnparsableContext() {
        let repMax = PersonalRecord(type: .repMax, value: 82.5, date: Date(), context: nil)
        XCTAssertEqual(PRDisplay.subtitle(repMax), "New rep max")
    }
}
