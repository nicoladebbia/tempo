//
// LoggerCursorAndCleanupTests.swift
// Tempo
//
// Regression tests for the active-workout logger QA pass: the cursor must
// never rest on a missing / already-completed set (set removal, rest, watch
// collision), an all-skipped session must not leave a zombie plan, discard
// must undo everything, pauses/calls must not inflate duration, and a
// finished gym session reaches Apple Health.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class LoggerCursorAndCleanupTests: XCTestCase {
    private var healthKit = MockHealthKitService()

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        healthKit = MockHealthKitService()
        return TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: healthKit
        )
    }

    /// One plan, `setCounts.count` exercises ("Bench Press", "Row", …) with N sets each.
    private func seedPlan(
        context: ModelContext,
        setCounts: [Int],
        equipment: Equipment = .barbell,
        targetWeight: Double? = 80
    ) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.status = .inProgress
        plan.startedAt = Date().addingTimeInterval(-600)
        context.insert(plan)
        let names = ["Bench Press", "Barbell Row", "Overhead Press"]
        for (order, count) in setCounts.enumerated() {
            let exercise = Exercise(
                name: names[order], muscleGroup: .chest, equipment: equipment,
                movementPattern: .horizontalPush, isCompound: true
            )
            context.insert(exercise)
            let slot = PlannedExercise(order: order, workoutPlan: plan, exercise: exercise)
            slot.sets = (1 ... count).map {
                PlannedSet(setNumber: $0, targetReps: 8, targetWeight: targetWeight, plannedExercise: slot)
            }
        }
        try? context.save()
        return plan
    }

    private func start(_ vm: TrainingViewModel, plan: WorkoutPlan, exercise: Int = 0, set: Int = 0) {
        vm.todayPlan = plan
        vm.currentExerciseIndex = exercise
        vm.currentSetIndex = set
        vm.sessionState = .exercise(.setActive(exerciseIndex: exercise, setIndex: set))
    }

    private func assertSetActive(
        _ vm: TrainingViewModel, exercise: Int, set: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case let .exercise(.setActive(ex, idx)) = vm.sessionState else {
            XCTFail("Expected .setActive, got \(vm.sessionState)", file: file, line: line)
            return
        }
        XCTAssertEqual(ex, exercise, file: file, line: line)
        XCTAssertEqual(idx, set, file: file, line: line)
        XCTAssertEqual(vm.currentExerciseIndex, exercise, file: file, line: line)
        XCTAssertEqual(vm.currentSetIndex, set, file: file, line: line)
    }

    // MARK: - 1. Structural changes never strand the cursor

    func testRemovingTheSetOnScreenReroutesInsteadOfStranding() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2, 1])
        start(vm, plan: plan)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        vm.skipRest() // now on ex 0, set 1 (uncompleted, last)
        assertSetActive(vm, exercise: 0, set: 1)

        vm.removeLastUncompletedSet(from: 0, modelContext: context)

        // The on-screen set is gone → land on the next real work, not at
        // index == sets.count where Finish Set / Skip silently die.
        assertSetActive(vm, exercise: 1, set: 0)
        vm.resetState()
    }

    func testRemovingSetsDuringRestNeverLeavesCursorOutOfRange() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3])
        start(vm, plan: plan)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        guard case .exercise(.resting) = vm.sessionState else {
            return XCTFail("expected rest")
        }

        vm.removeLastUncompletedSet(from: 0, modelContext: context)
        vm.removeLastUncompletedSet(from: 0, modelContext: context)
        vm.skipRest()

        // Only the completed set is left → session is done, not parked on set 1 of 1.
        XCTAssertEqual(vm.sessionState, .summary)
        vm.resetState()
    }

    func testRemovingLaterSetKeepsCursorOnTheSameSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3])
        start(vm, plan: plan)

        vm.removeLastUncompletedSet(from: 0, modelContext: context)

        assertSetActive(vm, exercise: 0, set: 0)
        vm.resetState()
    }

    func testWatchLoggedSetDuringRestIsSkippedWhenRestEnds() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3])
        start(vm, plan: plan)
        vm.logSet(weight: 80, reps: 8, modelContext: context) // rest starts

        // Watch logs set 2 while the phone is resting (direct path).
        XCTAssertTrue(vm.applyWatchSetLog(exerciseName: "Bench Press", reps: 8, weightKg: 82.5, modelContext: context))
        vm.skipRest()

        assertSetActive(vm, exercise: 0, set: 2)
        vm.resetState()
    }

    func testSetAddedDuringFinalRestIsVisited() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [1, 1])
        start(vm, plan: plan)
        vm.logSet(weight: 80, reps: 8, modelContext: context) // last set of ex 0 → rest → .nextExercise
        XCTAssertEqual(vm.pendingRestAction, .nextExercise)

        vm.addSet(to: 0, modelContext: context)
        vm.skipRest()

        assertSetActive(vm, exercise: 0, set: 1)
        vm.resetState()
    }

    func testRestEndingOnLastExerciseGoesToSummary() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [1])
        start(vm, plan: plan)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        // Last set of last exercise → straight to summary (unchanged behaviour).
        XCTAssertEqual(vm.sessionState, .summary)
        vm.resetState()
    }

    // MARK: - 2. Skipping everything is not a workout

    func testSkippingEverySetDoesNotLeaveAZombieInProgressPlan() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        start(vm, plan: plan)

        vm.skipCurrentSet(modelContext: context)
        vm.skipCurrentSet(modelContext: context)

        XCTAssertEqual(vm.sessionState, .discarded)
        XCTAssertNotEqual(plan.status, .inProgress, "No 'Resume your workout?' forever")
        XCTAssertEqual(plan.status, .skipped, "Skip deletes the sets, so nothing is left to redo")
    }

    // MARK: - 3. HealthKit

    func testFinishedGymWorkoutIsWrittenToHealthKit() async throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        start(vm, plan: plan)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        vm.skipRest()
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        vm.elapsedSeconds = 1800

        XCTAssertTrue(vm.persistCompletion(modelContext: context))
        await vm.healthKitWriteTask?.value

        let written = healthKit.writtenWorkouts
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.workoutType, "strength")
        XCTAssertEqual(written.first?.totalVolumeKg, 1280)
        XCTAssertEqual(written.first?.durationMinutes ?? 0, 30, accuracy: 0.01)

        // Idempotent persist must not write a second HK workout.
        XCTAssertFalse(vm.persistCompletion(modelContext: context))
        await vm.healthKitWriteTask?.value
        XCTAssertEqual(healthKit.writtenWorkouts.count, 1)
        vm.resetState()
    }

    func testEmptySessionWritesNothingToHealthKit() async throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [1])
        start(vm, plan: plan)

        XCTAssertFalse(vm.persistCompletion(modelContext: context))
        await vm.healthKitWriteTask?.value
        XCTAssertTrue(healthKit.writtenWorkouts.isEmpty)
    }

    // MARK: - 4. Calls / pauses vs duration

    func testPhoneCallTimeIsCountedAsPauseNotTraining() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        start(vm, plan: plan)

        vm.handleCallChange(callEnded: false)
        XCTAssertNotNil(vm.callStartedAt)
        vm.callStartedAt = Date().addingTimeInterval(-600) // a 10-minute call
        vm.handleCallChange(callEnded: true)

        XCTAssertEqual(vm.totalPauseDuration, 600, accuracy: 2)
        XCTAssertEqual(plan.pausedSeconds, 600, accuracy: 2, "Mirrored on the plan for crash recovery")
        XCTAssertNil(vm.callStartedAt)
        vm.resetState()
    }

    func testCrashResumeRestoresPersistedPauseTime() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        plan.startedAt = Date().addingTimeInterval(-1000)
        plan.pausedSeconds = 600
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.resumeFromCrash()

        XCTAssertEqual(vm.totalPauseDuration, 600, accuracy: 0.1)
        XCTAssertEqual(vm.elapsedSeconds, 400, accuracy: 3)
        vm.resetState()
    }

    func testPauseStampsMarkerAndResumeClearsIt() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        start(vm, plan: plan)

        vm.pause()
        XCTAssertNotNil(plan.pausedAt, "A pause must be persisted the moment it starts")
        vm.resume()
        XCTAssertNil(plan.pausedAt)

        vm.handleCallChange(callEnded: false)
        XCTAssertNotNil(plan.pausedAt, "A phone call is a pause too")
        vm.handleCallChange(callEnded: true)
        XCTAssertNil(plan.pausedAt)
        vm.resetState()
    }

    func testKillWhilePausedDoesNotCountThePauseAsTraining() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        plan.startedAt = Date().addingTimeInterval(-1000)
        plan.pausedSeconds = 100 // an earlier, already-resumed pause
        plan.pausedAt = Date().addingTimeInterval(-300) // app killed while paused
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.resumeFromCrash()

        XCTAssertEqual(vm.elapsedSeconds, 600, accuracy: 3)
        XCTAssertEqual(plan.pausedSeconds, 400, accuracy: 3)
        XCTAssertNil(plan.pausedAt, "The open pause is folded in and closed")
        vm.resetState()
    }

    func testCrashHoursLaterDoesNotCountDeadAppTimeAsTraining() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3])
        let now = Date()
        plan.startedAt = now.addingTimeInterval(-3 * 3600)
        let first = try XCTUnwrap(plan.orderedExercises.first?.orderedSets.first)
        first.completed = true
        first.actualReps = 8
        first.actualWeight = 80
        first.completedAt = now.addingTimeInterval(-3 * 3600 + 1200) // 20 min in
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.resumeFromCrash()

        // 20 min up to the last set + the 10 min idle allowance — not 3 hours.
        XCTAssertEqual(vm.elapsedSeconds, 1800, accuracy: 3)
        vm.resetState()
    }

    func testCrashSoonAfterStartKeepsTheRealClock() {
        let plan = WorkoutPlan(date: Date(), type: .push)
        let now = Date()
        plan.startedAt = now.addingTimeInterval(-500)
        plan.pausedSeconds = 60
        XCTAssertEqual(
            TrainingViewModel.recoveredPauseSeconds(for: plan, now: now), 60, accuracy: 0.1,
            "Within the idle allowance nothing extra is treated as paused"
        )
    }

    func testFinishingWhilePausedCountsTheFinalPause() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        start(vm, plan: plan)
        let set = try XCTUnwrap(plan.orderedExercises.first?.orderedSets.first)
        set.completed = true
        set.actualReps = 8
        set.actualWeight = 80

        let pauseStart = Date().addingTimeInterval(-300)
        vm.sessionState = .paused(
            previousState: .exercise(.setActive(exerciseIndex: 0, setIndex: 1)),
            pauseStartTime: pauseStart
        )
        plan.pausedAt = pauseStart
        vm.finishWorkout(modelContext: context)

        XCTAssertEqual(vm.sessionState, .summary)
        XCTAssertEqual(plan.pausedSeconds, 300, accuracy: 3)
        XCTAssertNil(plan.pausedAt)
        vm.resetState()
    }

    func testActualDurationExcludesPausedTime() {
        let plan = WorkoutPlan(date: Date(), type: .push)
        let start = Date()
        plan.startedAt = start
        plan.finishedAt = start.addingTimeInterval(3600)
        plan.pausedSeconds = 600
        XCTAssertEqual(plan.actualDurationMinutes, 50)
    }

    // MARK: - Severe pain → "End the session"

    func testPainEndWithLoggedSetsFinishesToSummary() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3])
        start(vm, plan: plan)
        let set = try XCTUnwrap(plan.orderedExercises.first?.orderedSets.first)
        set.completed = true
        set.actualReps = 8
        set.actualWeight = 80
        let report = PainReport(bodyArea: .knee, severity: 8)
        context.insert(report)

        vm.endSessionDueToPain(report, modelContext: context)

        XCTAssertEqual(report.actionTaken, .endedSession)
        XCTAssertEqual(vm.sessionState, .summary, "The session really ends — no ghost session behind the screen")
        XCTAssertTrue(set.completed, "Logged work is kept")
        vm.resetState()
    }

    func testPainEndWithNothingLoggedClosesAndRestsTheDay() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3])
        start(vm, plan: plan)
        let report = PainReport(bodyArea: .back, severity: 9)
        context.insert(report)

        vm.endSessionDueToPain(report, modelContext: context)

        XCTAssertEqual(vm.sessionState, .discarded)
        XCTAssertEqual(plan.status, .skipped)
        XCTAssertEqual(plan.skipReason, .floorForced, "Pain is the body saying no — not a missed day")
        vm.resetState()
    }

    func testPainEndDuringACallStillFinishes() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        start(vm, plan: plan)
        let set = try XCTUnwrap(plan.orderedExercises.first?.orderedSets.first)
        set.completed = true
        set.actualReps = 8
        set.actualWeight = 80
        vm.handleCallChange(callEnded: false)
        let report = PainReport(bodyArea: .shoulder, severity: 8)
        context.insert(report)

        vm.endSessionDueToPain(report, modelContext: context)

        XCTAssertEqual(vm.sessionState, .summary)
        XCTAssertNil(plan.pausedAt)
        vm.resetState()
    }

    func testPainEndWithoutASessionOnlyRecordsTheReport() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        plan.status = .planned
        plan.startedAt = nil
        vm.todayPlan = plan
        vm.sessionState = .idle
        let report = PainReport(bodyArea: .knee, severity: 8)
        context.insert(report)

        XCTAssertFalse(vm.canEndSessionForPain, "From Today's list there is no session to end")
        vm.endSessionDueToPain(report, modelContext: context)

        XCTAssertEqual(vm.sessionState, .idle)
        XCTAssertEqual(plan.status, .planned)
    }

    // MARK: - Benched day (recovery floor / pain) → "Train anyway"

    private func seedBenchedPlan(context: ModelContext, reason: SkipReason) -> WorkoutPlan {
        let plan = seedPlan(context: context, setCounts: [2])
        plan.status = .skipped
        plan.skipReason = reason
        plan.startedAt = nil
        return plan
    }

    func testBenchedDayCannotBeStartedDirectly() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedBenchedPlan(context: context, reason: .floorForced)
        vm.sessionState = .idle

        XCTAssertFalse(vm.canStartWorkout)
        XCTAssertFalse(vm.startWorkout(), "The Dashboard Start button must not walk past the recovery block")
        XCTAssertEqual(vm.sessionState, .idle)
        XCTAssertTrue(vm.isRecoveryBenched)
    }

    func testTrainAnywayReopensABenchedDay() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedBenchedPlan(context: context, reason: .floorForced)
        vm.todayPlan = plan
        vm.sessionState = .idle

        vm.trainAnyway(modelContext: context)

        XCTAssertEqual(plan.status, .planned)
        XCTAssertNil(plan.skipReason)
        XCTAssertFalse(vm.isRecoveryBenched)
        XCTAssertTrue(vm.canStartWorkout)
        XCTAssertTrue(vm.startWorkout())
        vm.resetState()
    }

    func testTrainAnywayLeavesAUserSkipAlone() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedBenchedPlan(context: context, reason: .userSkipped)
        vm.todayPlan = plan

        vm.trainAnyway(modelContext: context)

        XCTAssertEqual(plan.status, .skipped)
        XCTAssertEqual(plan.skipReason, .userSkipped)
        XCTAssertFalse(vm.isRecoveryBenched)
    }

    func testDashboardShowsABenchedDayAsRest() throws {
        let context = try makeContext()
        let benched = seedBenchedPlan(context: context, reason: .floorForced)
        XCTAssertEqual(DashboardViewModel.dashboardWorkoutStatus(for: benched), .restDay)
        benched.skipReason = .userSkipped
        XCTAssertEqual(DashboardViewModel.dashboardWorkoutStatus(for: benched), .none)
    }

    // MARK: - Pain skip / reduce really change the session

    func testPainSkippedExerciseHasNoWorkLeft() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2, 2])
        let first = plan.orderedExercises[0]
        XCTAssertEqual(vm.firstUncompletedSetIndex(in: first), 0)
        first.painSkipped = true
        XCTAssertNil(vm.firstUncompletedSetIndex(in: first))
    }

    func testPainSkippingTheCurrentExerciseMovesOn() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3, 2])
        start(vm, plan: plan)
        let report = PainReport(bodyArea: .shoulder, severity: 5)
        context.insert(report)

        vm.skipExerciseDueToPain(report, plannedExercise: plan.orderedExercises[0], modelContext: context)

        assertSetActive(vm, exercise: 1, set: 0)
        vm.resetState()
    }

    func testCrashResumeWalksPastAPainSkippedExercise() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2, 2])
        plan.orderedExercises[0].painSkipped = true
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.resumeFromCrash()

        assertSetActive(vm, exercise: 1, set: 0)
        vm.resetState()
    }

    func testWatchNeitherShowsNorLogsAPainSkippedExercise() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2, 2])
        plan.orderedExercises[0].painSkipped = true
        vm.todayPlan = plan

        let names = vm.watchWorkoutPayload()?.exercises.map(\.name) ?? []
        XCTAssertFalse(names.contains("Bench Press"))
        XCTAssertTrue(names.contains("Barbell Row"))
        XCTAssertFalse(
            vm.applyWatchSetLog(exerciseName: "Bench Press", reps: 8, weightKg: 80, modelContext: context),
            "A wrist log can't complete a set on an exercise skipped for pain"
        )
        XCTAssertFalse(plan.orderedExercises[0].orderedSets.contains(where: \.completed))
    }

    func testMildPainPrefillsTheReducedWeight() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [3])
        start(vm, plan: plan)
        let sets = plan.orderedExercises[0].orderedSets
        sets[0].completed = true
        sets[0].actualReps = 8
        sets[0].actualWeight = 80
        vm.currentSetIndex = 1
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 1))

        vm.filePainReport(
            plannedExercise: plan.orderedExercises[0], bodyArea: .knee, severity: 2, modelContext: context
        )

        let reduced = try XCTUnwrap(sets[1].targetWeight)
        XCTAssertLessThan(reduced, 80)
        XCTAssertEqual(vm.stickyWeight, reduced, "Must not carry the pre-report 80 kg")
        vm.resetState()
    }

    // MARK: - PR: one row + one toast per lift per session

    func testBetterSetLaterInTheSessionUpgradesTheSameRecord() throws {
        let context = try makeContext()
        let vm = TrainingViewModel(trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: healthKit)
        let plan = seedPlan(context: context, setCounts: [3], targetWeight: 100)
        let bench = try XCTUnwrap(plan.orderedExercises[0].exercise)
        context.insert(ExerciseHistory(
            date: Date().addingTimeInterval(-7 * 86400),
            estimated1RM: StrengthStandards.epleyE1RM(weight: 80, reps: 5),
            bestSetWeight: 80, bestSetReps: 5, workoutPlanID: UUID(), exercise: bench
        ))
        start(vm, plan: plan)

        vm.logSet(weight: 100, reps: 5, modelContext: context)
        XCTAssertEqual(vm.detectedPRs.count, 1, "First set past the old best is a record")
        let firstValue = try XCTUnwrap(vm.detectedPRs.first?.value)

        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 1))
        vm.currentSetIndex = 1
        vm.logSet(weight: 105, reps: 5, modelContext: context)

        let planID = plan.id
        let rows = try context.fetch(FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.workoutPlanID == planID }
        ))
        XCTAssertEqual(vm.detectedPRs.count, 1, "Still one toast/summary line for the lift")
        XCTAssertEqual(rows.filter { $0.type == .oneRepMax }.count, 1, "Upgraded in place, not a second row")
        XCTAssertGreaterThan(try XCTUnwrap(vm.detectedPRs.first?.value), firstValue)
        vm.resetState()
    }

    func testFirstSessionOfALiftHasNoRecords() throws {
        let context = try makeContext()
        let vm = TrainingViewModel(trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: healthKit)
        let plan = seedPlan(context: context, setCounts: [2], targetWeight: 100)
        start(vm, plan: plan)

        vm.logSet(weight: 100, reps: 5, modelContext: context)

        XCTAssertTrue(vm.detectedPRs.isEmpty, "Day one is the baseline")
        vm.resetState()
    }

    // MARK: - 5. Watch payloads

    func testWatchSetWithoutWeightUsesPrescriptionNotZero() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2])
        vm.todayPlan = plan // no live session → direct path

        XCTAssertTrue(vm.applyWatchSetLog(exerciseName: "Bench Press", reps: 8, weightKg: nil, modelContext: context))

        XCTAssertEqual(plan.orderedExercises[0].orderedSets[0].actualWeight, 80)
    }

    func testWatchSetWithNoUsableWeightIsRefusedForLoadedLifts() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2], targetWeight: nil)
        vm.todayPlan = plan

        XCTAssertFalse(vm.applyWatchSetLog(exerciseName: "Bench Press", reps: 8, weightKg: nil, modelContext: context))
        XCTAssertFalse(plan.orderedExercises[0].orderedSets[0].completed, "Never log a barbell lift at 0 kg")
    }

    func testWatchSetWithoutWeightOnBodyweightMoveLogsZero() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [2], equipment: .bodyweight, targetWeight: nil)
        vm.todayPlan = plan

        XCTAssertTrue(vm.applyWatchSetLog(exerciseName: "Bench Press", reps: 10, weightKg: nil, modelContext: context))
    }

    // MARK: - 6. Discard leaves nothing behind

    private func seedLoggedSessionWithPR(vm: TrainingViewModel, context: ModelContext) -> WorkoutPlan {
        let plan = seedPlan(context: context, setCounts: [2])
        start(vm, plan: plan)
        vm.logSet(weight: 80, reps: 8, addedLoadKg: 10, leftReps: 8, rightReps: 7, modelContext: context)
        let exercise = plan.orderedExercises[0].exercise
        context.insert(PersonalRecord(type: .oneRepMax, value: 100, date: Date(), workoutPlanID: plan.id, exercise: exercise))
        // A PR from an UNRELATED session must survive.
        context.insert(PersonalRecord(type: .oneRepMax, value: 90, date: Date(), workoutPlanID: UUID(), exercise: exercise))
        try? context.save()
        return plan
    }

    private func assertRolledBack(_ plan: WorkoutPlan, context: ModelContext, file: StaticString = #filePath, line: UInt = #line) throws {
        let set = plan.orderedExercises[0].orderedSets[0]
        XCTAssertFalse(set.completed, file: file, line: line)
        XCTAssertNil(set.addedLoadKg, file: file, line: line)
        XCTAssertNil(set.actualRepsLeft, file: file, line: line)
        XCTAssertNil(set.actualRepsRight, file: file, line: line)
        let prs = try context.fetch(FetchDescriptor<PersonalRecord>())
        XCTAssertFalse(prs.contains { $0.workoutPlanID == plan.id }, "Discarded session's PR is gone", file: file, line: line)
        XCTAssertEqual(prs.count, 1, "Other sessions' PRs are untouched", file: file, line: line)
    }

    func testDiscardResetsAddedLoadSplitRepsAndPRs() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedLoggedSessionWithPR(vm: vm, context: context)

        vm.discardActiveWorkout(modelContext: context)

        try assertRolledBack(plan, context: context)
        XCTAssertEqual(plan.status, .planned)
    }

    func testDiscardCrashedWorkoutRollsBackLoggedSetsAndPRs() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedLoggedSessionWithPR(vm: vm, context: context)
        vm.sessionState = .crashedRecovery

        vm.discardCrashedWorkout(modelContext: context)

        try assertRolledBack(plan, context: context)
        XCTAssertEqual(plan.status, .planned, "A discarded crash leaves the day open to redo")
        XCTAssertEqual(vm.sessionState, .discarded)
    }

    // MARK: - 8. Delayed inter-exercise hop can't overwrite a newer state

    func testDelayedNextExerciseHopDoesNotOverwriteDiscard() async throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [1, 1])
        start(vm, plan: plan)
        plan.orderedExercises[0].orderedSets[0].completed = true
        vm.pendingRestAction = .nextExercise

        vm.advanceAfterRest()
        guard case .exercise(.betweenExercises) = vm.sessionState else {
            return XCTFail("expected betweenExercises, got \(vm.sessionState)")
        }
        vm.sessionState = .discarded // user discards inside the 300 ms window
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(vm.sessionState, .discarded)
    }

    func testNextExerciseHopStillLandsOnNextExercise() async throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [1, 2])
        start(vm, plan: plan)
        plan.orderedExercises[0].orderedSets[0].completed = true
        vm.pendingRestAction = .nextExercise

        vm.advanceAfterRest()
        try await Task.sleep(for: .milliseconds(600))

        assertSetActive(vm, exercise: 1, set: 0)
        vm.resetState()
    }

    // MARK: - 10. Drop set bases on the entered weight

    func testDropSetOnUnloggedSetUsesEnteredWeight() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context, setCounts: [1]) // target 80
        start(vm, plan: plan)

        vm.addDropSet(enteredWeightKg: 100, modelContext: context)

        let drop = plan.orderedExercises[0].orderedSets[1]
        XCTAssertEqual(drop.targetWeight, 80, "100 kg entered × 0.8, not 80 × 0.8 = 64")
        vm.resetState()
    }
}
