//
// TodayExplainersTests.swift
// TempoTests
//
// The "tap a number" texts for Today: every one is complete, short and unique,
// and the few facts the words state about the app (the score bands, the
// weights, the goal tolerance) are the same as the code they describe, so a
// change to one cannot silently leave the other behind.
//

@testable import Tempo
import XCTest

@MainActor
final class TodayExplainersTests: XCTestCase {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    private var everyExplainer: [Explainer] {
        var all: [Explainer] = [
            Explainer.dayScore(weakest: nil), Explainer.recoveryPart, Explainer.foodPart(kcalLeft: 400),
            Explainer.studyPart(minutesLeft: 30), Explainer.movementPart(stepsTarget: 8000, stepsLeft: 2000, sessionDone: false),
            Explainer.streak(tasksLeft: 2), Explainer.weekSessions, Explainer.weekCalories, Explainer.weekRecovery,
            Explainer.weekTasks, Explainer.goalPace(.behind), Explainer.dayOrder, Explainer.tomorrowWake,
        ]
        all += GoalKind.allCases.map { Explainer.goalReading($0) }
        return all
    }

    // MARK: Shape

    func testEveryExplainerHasThreeShortAnswers() {
        for explainer in everyExplainer {
            for (name, resource) in [("what", explainer.what), ("how", explainer.how), ("action", explainer.action)] {
                let words = text(resource)
                XCTAssertFalse(words.isEmpty, "\(explainer.id) \(name)")
                // One or two sentences each.
                let sentences = words.split(separator: ".", omittingEmptySubsequences: true).count
                XCTAssertLessThanOrEqual(sentences, 2, "\(explainer.id) \(name): \(words)")
            }
        }
    }

    func testEveryExplainerIdIsUniqueAcrossTheVariants() {
        let ids = everyExplainer.map(\.id).filter { $0 != "goal-reading" }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: Day score

    func testTheScoreBandsInTheWordsAreTheMoodBands() {
        let words = text(Explainer.dayScore(weakest: nil).what)
        XCTAssertTrue(words.contains("67 and up reads On pace"))
        XCTAssertTrue(words.contains("34 to 66 Behind"))
        XCTAssertTrue(words.contains("under 34 Off track"))
        XCTAssertEqual(TideMood(score: 67).level, .onPace)
        XCTAssertEqual(TideMood(score: 66).level, .behind)
        XCTAssertEqual(TideMood(score: 34).level, .behind)
        XCTAssertEqual(TideMood(score: 33).level, .offTrack)
        XCTAssertEqual(TideMood(level: .onPace).word, "On pace")
        XCTAssertEqual(TideMood(level: .behind).word, "Behind")
        XCTAssertEqual(TideMood(level: .offTrack).word, "Off track")
    }

    func testTheLowestPartIsTheOneTheActionPointsAt() {
        let breakdown = DashboardViewModel.ScoreBreakdown(
            recoveryPoints: 20, nutritionPoints: 6, studyPoints: 25, movementPoints: 12,
            recoveryAvailable: true, nutritionAvailable: true, studyAvailable: true, movementAvailable: true
        )
        XCTAssertEqual(Explainer.weakestPart(in: breakdown), .food)
        XCTAssertTrue(text(Explainer.dayScore(weakest: .food).action).hasPrefix("Food is your lowest part"))
    }

    func testAPartWithNoDataIsNeverTheLowest() {
        let breakdown = DashboardViewModel.ScoreBreakdown(
            recoveryPoints: 0, nutritionPoints: 0, studyPoints: 25, movementPoints: 12,
            recoveryAvailable: false, nutritionAvailable: false, studyAvailable: true, movementAvailable: true
        )
        XCTAssertEqual(Explainer.weakestPart(in: breakdown), .movement)
    }

    func testAFullScoreHasNoLowestPart() {
        let breakdown = DashboardViewModel.ScoreBreakdown(
            recoveryPoints: 25, nutritionPoints: 25, studyPoints: 25, movementPoints: 25,
            recoveryAvailable: true, nutritionAvailable: true, studyAvailable: true, movementAvailable: true
        )
        XCTAssertNil(Explainer.weakestPart(in: breakdown))
    }

    // MARK: Parts

    func testTheNutritionActionNamesWhatIsLeftToEat() {
        XCTAssertTrue(text(Explainer.foodPart(kcalLeft: 1450).action).contains("1,450 kcal left"))
        XCTAssertTrue(text(Explainer.foodPart(kcalLeft: 0).action).hasPrefix("You have reached"))
        XCTAssertTrue(text(Explainer.foodPart(kcalLeft: -200).action).hasPrefix("You have reached"), "over the target is still reached")
        XCTAssertTrue(text(Explainer.foodPart(kcalLeft: nil).action).contains("calorie target"))
    }

    func testTheStudyActionNamesTheMinutesLeft() {
        XCTAssertTrue(text(Explainer.studyPart(minutesLeft: 45).action).contains("45 min"))
        XCTAssertTrue(text(Explainer.studyPart(minutesLeft: 0).action).contains("reached"))
    }

    func testTheMovementActionNeverClaimsBothHalvesWhenStepsAreUnknown() {
        let unknown = text(Explainer.movementPart(stepsTarget: 8000, stepsLeft: nil, sessionDone: true).action)
        XCTAssertFalse(unknown.contains("both halves"))
        XCTAssertTrue(text(Explainer.movementPart(stepsTarget: 8000, stepsLeft: 0, sessionDone: true).action).contains("both halves"))
        XCTAssertTrue(text(Explainer.movementPart(stepsTarget: 8000, stepsLeft: 1200, sessionDone: false).action).contains("1,200"))
        XCTAssertTrue(text(Explainer.movementPart(stepsTarget: 8000, stepsLeft: 0, sessionDone: false).action).contains("session"))
    }

    func testTheMovementWordsStateTheTargetTheScoreUses() {
        XCTAssertTrue(text(Explainer.movementPart(stepsTarget: 8000, stepsLeft: nil, sessionDone: false).how).contains("8,000"))
    }

    // MARK: Goal

    func testTheGoalToleranceInTheWordsIsTheEngineTolerance() {
        XCTAssertEqual(GoalEngine.tolerance, 0.10, "the words say a tenth of the distance")
        XCTAssertTrue(text(Explainer.goalPace(.onTrack).how).contains("a tenth"))
    }

    func testEveryPaceHasItsOwnAction() {
        let paces: [GoalProgress.Pace?] = [.ahead, .onTrack, .behind, .reached, .noReading, nil]
        let actions = paces.map { text(Explainer.goalPace($0).action) }
        XCTAssertEqual(actions[4], actions[5], "no reading and no goal say the same thing")
        XCTAssertEqual(Set(actions).count, 5)
    }

    func testTheRunReadingWordsUseTheSameSlackAsTheReader() {
        XCTAssertEqual(GoalReader.runDistanceSlack, 0.95)
        XCTAssertTrue(text(Explainer.goalReading(.runTime).how).contains("95%"))
    }

    // MARK: Streak

    func testTheStreakActionCountsTheTasksLeft() {
        XCTAssertTrue(text(Explainer.streak(tasksLeft: 3).action).contains("3 tasks left"))
        XCTAssertTrue(text(Explainer.streak(tasksLeft: 1).action).contains("1 task left"))
        XCTAssertFalse(text(Explainer.streak(tasksLeft: 1).action).contains("1 tasks"))
        XCTAssertTrue(text(Explainer.streak(tasksLeft: 0).action).contains("done"))
    }

    // MARK: Value

    func testShowingCarriesTheValueOnScreen() {
        XCTAssertEqual(Explainer.recoveryPart.showing("82%").value, "82%")
        XCTAssertNil(Explainer.recoveryPart.value)
    }
}
