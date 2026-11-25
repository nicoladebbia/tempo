//
// GuidanceExplainerTests.swift
// Tempo
//
// Round 3, guidance pass: every explainer in Recovery, Study, Lockdown, Streak, Body
// and Arena says what it is, how it is worked out and one action, and no two share an
// id (the id is the accessibility identifier, `explain.<id>`).
//

@testable import Tempo
import XCTest

final class GuidanceExplainerTests: XCTestCase {
    private var all: [Explainer] {
        [
            // Recovery
            .recoveryScore(zone: .green), .recoveryScore(zone: nil), .recoveryAverage,
            .hrv, .restingHeartRate, .bloodOxygen, .skinTemperature, .sleepAgainstNeed,
            .sleepScore, .sleepEfficiency, .sleepStages, .sleepDebt, .sleepConsistency, .respiratoryRate,
            .recoveryStrain, .dayHeartRate, .periodAverages, .strainBalance, .recoveryDistribution, .morningCheckIn,
            // Study, Lockdown, Streak
            .studyTarget, .studyStreak, .focusScore, .focusScoreLive, .averageFocus, .bestDay, .studyHeatmap,
            .lockdownProgress, .lockdownPace, .habitStreak,
            .currentStreak, .streakFreezes, .streakMilestones, .streakHistory,
            // Body
            .bodyWeight, .bodyFat, .leanMass, .bodyTrend, .bodyRecovery(zone: .yellow),
            .bodyHRV, .bodyRestingHeartRate, .bodySleep, .bodyOxygen, .bodySleepStages, .bodyComparison,
            // Arena
            .arenaLevel, .arenaDailyGoal, .arenaStreak, .arenaRank, .friendWeeklyXP, .challengeScore,
        ]
    }

    func testEveryExplainerHasWhatHowAndAnAction() {
        for explainer in all {
            XCTAssertFalse(String(localized: explainer.what).isEmpty, explainer.id)
            XCTAssertFalse(String(localized: explainer.how).isEmpty, explainer.id)
            XCTAssertFalse(String(localized: explainer.action).isEmpty, explainer.id)
            XCTAssertFalse(String(localized: explainer.title).isEmpty, explainer.id)
        }
    }

    func testNoTwoExplainersShareAnId() {
        // The recovery dial and the Body dial change their action with the zone, never their id.
        let ids = all.map(\.id)
        let distinct = Set(ids)
        XCTAssertEqual(distinct.count, ids.count - 1, "only the repeated .recoveryScore(zone:) shares an id")
        XCTAssertEqual(ids.filter { $0 == "recovery-score" }.count, 2)
    }

    func testEveryIdNamesItsArea() {
        let areas = ["recovery-", "study-", "lockdown-", "streak-", "body-", "arena-"]
        for explainer in all {
            XCTAssertTrue(areas.contains { explainer.id.hasPrefix($0) }, "\(explainer.id) has no area prefix")
        }
    }
}
