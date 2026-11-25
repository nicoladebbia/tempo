//
// SetupChecklistTests.swift
// TempoTests
//
// The "Get set up" checklist is built from real state and never shows to
// someone who is already set up.
//

@testable import Tempo
import XCTest

final class SetupChecklistTests: XCTestCase {
    private func signals(
        health: Bool = false, whoop: Bool = false, diet: Bool = false,
        training: Bool = false, tasks: Int = 0, resolved: Bool = true
    ) -> SetupChecklist.Signals {
        .init(
            healthAllowed: health, whoopConnected: whoop, hasDietProfile: diet,
            hasChosenTraining: training, taskCount: tasks, resolved: resolved
        )
    }

    func testAFreshAccountHasFiveOpenLines() {
        let list = SetupChecklist(signals())
        XCTAssertEqual(list.total, 5)
        XCTAssertEqual(list.doneCount, 0)
        XCTAssertEqual(list.remaining.map(\.step), [.health, .whoop, .food, .training, .tasks])
        XCTAssertTrue(list.isVisible(dismissed: false))
    }

    func testEachLineFollowsItsOwnSignal() throws {
        XCTAssertTrue(try XCTUnwrap(SetupChecklist(signals(health: true)).lines.first { $0.step == .health }?.done))
        XCTAssertTrue(try XCTUnwrap(SetupChecklist(signals(whoop: true)).lines.first { $0.step == .whoop }?.done))
        XCTAssertTrue(try XCTUnwrap(SetupChecklist(signals(diet: true)).lines.first { $0.step == .food }?.done))
        XCTAssertTrue(try XCTUnwrap(SetupChecklist(signals(training: true)).lines.first { $0.step == .training }?.done))
        XCTAssertTrue(try XCTUnwrap(SetupChecklist(signals(tasks: 2)).lines.first { $0.step == .tasks }?.done))
    }

    func testAnAthleteWhoIsFullySetUpNeverSeesTheCard() {
        let list = SetupChecklist(signals(health: true, whoop: true, diet: true, training: true, tasks: 4))
        XCTAssertTrue(list.isConfigured)
        XCTAssertEqual(list.doneCount, 5)
        XCTAssertFalse(list.isVisible(dismissed: false))
    }

    func testSomeoneWithoutABandOrHealthIsStillConfigured() {
        let list = SetupChecklist(signals(diet: true, training: true, tasks: 1))
        XCTAssertTrue(list.isConfigured)
        XCTAssertFalse(list.isVisible(dismissed: false))
    }

    func testHealthAndWhoopAloneDoNotMakeSomeoneConfigured() {
        let list = SetupChecklist(signals(health: true, whoop: true))
        XCTAssertFalse(list.isConfigured)
        XCTAssertTrue(list.isVisible(dismissed: false))
    }

    func testLaterHidesTheCard() {
        XCTAssertFalse(SetupChecklist(signals()).isVisible(dismissed: true))
    }

    func testTheCardWaitsUntilConnectionStatesAreKnown() {
        XCTAssertFalse(SetupChecklist(signals(resolved: false)).isVisible(dismissed: false))
    }

    func testEveryStepHasWordsAnIconAndAUniqueId() {
        let steps = SetupStep.allCases
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        for step in steps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.detail.isEmpty)
            XCTAssertFalse(step.icon.isEmpty)
        }
    }

    func testTheCoreStepsAreFoodTrainingAndTasks() {
        XCTAssertEqual(Set(SetupStep.allCases.filter(\.isCore)), [.food, .training, .tasks])
    }
}
