//
// WatchSnapshotBuilderTests.swift
// Tempo
//
// Created by Tempo on 9/23/26.
//
//

//
// WatchSnapshotBuilderTests.swift
// Tempo
//
// §22 — pins the pure assembly of the watch's WatchSnapshot: real
// non-negotiable titles/ids (not "Task N"), the honest `nil` leaderboard
// position (there is no real leaderboard data source anywhere in the app —
// see LeaderboardView.loadMockData), the next-incomplete-task name, and
// `hasRealData: true` on every built snapshot (only `WatchSnapshot.empty`
// carries `false`).
//

@testable import Tempo
import XCTest

final class WatchSnapshotBuilderTests: XCTestCase {
    private func item(_ title: String, done: Bool) -> WatchNonNegotiableItem {
        WatchNonNegotiableItem(id: UUID().uuidString, title: title, isCompleted: done)
    }

    func testBuildMarksRealDataAndCountsCompletion() {
        let input = WatchSnapshotBuilder.Input(
            dailyScore: 62,
            recoveryScore: 71,
            recoveryZone: .green,
            sleepHours: 7.5,
            hrv: 55,
            rhr: 48,
            nonNegotiables: [item("Train", done: true), item("Study", done: false)],
            leisureUnlocked: false,
            timeToLeisureUnlock: 3600,
            currentStreak: 4,
            totalXP: 250,
            nextMeal: WatchNextMeal(id: "m1", name: "Lunch"),
            now: Date(timeIntervalSince1970: 0)
        )
        let snapshot = WatchSnapshotBuilder.build(from: input)

        XCTAssertTrue(snapshot.hasRealData)
        XCTAssertEqual(snapshot.dailyScore, 62)
        XCTAssertEqual(snapshot.recoveryZone, "green")
        XCTAssertEqual(snapshot.nnCompleted, 1)
        XCTAssertEqual(snapshot.nnTotal, 2)
        XCTAssertEqual(snapshot.nextTaskName, "Study", "First INCOMPLETE item, not the first item")
        XCTAssertEqual(snapshot.nextTaskTimeRemaining, "1h0m")
        XCTAssertEqual(snapshot.currentStreak, 4)
        XCTAssertEqual(snapshot.xp, 250)
        XCTAssertEqual(snapshot.nextMeal?.name, "Lunch")
    }

    func testLeaderboardPositionIsAlwaysNilNeverInvented() {
        // No real leaderboard data source exists anywhere in the app yet —
        // the builder must never invent a rank, regardless of other inputs.
        let input = WatchSnapshotBuilder.Input(
            dailyScore: 90, recoveryScore: 90, recoveryZone: .green,
            sleepHours: 8, hrv: 70, rhr: 45,
            nonNegotiables: [], leisureUnlocked: true, timeToLeisureUnlock: nil,
            currentStreak: 30, totalXP: 5000, nextMeal: nil
        )
        let snapshot = WatchSnapshotBuilder.build(from: input)
        XCTAssertNil(snapshot.leaderboardPosition)
    }

    func testLeisureUnlockedHidesNextTaskInsteadOfShowingStaleOne() {
        let input = WatchSnapshotBuilder.Input(
            dailyScore: 100, recoveryScore: 80, recoveryZone: .green,
            sleepHours: 8, hrv: 70, rhr: 45,
            nonNegotiables: [item("Train", done: true), item("Study", done: true)],
            leisureUnlocked: true,
            timeToLeisureUnlock: nil,
            currentStreak: 5, totalXP: 100, nextMeal: nil
        )
        let snapshot = WatchSnapshotBuilder.build(from: input)
        XCTAssertEqual(snapshot.nnCompleted, 2)
        XCTAssertEqual(snapshot.nnTotal, 2)
        XCTAssertTrue(snapshot.nextTaskName.isEmpty)
        XCTAssertTrue(snapshot.nextTaskTimeRemaining.isEmpty)
    }

    func testMissingBiometricsDefaultToZeroNotCrash() {
        let input = WatchSnapshotBuilder.Input(
            dailyScore: nil, recoveryScore: nil, recoveryZone: nil,
            sleepHours: nil, hrv: nil, rhr: nil,
            nonNegotiables: [], leisureUnlocked: false, timeToLeisureUnlock: nil,
            currentStreak: 0, totalXP: 0, nextMeal: nil
        )
        let snapshot = WatchSnapshotBuilder.build(from: input)
        XCTAssertEqual(snapshot.dailyScore, 0)
        XCTAssertEqual(snapshot.recoveryZone, "unknown")
        XCTAssertEqual(snapshot.recoveryScore, 0)
        XCTAssertEqual(snapshot.sleepHours, 0)
        XCTAssertTrue(snapshot.hasRealData, "Missing biometrics is real data (e.g. no Whoop) — not the same as never-synced")
    }

    func testRemainingTimeFormattingUnderAnHour() {
        let input = WatchSnapshotBuilder.Input(
            dailyScore: 50, recoveryScore: 50, recoveryZone: .yellow,
            sleepHours: 6, hrv: 40, rhr: 55,
            nonNegotiables: [item("Study", done: false)],
            leisureUnlocked: false,
            timeToLeisureUnlock: 25 * 60,
            currentStreak: 1, totalXP: 10, nextMeal: nil
        )
        let snapshot = WatchSnapshotBuilder.build(from: input)
        XCTAssertEqual(snapshot.nextTaskTimeRemaining, "25m")
    }

    func testEmptySnapshotHasNoRealData() {
        XCTAssertFalse(WatchSnapshot.empty.hasRealData)
        XCTAssertEqual(WatchSnapshot.empty.dailyScore, 0)
        XCTAssertTrue(WatchSnapshot.empty.nonNegotiables.isEmpty)
        XCTAssertNil(WatchSnapshot.empty.leaderboardPosition)
    }
}
