//
// EmptyGymPlanBackfillTests.swift
// Tempo
//
// Pins the fix for the 0/0 unstartable workout (device log 2026-07-29:
// advancePastWarmup totalSets=0). The daily coach can flip a non-gym day to a
// gym modality (football → upper, "you've got the headroom, lift") — a row
// that never had exercises. ensureTodayPlanPersisted's keep path must
// backfill any still-planned gym row with no exercises so Start Workout can
// never launch a session where Finish Set and Skip are both dead.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class EmptyGymPlanBackfillTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            ExerciseHistory.self,
            PlannedExercise.self,
            PlannedSet.self,
            PredictionLog.self,
            AdaptiveProfile.self,
            UserSettings.self,
            UserProfile.self,
            BodyComposition.self,
            SetFeedback.self,
            Match.self,
            ActivitySession.self,
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

    /// One upper-body compound in the library so populateExercises has
    /// something to prescribe for an .upper day.
    private func seedLibrary(_ context: ModelContext) {
        let bench = Exercise(name: "Barbell Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush,
                             isCompound: true)
        context.insert(bench)
        try? context.save()
    }

    func testKeptPlannedGymDayWithNoExercisesIsBackfilled() throws {
        // The device case: the coach reshaped football → upper on a row with
        // zero exercises; the row is kept (type matches the template) and must
        // come out startable.
        let context = try makeContext()
        let vm = makeVM()
        seedLibrary(context)
        let today = Calendar.current.startOfDay(for: Date())

        let persisted = WorkoutPlan(date: today, type: .upper) // .planned, NO exercises
        persisted.plannedTypeRaw = WorkoutType.football.rawValue // coach-moved
        context.insert(persisted)
        try context.save()

        let fresh = WorkoutPlan(date: today, type: .upper)
        vm.weekPlans = [fresh]

        let resolved = vm.ensureTodayPlanPersisted(modelContext: context)
        XCTAssertFalse(resolved.plan.orderedExercises.isEmpty,
                       "A kept planned gym day is never returned without exercises")
        XCTAssertGreaterThan(resolved.plan.totalSets, 0,
                             "Backfilled sets exist — Start Workout can't launch 0/0")
    }

    func testKeptPlanWithSetlessExerciseIsRebuilt() throws {
        // §11.13 device case 2: the plan HAS exercises but one carries zero
        // sets — Start Workout froze on it ("Set 1 of 0", dead Finish Set).
        let context = try makeContext()
        let vm = makeVM()
        seedLibrary(context)
        let today = Calendar.current.startOfDay(for: Date())

        let persisted = WorkoutPlan(date: today, type: .upper)
        context.insert(persisted)
        let hollow = PlannedExercise(order: 0, workoutPlan: persisted)
        context.insert(hollow)
        persisted.exercises = [hollow]
        try context.save()

        let fresh = WorkoutPlan(date: today, type: .upper)
        vm.weekPlans = [fresh]

        let resolved = vm.ensureTodayPlanPersisted(modelContext: context)
        XCTAssertFalse(resolved.plan.orderedExercises.isEmpty)
        XCTAssertTrue(
            resolved.plan.orderedExercises.allSatisfy { pe in
                (pe.sets ?? []).contains { !$0.isWarmup }
            },
            "Every exercise on a kept planned gym day carries at least one working set"
        )
    }

    func testSessionRecoversPastAnEmptyExercise() throws {
        // §11.13 runtime self-heal: mid-session, an empty exercise moves the
        // session forward instead of freezing Finish Set.
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .upper)
        context.insert(plan)

        let empty = PlannedExercise(order: 0, workoutPlan: plan)
        let real = PlannedExercise(order: 1, workoutPlan: plan)
        context.insert(empty)
        context.insert(real)
        let set = PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 60, plannedExercise: real)
        context.insert(set)
        real.sets = [set]
        plan.exercises = [empty, real]
        try context.save()

        vm.todayPlan = plan
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))

        // Finish Set on the empty exercise: logSet self-heals to exercise 1.
        vm.logSet(weight: 60, reps: 8, modelContext: context)
        XCTAssertEqual(vm.currentExerciseIndex, 1, "Session jumped past the empty exercise")
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 1, setIndex: 0)))
    }

    func testCompletedEmptyGymDayIsLeftAlone() throws {
        // Sacredness: a completed row (however odd its state) is never mutated.
        let context = try makeContext()
        let vm = makeVM()
        seedLibrary(context)
        let today = Calendar.current.startOfDay(for: Date())

        let done = WorkoutPlan(date: today, type: .upper)
        done.status = .completed
        context.insert(done)
        try context.save()

        let fresh = WorkoutPlan(date: today, type: .upper)
        vm.weekPlans = [fresh]

        let resolved = vm.ensureTodayPlanPersisted(modelContext: context)
        XCTAssertTrue(resolved.plan.orderedExercises.isEmpty,
                      "A completed day is sacred — the backfill never touches it")
    }

    func testKeptPopulatedGymDayIsNotRepopulated() throws {
        // Idempotence: a day that already has its exercises keeps them exactly.
        let context = try makeContext()
        let vm = makeVM()
        seedLibrary(context)
        let today = Calendar.current.startOfDay(for: Date())

        let persisted = WorkoutPlan(date: today, type: .upper)
        context.insert(persisted)
        try context.save()
        vm.populateExercises(for: persisted, modelContext: context)
        let countBefore = persisted.orderedExercises.count
        XCTAssertGreaterThan(countBefore, 0, "Precondition: seeded population worked")

        let fresh = WorkoutPlan(date: today, type: .upper)
        vm.weekPlans = [fresh]

        let resolved = vm.ensureTodayPlanPersisted(modelContext: context)
        XCTAssertEqual(resolved.plan.orderedExercises.count, countBefore,
                       "No duplicate exercises on an already-populated kept day")
    }
}
