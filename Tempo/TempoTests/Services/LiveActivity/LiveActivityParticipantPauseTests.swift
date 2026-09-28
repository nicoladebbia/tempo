//
// LiveActivityParticipantPauseTests.swift
// Tempo
//
// Code-review finding, 2026-09 — `hasActiveLiveSession` on both
// `TrainingViewModel` and `AccountabilityViewModel` used to alias the
// existing `sessionState.isActive` / `focusState.isActive`, which reads
// `false` while `.paused`. Since `LiveActivityCoordinator.end(_:)` only
// resumes a suspended participant whose `hasActiveLiveSession` reads true,
// a session paused at the exact moment a higher-priority activity suspended
// it could never get its Live Activity back — not even after being resumed,
// since `syncLiveActivity()`/`syncFocusTimerLiveSurfaces()` only ever call
// the coordinator's `update` (a no-op once `current` is nil), never `start`.
// Pins the fix: `hasActiveLiveSession` stays true through `.paused` for both.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class LiveActivityParticipantPauseTests: XCTestCase {
    // MARK: - TrainingViewModel (gym workout)

    private func makeTrainingContext() throws -> ModelContext {
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

    func testTrainingViewModelReportsActiveLiveSessionWhilePaused() throws {
        let context = try makeTrainingContext()
        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        let plan = WorkoutPlan(date: Date(), type: .push)
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
        slot.sets = [PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 80, plannedExercise: slot)]
        try context.save()

        vm.todayPlan = plan
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
        XCTAssertTrue(vm.hasActiveLiveSession, "sanity: an active session reports alive")

        vm.pause()
        guard case .paused = vm.sessionState else {
            XCTFail("pause() should move an active session to .paused")
            return
        }
        XCTAssertTrue(
            vm.hasActiveLiveSession,
            "a paused workout must still report an active live session, or a suspended Activity can never resume"
        )
    }

    // MARK: - AccountabilityViewModel (focus timer)

    func testAccountabilityViewModelReportsActiveLiveSessionWhilePaused() throws {
        let schema = Schema([DailyAccountability.self, StudySession.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let accountability = DailyAccountability(date: Date())
        context.insert(accountability)
        try context.save()

        let vm = AccountabilityViewModel()
        vm.accountability = accountability
        vm.configureFocusTimer(duration: 25 * 60)
        vm.startFocusSession(modelContext: context)
        XCTAssertTrue(vm.hasActiveLiveSession, "sanity: a running focus session reports alive")

        vm.pauseFocus()
        guard case .paused = vm.focusState else {
            XCTFail("pauseFocus() should move an active session to .paused")
            return
        }
        XCTAssertTrue(
            vm.hasActiveLiveSession,
            "a paused focus session must still report an active live session, or a suspended Activity can never resume"
        )
    }
}
