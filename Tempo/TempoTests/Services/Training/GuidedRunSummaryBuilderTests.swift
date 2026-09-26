//
// GuidedRunSummaryBuilderTests.swift
// Tempo
//
// Guided run mode — the pure mapping from a finished session's records to
// `TrainingViewModel.logConditioningBlock` inputs. The actual persistence
// call is covered end to end in GuidedRunLoggingIntegrationTests.
//

@testable import Tempo
import XCTest

final class GuidedRunSummaryBuilderTests: XCTestCase {
    func testOnlyBlocksWithARecordedResultAreIncluded() {
        let blockWithResult = UUID()
        let blockNeverStarted = UUID()
        let plan = GuidedRunPlan(
            blocks: [
                GuidedRunBlock(
                    id: blockWithResult, name: "Shuttle", trainerText: "4 reps of 25y < 65\"",
                    rawDetail: "4 reps of 25y < 65\"",
                    target: ConditioningTargetParser.parse(detail: "4 reps of 25y < 65\""),
                    restSeconds: 90, restIsDefault: false
                ),
                GuidedRunBlock(
                    id: blockNeverStarted, name: "Cool Down", trainerText: "10'", rawDetail: "10'",
                    target: ConditioningTargetParser.parse(detail: "10'"), restSeconds: 60, restIsDefault: true
                ),
            ],
            steps: []
        )
        let results: [UUID: GuidedRunBlockRecord] = [
            blockWithResult: GuidedRunBlockRecord(blockID: blockWithResult, repTimesSeconds: [58, 62]),
        ]

        let inputs = GuidedRunSummaryBuilder.blockInputs(plan: plan, results: results, rpe: 8, notes: "felt strong")

        XCTAssertEqual(inputs.count, 1)
        let input = inputs[0]
        XCTAssertEqual(input.blockID, blockWithResult)
        XCTAssertEqual(input.detail, "4 reps of 25y < 65\"")
        XCTAssertEqual(input.repTimesSeconds, [58, 62])
        XCTAssertNil(input.durationSeconds)
        XCTAssertNil(input.distanceMeters)
        XCTAssertNil(input.roundsCompleted)
        XCTAssertEqual(input.rpe, 8)
        XCTAssertEqual(input.notes, "felt strong")
    }

    func testContinuousResultCarriesDurationAndDistance() {
        let blockID = UUID()
        let plan = GuidedRunPlan(
            blocks: [
                GuidedRunBlock(
                    id: blockID, name: "Fartleck", trainerText: "35'", rawDetail: "35'",
                    target: ConditioningTargetParser.parse(detail: "35'"), restSeconds: 60, restIsDefault: true
                ),
            ],
            steps: []
        )
        let results: [UUID: GuidedRunBlockRecord] = [
            blockID: GuidedRunBlockRecord(blockID: blockID, durationSeconds: 2100, distanceMeters: 5200),
        ]

        let inputs = GuidedRunSummaryBuilder.blockInputs(plan: plan, results: results, rpe: nil, notes: nil)

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].durationSeconds, 2100)
        XCTAssertEqual(inputs[0].distanceMeters, 5200)
        XCTAssertNil(inputs[0].repTimesSeconds)
    }

    func testRoundsResultMapsRoundsCompleted() {
        let blockID = UUID()
        let plan = GuidedRunPlan(
            blocks: [
                GuidedRunBlock(
                    id: blockID, name: "Ladder", trainerText: "2 x 10times", rawDetail: "2 x 10times",
                    target: ConditioningTargetParser.parse(detail: "2 x 10times"), restSeconds: 60, restIsDefault: true
                ),
            ],
            steps: []
        )
        let results: [UUID: GuidedRunBlockRecord] = [
            blockID: GuidedRunBlockRecord(blockID: blockID, roundsCompleted: 18, skippedCount: 2),
        ]

        let inputs = GuidedRunSummaryBuilder.blockInputs(plan: plan, results: results, rpe: 6, notes: nil)

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].roundsCompleted, 18)
    }
}
