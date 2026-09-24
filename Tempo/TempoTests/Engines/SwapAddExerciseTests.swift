//
// SwapAddExerciseTests.swift
// Tempo
//
// §2.13 / §2.14 — swap-exercise and add-exercise flows. Pins the invariants:
// a swap keeps the slot but rebuilds the prescription for the new movement,
// refuses once any set is logged (completed work is never re-attributed),
// and cleans up the old movement's unresolved prediction; add appends a fully
// prescribed slot and refuses duplicates. Alternatives are same-muscle-group
// only and exclude movements already in the plan.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SwapAddExerciseTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            ExerciseHistory.self,
            PlannedExercise.self,
            PlannedSet.self,
            PredictionLog.self,
            AdaptiveProfile.self,
            SetFeedback.self,
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

    private func bench() -> Exercise {
        Exercise(
            name: "Barbell Bench Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
    }

    private func cableFly() -> Exercise {
        Exercise(
            name: "Cable Fly",
            muscleGroup: .chest,
            equipment: .cable,
            movementPattern: .isolation,
            isCompound: false
        )
    }

    /// A .planned plan holding one compound slot: 2 warmups + 3 working sets.
    private func seedPlan(
        with exercise: Exercise, context: ModelContext
    ) -> (plan: WorkoutPlan, slot: PlannedExercise) {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        context.insert(exercise)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        var sets: [PlannedSet] = []
        for (i, warm) in [true, true, false, false, false].enumerated() {
            sets.append(PlannedSet(
                setNumber: i + 1, targetReps: 8, targetWeight: warm ? 40 : 80,
                isWarmup: warm, plannedExercise: slot
            ))
        }
        slot.sets = sets
        try? context.save()
        return (plan, slot)
    }

    // MARK: - Swap

    func testSwapReplacesMovementAndRebuildsPrescription() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)

        XCTAssertEqual(slot.exercise?.name, "Cable Fly", "The movement swaps in place")
        let sets = slot.orderedSets
        XCTAssertTrue(
            sets.allSatisfy { !$0.isWarmup },
            "An isolation gets no warmup ramp"
        )
        XCTAssertEqual(sets.count, 3, "The slot's working-set count is preserved")
        XCTAssertEqual(sets.first?.targetReps, 12, "Reps re-prescribe for the new movement")
        XCTAssertEqual(sets.first?.targetWeight, 80, "Weight comes from the engine's prescription")
    }

    /// §8 pain notes — `prescribedSets` (the shared builder swap/add/applyRoutine
    /// all use) must apply the same conservative-note cap `populateExercises`
    /// does. Without it, a recently pain-flagged movement could come back in
    /// HEAVIER than the session that hurt, the moment it's swapped/added/applied
    /// via a routine instead of freshly generated.
    func testSwapAppliesPainNoteConservativeCap() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        let fly = cableFly()
        context.insert(fly)
        // Last logged session for the incoming movement was lighter than the
        // engine's flat 80 kg mock prescription.
        let lastSession = ExerciseHistory(date: Date(), bestSetWeight: 50, exercise: fly)
        context.insert(lastSession)
        let painNote = SetFeedback(exerciseID: fly.id, rpe: 8, note: "sharp shoulder pain on this")
        painNote.userProvidedFeedback = true
        context.insert(painNote)
        try context.save()

        vm.swapExercise(slot, with: fly, modelContext: context)

        XCTAssertEqual(
            slot.orderedSets.first?.targetWeight, 50,
            "A pain-flagged movement is capped at last session's weight, never bumped to the engine's fresh prescription"
        )
    }

    func testSwapRefusedOnceASetIsCompleted() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        slot.orderedSets.last?.completed = true
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)

        XCTAssertEqual(
            slot.exercise?.name,
            "Barbell Bench Press",
            "Logged work pins the movement — no swap after a completed set"
        )
        XCTAssertEqual(slot.orderedSets.count, 5, "Sets untouched")
    }

    func testSwapReplacesUnresolvedPrediction() throws {
        let context = try makeContext()
        let vm = makeVM()
        let old = bench()
        let (plan, slot) = seedPlan(with: old, context: context)
        let stale = PredictionLog(
            exercise: old, exerciseID: old.id, workoutPlanID: plan.id,
            predictedWeight: 80, predictedReps: 8,
            signalUsedRaw: ProgressionReason.standardProgression.rawValue,
            learnedIncrementUsed: nil, baselineWeight: nil
        )
        context.insert(stale)
        try context.save()
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)

        let rows = try context.fetch(FetchDescriptor<PredictionLog>())
        XCTAssertFalse(
            rows.contains { $0.exerciseID == old.id },
            "The swapped-out movement's unresolved prediction is dropped"
        )
        XCTAssertTrue(
            rows.contains { $0.exerciseID == fly.id },
            "The new movement's prescription is logged in its place"
        )
    }

    // MARK: - Add

    func testAddExerciseAppendsWithPrescription() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seedPlan(with: bench(), context: context)
        vm.todayPlan = plan
        let fly = cableFly()
        context.insert(fly)

        vm.addExercise(fly, modelContext: context)

        let slots = plan.orderedExercises
        XCTAssertEqual(slots.count, 2, "The new movement appends to the plan")
        let added = slots.last
        XCTAssertEqual(added?.exercise?.name, "Cable Fly")
        XCTAssertEqual(added?.order, 1, "Appends after the existing slots")
        XCTAssertEqual(added?.orderedSets.count, 3, "Three working sets by default")
        XCTAssertEqual(added?.orderedSets.first?.targetReps, 12)
    }

    func testAddExerciseRefusesDuplicates() throws {
        let context = try makeContext()
        let vm = makeVM()
        let ex = bench()
        let (plan, _) = seedPlan(with: ex, context: context)
        vm.todayPlan = plan

        vm.addExercise(ex, modelContext: context)

        XCTAssertEqual(
            plan.orderedExercises.count,
            1,
            "A movement already in the plan is never added twice"
        )
    }

    // MARK: - Alternatives

    func testSwapAlternativesSameMuscleGroupExcludingPlan() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        let incline = Exercise(
            name: "Incline Dumbbell Press",
            muscleGroup: .chest,
            equipment: .dumbbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        let fly = cableFly()
        let row = Exercise(
            name: "Barbell Row",
            muscleGroup: .back,
            equipment: .barbell,
            movementPattern: .horizontalPull,
            isCompound: true
        )
        [incline, fly, row].forEach { context.insert($0) }
        try context.save()

        let names = vm.swapAlternatives(for: slot, modelContext: context).map(\.name)

        XCTAssertEqual(
            names.first,
            "Incline Dumbbell Press",
            "Same movement pattern ranks first — the closest substitute"
        )
        XCTAssertTrue(names.contains("Cable Fly"), "Same muscle group qualifies")
        XCTAssertFalse(names.contains("Barbell Row"), "Other muscle groups excluded")
        XCTAssertFalse(
            names.contains("Barbell Bench Press"),
            "The movement being swapped is not its own alternative"
        )
    }

    /// §8 pain notes — `swapAlternatives` must never offer a movement the user
    /// recently flagged as painful, mirroring the rule `applyPreferredSwaps`
    /// already enforces for the automatic-substitution path.
    func testSwapAlternativesExcludesPainFlaggedCandidate() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        let incline = Exercise(
            name: "Incline Dumbbell Press",
            muscleGroup: .chest,
            equipment: .dumbbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        context.insert(incline)
        try context.save()
        let painNote = SetFeedback(exerciseID: incline.id, rpe: 8, note: "shoulder pain on incline")
        painNote.userProvidedFeedback = true
        context.insert(painNote)
        try context.save()

        let names = vm.swapAlternatives(for: slot, modelContext: context).map(\.name)

        XCTAssertFalse(
            names.contains("Incline Dumbbell Press"),
            "A recently pain-flagged candidate is never offered as a swap target"
        )
    }

    // MARK: - Warmup ramp placement (§2.16)

    func testSecondCompoundGetsSingleFeelSetNotFullRamp() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seedPlan(with: bench(), context: context)
        vm.todayPlan = plan
        let incline = Exercise(
            name: "Incline Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        context.insert(incline)

        vm.addExercise(incline, modelContext: context)

        let slot = try XCTUnwrap(plan.orderedExercises.first { $0.exercise?.name == "Incline Press" })
        let warmups = slot.orderedSets.filter(\.isWarmup)
        XCTAssertEqual(
            warmups.count,
            1,
            "A compound after another compound works warm muscle — one feel set"
        )
        XCTAssertEqual(warmups.first?.targetWeight, 60, "75% of the 80 kg working weight")
    }

    // MARK: - Preferred swaps (§2.13b — the planner learns your machines)

    private func profile(_ context: ModelContext) -> AdaptiveProfile {
        (try? context.fetch(FetchDescriptor<AdaptiveProfile>()))?.first ?? {
            let p = AdaptiveProfile()
            context.insert(p)
            return p
        }()
    }

    func testSwapRemembersPreference() throws {
        let context = try makeContext()
        let vm = makeVM()
        let old = bench()
        let (_, slot) = seedPlan(with: old, context: context)
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)

        XCTAssertEqual(
            profile(context).preferredSwaps[old.id],
            fly.id,
            "A manual swap teaches the planner"
        )
    }

    func testSwapBackForgetsPreference() throws {
        let context = try makeContext()
        let vm = makeVM()
        let old = bench()
        let (_, slot) = seedPlan(with: old, context: context)
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)
        vm.swapExercise(slot, with: old, modelContext: context)

        XCTAssertTrue(
            profile(context).preferredSwaps.isEmpty,
            "Swapping back to the original undoes the preference, never stores a loop"
        )
    }

    func testRepeatSwapChainCollapses() throws {
        let context = try makeContext()
        let vm = makeVM()
        let old = bench()
        let (_, slot) = seedPlan(with: old, context: context)
        let fly = cableFly()
        let press = Exercise(
            name: "Machine Chest Press",
            muscleGroup: .chest,
            equipment: .machine,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        context.insert(fly)
        context.insert(press)

        vm.swapExercise(slot, with: fly, modelContext: context)
        vm.swapExercise(slot, with: press, modelContext: context)

        let prefs = profile(context).preferredSwaps
        XCTAssertEqual(
            prefs,
            [old.id: press.id],
            "X→Y then Y→Z stores the single hop X→Z"
        )
    }

    func testApplyPreferredSwapsSubstitutesInSelection() throws {
        let context = try makeContext()
        let vm = makeVM()
        let cable = Exercise(
            name: "Tricep Pushdown",
            muscleGroup: .triceps,
            equipment: .cable,
            movementPattern: .isolation,
            isCompound: false
        )
        let machine = Exercise(
            name: "Pushdown Machine",
            muscleGroup: .triceps,
            equipment: .machine,
            movementPattern: .isolation,
            isCompound: false
        )
        context.insert(cable)
        context.insert(machine)
        profile(context).preferredSwaps = [cable.id: machine.id]
        try context.save()

        let out = vm.applyPreferredSwaps(
            to: [cable], library: [cable, machine], modelContext: context
        )
        XCTAssertEqual(
            out.map(\.name),
            ["Pushdown Machine"],
            "The planner prescribes the movement the user actually does"
        )

        // Replacement already selected → no duplicate slot, source stays.
        let both = vm.applyPreferredSwaps(
            to: [cable, machine], library: [cable, machine], modelContext: context
        )
        XCTAssertEqual(both.map(\.name), ["Tricep Pushdown", "Pushdown Machine"])
    }

    func testApplyPreferredSwapsSkipsPainFlaggedReplacement() throws {
        let context = try makeContext()
        let vm = makeVM()
        let cable = Exercise(
            name: "Tricep Pushdown",
            muscleGroup: .triceps,
            equipment: .cable,
            movementPattern: .isolation,
            isCompound: false
        )
        let machine = Exercise(
            name: "Pushdown Machine",
            muscleGroup: .triceps,
            equipment: .machine,
            movementPattern: .isolation,
            isCompound: false
        )
        context.insert(cable)
        context.insert(machine)
        profile(context).preferredSwaps = [cable.id: machine.id]
        let feedback = SetFeedback(
            exerciseID: machine.id,
            rpe: 7,
            note: "sharp elbow pain on this machine"
        )
        feedback.userProvidedFeedback = true
        context.insert(feedback)
        try context.save()

        let out = vm.applyPreferredSwaps(
            to: [cable], library: [cable, machine], modelContext: context
        )
        XCTAssertEqual(
            out.map(\.name),
            ["Tricep Pushdown"],
            "Safety wins — a pain-flagged replacement is not auto-prescribed"
        )
    }
}
