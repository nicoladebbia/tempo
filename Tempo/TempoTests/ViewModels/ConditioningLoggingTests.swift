//
// ConditioningLoggingTests.swift
// Tempo
//
// Fix #7 — logging a trainer-program conditioning block: persistence
// (dedup on re-log), target-met stamped at save time, and completion
// bridging through the EXISTING paths (persistNonGymCompletion for a
// primary conditioning day, toggleSecondarySessionComplete for a two-a-day's
// second session) — never a parallel completion flag. Also covers the
// query + grouping History reads to show results under the day's entry.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ConditioningLoggingTests: XCTestCase {
    /// Kept alive for the life of the test — `ModelContext` doesn't retain
    /// its `ModelContainer`, so if `makeContext()` returned only the context
    /// off a temporary container, the container would deinit immediately and
    /// the first insert/fetch would crash the host app.
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

    // MARK: - Persistence

    func testLogConditioningBlockPersistsResultWithTargetMet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .sprint)
        plan.programSessionKey = "prog#0#d0"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        let blockID = UUID()
        let result = vm.logConditioningBlock(
            workoutPlanID: plan.id,
            programSessionKey: "prog#0#d0",
            blockID: blockID,
            detail: "4 reps of 25y out and back in < 65\"",
            repTimesSeconds: [60, 62, 64, 58],
            durationSeconds: nil,
            distanceMeters: nil,
            roundsCompleted: nil,
            rpe: 8,
            notes: "felt strong",
            source: "manual",
            modelContext: context
        )

        XCTAssertEqual(result.targetMet, true)
        XCTAssertEqual(result.repTimesSeconds, [60, 62, 64, 58])
        XCTAssertEqual(result.rpe, 8)
        XCTAssertEqual(result.notes, "felt strong")
        XCTAssertEqual(result.blockID, blockID)
        XCTAssertEqual(result.workoutPlanID, plan.id)

        let fetched = (try? context.fetch(FetchDescriptor<ConditioningBlockResult>())) ?? []
        XCTAssertEqual(fetched.count, 1)
    }

    func testReLoggingSameBlockReplacesNotDuplicates() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .sprint)
        plan.programSessionKey = "prog#0#d0"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan
        let blockID = UUID()

        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "prog#0#d0", blockID: blockID,
            detail: "35'", repTimesSeconds: nil, durationSeconds: 20 * 60, distanceMeters: nil,
            roundsCompleted: nil, rpe: 5, notes: nil, source: "manual", modelContext: context
        )
        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "prog#0#d0", blockID: blockID,
            detail: "35'", repTimesSeconds: nil, durationSeconds: 36 * 60, distanceMeters: nil,
            roundsCompleted: nil, rpe: 7, notes: "edited", source: "manual", modelContext: context
        )

        let fetched = (try? context.fetch(FetchDescriptor<ConditioningBlockResult>())) ?? []
        XCTAssertEqual(fetched.count, 1, "re-logging edits, it doesn't duplicate")
        XCTAssertEqual(fetched.first?.durationSeconds, 36 * 60)
        XCTAssertEqual(fetched.first?.rpe, 7)
        XCTAssertEqual(fetched.first?.targetMet, true, "36min clears the 35min target")
    }

    // MARK: - Completion bridging — primary conditioning day

    func testLoggingOneBlockMarksPrimaryConditioningDayDoneViaExistingPath() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .sprint)
        plan.programSessionKey = "prog#0#d0"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        XCTAssertNotEqual(plan.status, .completed)

        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "prog#0#d0", blockID: UUID(),
            detail: "35'", repTimesSeconds: nil, durationSeconds: 35 * 60, distanceMeters: nil,
            roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )

        XCTAssertEqual(plan.status, .completed, "same completion path persistNonGymCompletion uses")
        XCTAssertNotNil(plan.finishedAt)

        // Dashboard Move / History / Week Plan all read this ActivitySession —
        // it must exist exactly as persistNonGymCompletion would write it.
        let sessions = (try? context.fetch(FetchDescriptor<ActivitySession>())) ?? []
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.workoutPlanID, plan.id)
        XCTAssertEqual(sessions.first?.source, "manual")
    }

    func testLoggingASecondBlockDoesNotDoubleCompleteOrDuplicateActivitySession() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .sprint)
        plan.programSessionKey = "prog#0#d0"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "prog#0#d0", blockID: UUID(),
            detail: "35'", repTimesSeconds: nil, durationSeconds: 35 * 60, distanceMeters: nil,
            roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )
        let firstFinishedAt = plan.finishedAt
        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "prog#0#d0", blockID: UUID(),
            detail: "5 km", repTimesSeconds: nil, durationSeconds: nil, distanceMeters: 5000,
            roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )

        XCTAssertEqual(plan.status, .completed)
        XCTAssertEqual(plan.finishedAt, firstFinishedAt, "second log doesn't re-run completion")

        let sessions = (try? context.fetch(FetchDescriptor<ActivitySession>())) ?? []
        XCTAssertEqual(sessions.count, 1, "still exactly one ActivitySession for the plan")

        let results = (try? context.fetch(FetchDescriptor<ConditioningBlockResult>())) ?? []
        XCTAssertEqual(results.count, 2, "both blocks' results are kept")
    }

    // MARK: - Completion bridging — two-a-day second session

    func testLoggingSecondSessionBlockMarksSecondaryDoneViaExistingToggle() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.programSecondaryKey = "prog#0#d1"
        plan.secondarySessionTypeRaw = WorkoutType.conditioning.rawValue
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        XCTAssertFalse(plan.secondaryCompleted)

        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "prog#0#d1", blockID: UUID(),
            detail: "2 x 10times (5R-5L) 10m+5m", repTimesSeconds: nil, durationSeconds: nil,
            distanceMeters: nil, roundsCompleted: 20, rpe: 6, notes: nil, source: "manual", modelContext: context
        )

        XCTAssertTrue(plan.secondaryCompleted, "same flag toggleSecondarySessionComplete/Mark done sets")
        // The lift's own completion (plan.status) is untouched — the two-a-day
        // rule is the bonus cardio never gates the day.
        XCTAssertNotEqual(plan.status, .completed)

        let sessions = (try? context.fetch(FetchDescriptor<ActivitySession>())) ?? []
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.workoutType, WorkoutType.conditioning.rawValue)
    }

    func testLoggingSecondaryDoesNotAffectAlreadyCompletedPrimary() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.programSecondaryKey = "prog#0#d1"
        plan.secondarySessionTypeRaw = WorkoutType.conditioning.rawValue
        plan.status = .completed
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "prog#0#d1", blockID: UUID(),
            detail: "15'", repTimesSeconds: nil, durationSeconds: 15 * 60, distanceMeters: nil,
            roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )

        XCTAssertTrue(plan.secondaryCompleted)
        XCTAssertEqual(plan.status, .completed, "the lift's completion is untouched")
    }

    // MARK: - Read / History grouping

    func testConditioningResultsForSessionKeyOnlyReturnsThatKey() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.programSessionKey = "progA#0#d0"
        plan.programSecondaryKey = "progA#0#d1"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "progA#0#d0", blockID: UUID(),
            detail: "5 km", repTimesSeconds: nil, durationSeconds: nil, distanceMeters: 5000,
            roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )
        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "progA#0#d1", blockID: UUID(),
            detail: "15'", repTimesSeconds: nil, durationSeconds: 900, distanceMeters: nil,
            roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )

        let primaryResults = vm.conditioningResults(forSessionKey: "progA#0#d0", modelContext: context)
        let secondaryResults = vm.conditioningResults(forSessionKey: "progA#0#d1", modelContext: context)
        XCTAssertEqual(primaryResults.count, 1)
        XCTAssertEqual(secondaryResults.count, 1)
        XCTAssertEqual(primaryResults.first?.distanceMeters, 5000)
        XCTAssertEqual(secondaryResults.first?.durationSeconds, 900)
    }

    /// Mirrors the grouping WorkoutHistoryView does — fetch every result for
    /// a plan, group by `programSessionKey`. History shows one section per
    /// session (a two-a-day's lift + conditioning second session both
    /// surface under the same day's card, but grouped apart).
    func testHistoryGroupingByProgramSessionKey() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.status = .completed
        plan.programSessionKey = "progB#0#d0"
        plan.programSecondaryKey = "progB#0#d1"
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan

        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "progB#0#d0", blockID: UUID(),
            detail: "4 reps of 25y in < 65\"", repTimesSeconds: [60, 61], durationSeconds: nil,
            distanceMeters: nil, roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )
        vm.logConditioningBlock(
            workoutPlanID: plan.id, programSessionKey: "progB#0#d1", blockID: UUID(),
            detail: "35'", repTimesSeconds: nil, durationSeconds: 2100, distanceMeters: nil,
            roundsCompleted: nil, rpe: nil, notes: nil, source: "manual", modelContext: context
        )
        // A different plan's result must never bleed into this plan's grouping.
        let otherPlan = WorkoutPlan(date: Date().addingTimeInterval(-86400), type: .sprint)
        otherPlan.programSessionKey = "progB#0#d0"
        context.insert(otherPlan)
        try context.save()
        context.insert(ConditioningBlockResult(
            workoutPlanID: otherPlan.id, programSessionKey: "progB#0#d0", blockID: UUID(),
            durationSeconds: 600, source: "manual"
        ))
        try context.save()

        let allResults = (try? context.fetch(FetchDescriptor<ConditioningBlockResult>())) ?? []
        let forThisPlan = allResults.filter { $0.workoutPlanID == plan.id }
        XCTAssertEqual(forThisPlan.count, 2, "only this plan's two logged blocks — the other plan's row is excluded")

        let grouped = Dictionary(grouping: forThisPlan) { $0.programSessionKey ?? "" }
        XCTAssertEqual(grouped.keys.sorted(), ["progB#0#d0", "progB#0#d1"])
        XCTAssertEqual(grouped["progB#0#d0"]?.count, 1)
        XCTAssertEqual(grouped["progB#0#d1"]?.count, 1)
    }
}
