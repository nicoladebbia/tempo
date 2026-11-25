//
// TrainExplainersTests.swift
// Tempo
//
// Every Train explainer answers all three questions in short plain words,
// has its own stable id, and quotes the same numbers the code uses.
//

@testable import Tempo
import XCTest

@MainActor
final class TrainExplainersTests: XCTestCase {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    func testEveryExplainerHasAUniqueTrainIdentifier() {
        let ids = TrainExplainers.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "two explainers share an id: \(ids)")
        for id in ids {
            XCTAssertTrue(id.hasPrefix("train."), "\(id) should be namespaced to Train")
        }
    }

    func testEveryExplainerAnswersAllThreeQuestionsBriefly() {
        for explainer in TrainExplainers.all {
            for (name, answer) in [("what", explainer.what), ("how", explainer.how), ("action", explainer.action)] {
                let words = text(answer)
                XCTAssertFalse(words.trimmingCharacters(in: .whitespaces).isEmpty, "\(explainer.id) has no \(name)")
                XCTAssertLessThanOrEqual(words.count, 300, "\(explainer.id) \(name) is too long to read in a sheet")
                XCTAssertTrue(words.hasSuffix("."), "\(explainer.id) \(name) should be a sentence")
            }
            XCTAssertFalse(text(explainer.title).isEmpty)
        }
    }

    func testTheFormulasQuoteTheConstantsTheCodeUses() {
        // The e1RM text says reps count up to 12 and reserve up to 4, and the
        // secondary-muscle text says half: these are the engine's own caps.
        XCTAssertEqual(StrengthStandards.e1RMRepCap, 12)
        XCTAssertEqual(StrengthStandards.e1RMRIRCap, 4)
        XCTAssertTrue(text(TrainExplainers.bestE1RM.how).contains("up to 12"))
        XCTAssertTrue(text(TrainExplainers.bestE1RM.how).contains("up to 4"))
        XCTAssertTrue(text(TrainExplainers.currentE1RM.how).contains("6 weeks"))
        XCTAssertEqual(MuscleHeatEngine.secondaryFactor, 0.5)
        XCTAssertTrue(text(TrainExplainers.heatVolume.how).contains("half"))
        XCTAssertTrue(text(TrainExplainers.trainingLoad.action).contains(String(format: "%.1f", TrainingSafetyFloor.acwrCompositeMax)))
    }

    func testTheEstimatedTimeTextMatchesTheRealEstimate() {
        // The figures are the ones `TodayWorkoutView.estimatedDuration` adds up.
        let how = text(TrainExplainers.estimatedTime.how)
        for part in ["5 minutes of warm-up", "2.5 minutes", "1.5", "3 of cooldown", "never under 20"] {
            XCTAssertTrue(how.contains(part), "missing \(part)")
        }
    }

    func testAnExplainerShowsTheValueItWasTappedOn() {
        let shown = TrainExplainers.rir.showing("2")
        XCTAssertEqual(shown.value, "2")
        XCTAssertEqual(shown.id, TrainExplainers.rir.id)
    }
}
