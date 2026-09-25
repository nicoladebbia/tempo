//
// GuidedRunLoggingIntegrationTests.swift
// Tempo
//
// Guided run mode — the summary screen's save path end to end: GuidedRunSummaryBuilder's
// mapping fed straight into the EXISTING `TrainingViewModel.logConditioningBlock`
// (same call the manual ConditioningLogSheet uses — see
// TrainingViewModel+ConditioningLogging.swift's header for why that matters:
// History/trainer report/completion/Dashboard Move/Week Plan all read
// through that one path, never a parallel guided-run-only flag).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class GuidedRunLoggingIntegrationTests: XCTestCase {
    private var container: ModelContainer!

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    private func makeContext() throws -> ModelContext {
        container = try TempoModelContainer.create(inMemory: true)
        return container.mainContext
    }

    func testGuidedRunSummarySavesOneConditioningBlockResultPerBlockAndCompletesTheSession() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .sprint)
        plan.programSessionKey = "prog#0#d0"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        let shuttle1 = UUID()
        let shuttle2 = UUID()
        let runPlan = GuidedRunPlan(
            blocks: [
                GuidedRunBlock(
                    id: shuttle1, name: "Shuttle 1", trainerText: "4 reps of 25y < 65\"",
                    rawDetail: "4 reps of 25y < 65\"",
                    target: ConditioningTargetParser.parse(detail: "4 reps of 25y < 65\""),
                    restSeconds: 90, restIsDefault: false
                ),
                GuidedRunBlock(
                    id: shuttle2, name: "Shuttle 2", trainerText: "4 reps 80y < 55\"",
                    rawDetail: "4 reps 80y < 55\"",
                    target: ConditioningTargetParser.parse(detail: "4 reps 80y < 55\""),
                    restSeconds: 90, restIsDefault: false
                ),
            ],
            steps: []
        )
        let results: [UUID: GuidedRunBlockRecord] = [
            shuttle1: GuidedRunBlockRecord(blockID: shuttle1, repTimesSeconds: [60, 61, 59, 58]),
            shuttle2: GuidedRunBlockRecord(blockID: shuttle2, repTimesSeconds: [50, 52, 49, 53]),
        ]
        let inputs = GuidedRunSummaryBuilder.blockInputs(plan: runPlan, results: results, rpe: 8, notes: "hard but clean")

        XCTAssertEqual(inputs.count, 2)
        for input in inputs {
            vm.logConditioningBlock(
                workoutPlanID: plan.id,
                programSessionKey: "prog#0#d0",
                blockID: input.blockID,
                detail: input.detail,
                repTimesSeconds: input.repTimesSeconds,
                durationSeconds: input.durationSeconds,
                distanceMeters: input.distanceMeters,
                roundsCompleted: input.roundsCompleted,
                rpe: input.rpe,
                notes: input.notes,
                source: "manual",
                modelContext: context
            )
        }

        let saved = vm.conditioningResults(forSessionKey: "prog#0#d0", modelContext: context)
        XCTAssertEqual(saved.count, 2)
        let shuttle1Result = try XCTUnwrap(saved.first { $0.blockID == shuttle1 })
        XCTAssertEqual(shuttle1Result.repTimesSeconds, [60, 61, 59, 58])
        // Cap is 65s — all four reps under it.
        XCTAssertEqual(shuttle1Result.targetMet, true)
        let shuttle2Result = try XCTUnwrap(saved.first { $0.blockID == shuttle2 })
        // Cap is 55s — 50/52/49 under, 53 under too, all pass.
        XCTAssertEqual(shuttle2Result.targetMet, true)

        // Logging any block of today's plan bridges completion through the
        // EXISTING path (persistNonGymCompletion), same as the manual sheet.
        XCTAssertEqual(plan.status, .completed)
    }

    func testASlowerRepMarksTargetNotMet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .sprint)
        plan.programSessionKey = "prog#0#d0"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        let shuttle1 = UUID()
        let runPlan = GuidedRunPlan(
            blocks: [
                GuidedRunBlock(
                    id: shuttle1, name: "Shuttle 1", trainerText: "4 reps of 25y < 65\"",
                    rawDetail: "4 reps of 25y < 65\"",
                    target: ConditioningTargetParser.parse(detail: "4 reps of 25y < 65\""),
                    restSeconds: 90, restIsDefault: false
                ),
            ],
            steps: []
        )
        let results: [UUID: GuidedRunBlockRecord] = [
            shuttle1: GuidedRunBlockRecord(blockID: shuttle1, repTimesSeconds: [60, 61, 59, 70]),
        ]
        let inputs = GuidedRunSummaryBuilder.blockInputs(plan: runPlan, results: results, rpe: nil, notes: nil)
        let input = try XCTUnwrap(inputs.first)

        vm.logConditioningBlock(
            workoutPlanID: plan.id,
            programSessionKey: "prog#0#d0",
            blockID: input.blockID,
            detail: input.detail,
            repTimesSeconds: input.repTimesSeconds,
            durationSeconds: input.durationSeconds,
            distanceMeters: input.distanceMeters,
            roundsCompleted: input.roundsCompleted,
            rpe: input.rpe,
            notes: input.notes,
            source: "manual",
            modelContext: context
        )

        let saved = vm.conditioningResults(forSessionKey: "prog#0#d0", modelContext: context)
        XCTAssertEqual(saved.first?.targetMet, false)
    }
}
