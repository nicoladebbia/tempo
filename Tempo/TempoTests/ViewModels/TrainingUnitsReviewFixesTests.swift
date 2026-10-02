//
// TrainingUnitsReviewFixesTests.swift
// Tempo
//
// Review fixes on the training-units branch: bodyweight PR keying (phone and
// watch agree), one PR row per lift per session, idempotent crash recovery,
// the pain flag surviving a discard, and 1RM seeding from the latest value.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainingUnitsReviewFixesTests: XCTestCase {
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
    }

    private func lift(_ equipment: Equipment, name: String = "Pull-Up") -> Exercise {
        let exercise = Exercise(
            name: name, muscleGroup: .back, equipment: equipment,
            movementPattern: .verticalPull, isCompound: true
        )
        context.insert(exercise)
        return exercise
    }

    private func addHistory(
        _ exercise: Exercise, weight: Double?, added: Double? = nil, reps: Int, e1RM: Double? = nil
    ) {
        context.insert(ExerciseHistory(
            date: Date().addingTimeInterval(-7 * 86400), estimated1RM: e1RM,
            bestSetWeight: weight, bestSetReps: reps, bestSetAddedLoadKg: added,
            workoutPlanID: UUID(), exercise: exercise
        ))
    }

    private func plan(for exercise: Exercise, sets: Int = 3) -> (WorkoutPlan, PlannedExercise) {
        let plan = WorkoutPlan(date: Date(), type: .pull)
        plan.status = .inProgress
        plan.startedAt = Date().addingTimeInterval(-600)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        slot.sets = (1 ... sets).map { PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 80, plannedExercise: slot) }
        try? context.save()
        return (plan, slot)
    }

    // MARK: 1 + 6 — bodyweight PR keying

    func testBodyweightEffectiveLoadLoggedByPhoneStillGetsMostReps() throws {
        let vm = makeVM()
        let pullUp = lift(.pullUpBar)
        addHistory(pullUp, weight: 80, reps: 10) // legacy phone row: effective load
        let (plan, _) = plan(for: pullUp)
        // Phone logs bodyweight 82 kg effective, +0 added, 12 reps.
        let outcome = vm.recordPersonalRecordIfAny(
            exercise: pullUp, weight: 82, reps: 12, rir: 0, addedLoadKg: 0, plan: plan, modelContext: context
        )
        XCTAssertEqual(outcome, .new)
        XCTAssertEqual(vm.detectedPRs.first?.type, .mostReps)
    }

    func testBodyweightGainAloneIsNotAHeaviestWeightPR() {
        let vm = makeVM()
        let pullUp = lift(.bodyweight)
        addHistory(pullUp, weight: 80, reps: 10)
        let (plan, _) = plan(for: pullUp)
        let outcome = vm.recordPersonalRecordIfAny(
            exercise: pullUp, weight: 85, reps: 8, rir: 0, addedLoadKg: 0, plan: plan, modelContext: context
        )
        XCTAssertEqual(outcome, .none, "Gaining 5 kg of bodyweight is not a record")
    }

    func testTwentyRepBodyweightSetCanPR() {
        let vm = makeVM()
        let pushUp = lift(.bodyweight, name: "Push-Up")
        addHistory(pushUp, weight: 80, reps: 15)
        let (plan, _) = plan(for: pushUp)
        XCTAssertEqual(
            vm.recordPersonalRecordIfAny(
                exercise: pushUp, weight: 80, reps: 20, rir: 0, addedLoadKg: 0, plan: plan, modelContext: context
            ),
            .new
        )
    }

    func testWeightedPullUpKeysOnAddedLoad() throws {
        let engine = TrainingEngine()
        let dip = lift(.bodyweight, name: "Dip")
        addHistory(dip, weight: 90, added: 10, reps: 8)
        // Added 15 kg beats the 10 kg row no matter the bodyweight.
        let pr = try XCTUnwrap(engine.detectPersonalRecord(exercise: dip, weight: 15, reps: 8, workoutPlanID: UUID()))
        XCTAssertEqual(pr.contextWeightKg, 15)
        XCTAssertNil(engine.detectPersonalRecord(exercise: dip, weight: 10, reps: 8, workoutPlanID: UUID()))
    }

    func testWatchAndPhoneRowsShareOneBaseline() {
        let vm = makeVM()
        let pullUp = lift(.pullUpBar)
        addHistory(pullUp, weight: 0, reps: 10) // watch-written row
        let (plan, _) = plan(for: pullUp)
        // Phone logs 11 reps at 80 kg effective, +0 added: beats the watch row's 10.
        XCTAssertEqual(
            vm.recordPersonalRecordIfAny(
                exercise: pullUp, weight: 80, reps: 11, rir: 0, addedLoadKg: 0, plan: plan, modelContext: context
            ),
            .new
        )
    }

    func testLoadedLiftAtZeroKgIsNeverAMostRepsRecord() {
        let engine = TrainingEngine()
        let bench = lift(.barbell, name: "Bench")
        addHistory(bench, weight: 60, reps: 5)
        XCTAssertNil(engine.detectPersonalRecord(exercise: bench, weight: 0, reps: 30, workoutPlanID: UUID()))
    }

    func testBodyweightLoadFormatting() {
        XCTAssertEqual(WeightFormat.bodyweightLoad(addedKg: nil, unit: .kg), "BW")
        XCTAssertEqual(WeightFormat.bodyweightLoad(addedKg: 0, unit: .kg), "BW")
        XCTAssertEqual(WeightFormat.bodyweightLoad(addedKg: 10, unit: .kg), "BW + 10 kg")
        XCTAssertEqual(WeightFormat.bodyweightLoad(addedKg: -15, unit: .kg), "BW − 15 kg")
        let rows = [
            ExerciseHistory(date: Date(), bestSetWeight: 90, bestSetReps: 8, bestSetAddedLoadKg: 10),
            ExerciseHistory(date: Date(), bestSetWeight: 80, bestSetReps: 12),
        ]
        let best = ExerciseBestSet.pick(from: rows, bodyweight: true)
        XCTAssertEqual(best?.addedLoadKg, 10)
        XCTAssertEqual(
            WeightFormat.setLoad(kg: 80, addedKg: nil, bodyweight: true, unit: .kg), "BW",
            "A bodyweight row never reads as its effective 80 kg"
        )
    }

    // MARK: 3 — one PR per lift per session

    func testSecondRecordTypeUpgradesTheSameRowInPlace() throws {
        let vm = makeVM()
        let bench = lift(.barbell, name: "Bench")
        addHistory(bench, weight: 60, reps: 5, e1RM: StrengthStandards.epleyE1RM(weight: 60, reps: 5))
        let (plan, _) = plan(for: bench)
        XCTAssertEqual(
            vm.recordPersonalRecordIfAny(
                exercise: bench, weight: 100, reps: 5, rir: 0, plan: plan, modelContext: context
            ),
            .new
        )
        // 14 reps skips the e1RM rule, still the heaviest... a lighter-but-heavier-than-baseline set
        let second = vm.recordPersonalRecordIfAny(
            exercise: bench, weight: 110, reps: 14, rir: 0, plan: plan, modelContext: context
        )
        XCTAssertEqual(second, .upgraded)
        try context.save()
        let rows = (bench.personalRecords ?? []).filter { $0.workoutPlanID == plan.id }
        XCTAssertEqual(rows.count, 1, "At most one PR row per lift per session")
        XCTAssertEqual(vm.detectedPRs.count, 1)
        XCTAssertEqual(vm.detectedPRs.first?.id, rows.first?.id)
    }

    // MARK: 2 — idempotent crash recovery

    func testCrashRecoveryIsIdempotentWithoutANewSet() throws {
        let now = Date()
        let plan = WorkoutPlan(date: now, type: .push)
        plan.startedAt = now.addingTimeInterval(-3 * 3600)
        let ex = PlannedExercise(order: 0, workoutPlan: plan)
        let set = PlannedSet(setNumber: 1, targetReps: 5, completed: true, plannedExercise: ex)
        set.completedAt = now.addingTimeInterval(-3 * 3600 + 1200)
        ex.sets = [set]
        plan.exercises = [ex]
        plan.pausedSeconds = TrainingViewModel.recoveredPauseSeconds(for: plan, now: now)
        plan.crashRecoveredAt = now
        let afterFirst = plan.pausedSeconds
        // Killed again 5 minutes later, no new set.
        let later = now.addingTimeInterval(300)
        XCTAssertEqual(TrainingViewModel.recoveredPauseSeconds(for: plan, now: later), afterFirst, accuracy: 0.5)
        XCTAssertGreaterThan(later.timeIntervalSince(plan.startedAt ?? later) - afterFirst, 0)
    }

    func testPauseAfterTheLastSetDoesNotShrinkTheTrainingAllowance() {
        let now = Date()
        let startedAt = now.addingTimeInterval(-3600)
        let plan = WorkoutPlan(date: now, type: .push)
        plan.startedAt = startedAt
        let ex = PlannedExercise(order: 0, workoutPlan: plan)
        let set = PlannedSet(setNumber: 1, targetReps: 5, completed: true, plannedExercise: ex)
        set.completedAt = startedAt.addingTimeInterval(1800) // last set 30 min in
        ex.sets = [set]
        plan.exercises = [ex]
        plan.pausedSeconds = 600 // a 10 min pause AFTER the last set
        // Killed 12 min after the last set: only 2 min is beyond the allowance.
        let nowShort = startedAt.addingTimeInterval(1800 + 720)
        XCTAssertEqual(TrainingViewModel.recoveredPauseSeconds(for: plan, now: nowShort), 600 + 120, accuracy: 1)
    }

    // MARK: 5 — pain flag survives the discard

    func testPainEndedEmptySessionKeepsTheHurtingLiftFlagged() {
        let vm = makeVM()
        let bench = lift(.barbell, name: "Bench")
        let (plan, slot) = plan(for: bench)
        vm.todayPlan = plan
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
        let report = PainReport(bodyArea: .shoulder, severity: 9)
        context.insert(report)
        vm.endSessionDueToPain(report, plannedExercise: slot, modelContext: context)
        XCTAssertTrue(slot.painSkipped, "'Train anyway' must not bring the hurting lift back unflagged")
        XCTAssertEqual(plan.status, .skipped)
        vm.resetState()
    }

    // MARK: 4 — seeding uses the latest value

    func testLatestEstimateKeepsThePreviousSemantics() {
        let squat = lift(.barbell, name: "Squat")
        addHistory(squat, weight: 100, reps: 5, e1RM: 150) // a week ago, strong
        context.insert(ExerciseHistory(date: Date(), estimated1RM: 120, bestSetWeight: 90, bestSetReps: 5, exercise: squat))
        XCTAssertEqual(squat.currentEstimated1RM, 150, "Display: strongest of the last 6 weeks")
        XCTAssertEqual(squat.latestEstimated1RM, 120, "Seeding: what he just did")
    }
}
