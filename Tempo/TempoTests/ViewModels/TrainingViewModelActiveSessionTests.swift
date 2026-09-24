//
// TrainingViewModelActiveSessionTests.swift
// Tempo
//
// Pins the active-workout-session bug fixes: the rest timer surviving a
// pause/call interruption (§2), Finish/Discard behaving correctly in every
// session state including crash recovery (§3), logSet refusing to
// re-complete a set the watch already logged, and applyWatchSetLog routing
// through the SAME logSet path when the phone's own session is live on the
// exact set the watch just completed (§11).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainingViewModelActiveSessionTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            SetFeedback.self,
            PersonalRecord.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    /// One exercise ("Bench Press") with `workingSetCount` un-warmed-up sets.
    private func seedSingleExercisePlan(
        context: ModelContext,
        workingSetCount: Int,
        status: WorkoutStatus = .inProgress
    ) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.status = status
        context.insert(plan)

        let bench = Exercise(
            name: "Bench Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        context.insert(bench)

        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.sets = (1 ... workingSetCount).map {
            PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 80, plannedExercise: slot)
        }
        try? context.save()
        return plan
    }

    // MARK: - §2 — rest timer survives pause / call interruption

    func testPauseDuringRestThenResumeRestartsTheRestTimer() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 2)
        vm.todayPlan = plan
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))

        // Complete set 1 of 2 — not the last set, so this lands in .resting
        // with the real rest timer armed.
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        guard case .exercise(.resting) = vm.sessionState else {
            XCTFail("Expected to land in .resting after a non-final set")
            return
        }
        XCTAssertNotNil(vm.restTimerTask, "Sanity: the rest timer is actually running before we pause")

        vm.pause()
        guard case .paused = vm.sessionState else {
            XCTFail("pause() should move an active session to .paused")
            return
        }
        XCTAssertNil(vm.restTimerTask, "pause() tears the timer down")

        vm.resume()

        guard case .exercise(.resting) = vm.sessionState else {
            XCTFail("resume() should come back into .resting, not skip past it")
            return
        }
        XCTAssertNotNil(vm.restTimerTask, "Without the fix, resume() never restarts the rest timer")
        XCTAssertGreaterThan(vm.restTimerRemaining, 0, "RestTimerView would show 0:00 forever without the fix")
        XCTAssertNotNil(vm.restEndDate)
    }

    func testCallInterruptionDuringRestThenEndingCallRestartsTheRestTimer() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 2)
        vm.todayPlan = plan
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))

        vm.logSet(weight: 80, reps: 8, modelContext: context)
        guard case .exercise(.resting) = vm.sessionState else {
            XCTFail("Expected to land in .resting after a non-final set")
            return
        }

        vm.handleCallChange(callEnded: false)
        guard case .interruptedCall = vm.sessionState else {
            XCTFail("A live call should park the session in .interruptedCall")
            return
        }
        XCTAssertNil(vm.restTimerTask)

        vm.handleCallChange(callEnded: true)

        guard case .exercise(.resting) = vm.sessionState else {
            XCTFail("Hanging up should restore .resting, not skip past it")
            return
        }
        XCTAssertNotNil(vm.restTimerTask, "Without the fix, the rest timer never restarts after a call")
        XCTAssertGreaterThan(vm.restTimerRemaining, 0)
    }

    // MARK: - §3 — discard/finish valid in every active/crash/call state

    func testDiscardActiveWorkoutWorksFromCrashedRecovery() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 1, status: .inProgress)
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.discardActiveWorkout(modelContext: context)

        XCTAssertEqual(plan.status, .planned, "Without the fix this silently no-ops and status stays .inProgress")
        XCTAssertEqual(vm.sessionState, .discarded)
    }

    func testDiscardActiveWorkoutWorksFromInterruptedCall() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 1, status: .inProgress)
        vm.todayPlan = plan
        vm.sessionState = .interruptedCall(previousState: .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))

        vm.discardActiveWorkout(modelContext: context)

        XCTAssertEqual(plan.status, .planned, "Without the fix this silently no-ops")
        XCTAssertEqual(vm.sessionState, .discarded)
    }

    func testDiscardActiveWorkoutDeletesOrphanedSetFeedback() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 1, status: .inProgress)
        let set = plan.orderedExercises[0].orderedSets[0]
        set.completed = true
        set.actualWeight = 80
        set.actualReps = 8
        let feedback = SetFeedback(plannedSet: set, rpe: 7)
        context.insert(feedback)
        try context.save()
        vm.todayPlan = plan
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))

        vm.discardActiveWorkout(modelContext: context)

        let remaining = try context.fetch(FetchDescriptor<SetFeedback>())
        XCTAssertTrue(remaining.isEmpty, "A rolled-back set's feedback must not linger and shadow the redo")
    }

    func testFinishWorkoutWithZeroCompletedSetsBehavesLikeDiscard() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 3, status: .inProgress)
        vm.todayPlan = plan
        vm.sessionState = .warmup(exerciseIndex: 0, warmupSetIndex: 0)

        vm.finishWorkout(modelContext: context)

        XCTAssertEqual(
            plan.status, .planned,
            "Without the fix the plan is wedged .inProgress forever (persistCompletion's zero-sets guard never reverts it)"
        )
        XCTAssertEqual(vm.sessionState, .discarded, "Zero logged sets must not reach .summary")
    }

    func testFinishWorkoutIsUnavailableFromCrashedRecovery() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 1, status: .inProgress)
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.finishWorkout(modelContext: context)

        XCTAssertEqual(vm.sessionState, .crashedRecovery, "finishWorkout must no-op from crashedRecovery")
        XCTAssertEqual(plan.status, .inProgress)
    }

    // MARK: - §3 — .cooldown dead-end routes to .summary instead

    func testAdvancePastWarmupWithZeroExercisesGoesToSummary() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan
        vm.sessionState = .warmup(exerciseIndex: 0, warmupSetIndex: 0)

        vm.advancePastWarmup()

        XCTAssertEqual(vm.sessionState, .summary, "A plan with no exercises must not land on the blank .cooldown screen")
    }

    func testResumeFromCrashWithEverythingAlreadyCompleteGoesToSummary() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 1, status: .inProgress)
        let set = plan.orderedExercises[0].orderedSets[0]
        set.completed = true
        set.actualWeight = 80
        set.actualReps = 8
        plan.startedAt = Date().addingTimeInterval(-600)
        try context.save()
        vm.todayPlan = plan
        vm.sessionState = .crashedRecovery

        vm.resumeFromCrash()

        XCTAssertEqual(vm.sessionState, .summary, "Nothing left to resume must not land on the blank .cooldown screen")
    }

    // MARK: - §11 — logSet refuses to re-complete an already-completed set

    func testLogSetRefusesToOverwriteAnAlreadyCompletedSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 2)
        let set = plan.orderedExercises[0].orderedSets[0]
        // Simulate the watch having already completed this exact set.
        set.completed = true
        set.actualWeight = 82.5
        set.actualReps = 6
        set.completedAt = Date()
        try context.save()

        vm.todayPlan = plan
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))

        vm.logSet(weight: 999, reps: 99, modelContext: context)

        XCTAssertEqual(set.actualWeight, 82.5, "A stale phone tap must never overwrite the watch's real numbers")
        XCTAssertEqual(set.actualReps, 6)
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)), "Cursor must not advance on a no-op")
    }

    // MARK: - §11 — applyWatchSetLog routes through logSet on a live match

    func testApplyWatchSetLogRoutesThroughLogSetWhenPhoneIsLiveOnTheExactSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 2)
        vm.todayPlan = plan
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))

        let applied = vm.applyWatchSetLog(exerciseName: "Bench Press", reps: 8, weightKg: 80, modelContext: context)
        XCTAssertTrue(applied)

        let set = plan.orderedExercises[0].orderedSets[0]
        XCTAssertTrue(set.completed)
        XCTAssertEqual(set.actualWeight, 80)
        XCTAssertEqual(set.actualReps, 8)
        // Routed through the real logSet — not the second (not-last) set, so
        // it must have moved on to resting rather than staying parked on the
        // now-completed set.
        guard case .exercise(.resting) = vm.sessionState else {
            XCTFail("applyWatchSetLog should route through logSet's full flow (rest timer included) when live")
            return
        }

        // A stale phone tap landing right after must not overwrite it — this
        // is logSet's own re-completion guard closing the loop end-to-end.
        vm.logSet(weight: 999, reps: 99, modelContext: context)
        XCTAssertEqual(set.actualWeight, 80, "Phone must not overwrite the watch-logged set")
        XCTAssertEqual(set.actualReps, 8)
    }

    func testApplyWatchSetLogFallsBackToDirectCompletionWhenPhoneIsNotLive() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedSingleExercisePlan(context: context, workingSetCount: 2, status: .planned)
        vm.todayPlan = plan
        // Phone has no live session at all.
        XCTAssertFalse(vm.sessionState.isActive)

        let applied = vm.applyWatchSetLog(exerciseName: "Bench Press", reps: 8, weightKg: 80, modelContext: context)
        XCTAssertTrue(applied)
        XCTAssertEqual(plan.status, .inProgress, "First wrist log still opens the session off-cursor")
        let set = plan.orderedExercises[0].orderedSets[0]
        XCTAssertTrue(set.completed)
        XCTAssertEqual(set.actualWeight, 80)
    }

    // MARK: - §11 — watch-started session is adopted as live, not crashed

    func testAdoptWatchStartedSessionEntersWarmupLiveNotCrashed() {
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.status = .inProgress
        plan.startedAt = Date()

        vm.adoptWatchStartedSession(plan)

        guard case .warmup = vm.sessionState else {
            XCTFail("A watch-started gym session should enter LIVE warmup, not sit in .crashedRecovery")
            return
        }
    }

    func testHasNoCompletedSetsDistinguishesWatchStartFromRealCrash() throws {
        let context = try makeContext()
        let vm = makeVM()
        let freshPlan = seedSingleExercisePlan(context: context, workingSetCount: 1, status: .inProgress)
        XCTAssertTrue(
            vm.hasNoCompletedSets(freshPlan),
            "A plan the watch just flipped to .inProgress has nothing logged yet"
        )

        freshPlan.orderedExercises[0].orderedSets[0].completed = true
        XCTAssertFalse(
            vm.hasNoCompletedSets(freshPlan),
            "Once anything is logged this must read as a REAL crash, not a watch start"
        )
    }
}
