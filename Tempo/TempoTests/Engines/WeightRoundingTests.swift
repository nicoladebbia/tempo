//
// WeightRoundingTests.swift
// Tempo
//
// Loadable-weight snapping — pins the fix for "88 lbs bench" / "27 lbs
// pushdown": prescriptions snap to weights that physically exist in the
// USER'S display unit (barbell plate lattice with a 45 lb bar floor,
// 5 lb stack pins, kg lattices for kg gyms), stored back as kg. Also pins
// the on-load re-snap of legacy plans: uncompleted targets normalize,
// logged actuals never move.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WeightRoundingTests: XCTestCase {
    // MARK: - loadableKg

    func testBarbellLbsSnapsToFivePoundLattice() {
        // The paid case: 40 kg → 88.2 lbs → snaps to 90 lbs.
        let kg = WeightConverter.loadableKg(40, equipment: .barbell, unit: .lbs)
        XCTAssertEqual(WeightConverter.toLbs(kg), 90, accuracy: 0.01)
    }

    func testBarbellLbsFloorsAtTheBar() {
        // 10 kg (22 lbs) is less than an empty US bar → prescribe the bar (45).
        let kg = WeightConverter.loadableKg(10, equipment: .barbell, unit: .lbs)
        XCTAssertEqual(WeightConverter.toLbs(kg), 45, accuracy: 0.01)
    }

    func testMachineLbsSnapsToStackPins() {
        // 12.2 kg → 26.9 lbs → the pin goes at 25.
        let kg = WeightConverter.loadableKg(12.2, equipment: .cable, unit: .lbs)
        XCTAssertEqual(WeightConverter.toLbs(kg), 25, accuracy: 0.01)
    }

    func testKgModeKeepsKgLattices() {
        XCTAssertEqual(WeightConverter.loadableKg(41, equipment: .barbell, unit: .kg), 40)
        XCTAssertEqual(WeightConverter.loadableKg(41, equipment: .barbell, unit: .kg),
                       WeightConverter.loadableKg(40, equipment: .barbell, unit: .kg))
        XCTAssertEqual(WeightConverter.loadableKg(22, equipment: .machine, unit: .kg), 20,
                       "kg stacks pin in 5s")
        XCTAssertEqual(WeightConverter.loadableKg(10, equipment: .barbell, unit: .kg), 20,
                       "kg bar floor")
    }

    func testBodyweightEquipmentPassesThrough() {
        XCTAssertEqual(WeightConverter.loadableKg(77.3, equipment: .bodyweight, unit: .lbs), 77.3)
        XCTAssertEqual(WeightConverter.loadableKg(80.1, equipment: .pullUpBar, unit: .lbs), 80.1)
    }

    func testNeverSnapsToZeroForLoadableEquipment() {
        let kg = WeightConverter.loadableKg(0.5, equipment: .dumbbell, unit: .lbs)
        XCTAssertEqual(WeightConverter.toLbs(kg), 5, accuracy: 0.01,
                       "Smallest dumbbell, never 0")
    }

    // MARK: - On-load re-snap of legacy plans

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            UserSettings.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func testSnapNormalizesUncompletedTargetsOnlyInLbsMode() throws {
        let context = try makeContext()
        let settings = UserSettings()
        settings.weightUnit = .lbs
        context.insert(settings)

        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        let logged = PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 40,
                                actualReps: 8, actualWeight: 40, completed: true,
                                plannedExercise: slot)
        let open = PlannedSet(setNumber: 2, targetReps: 8, targetWeight: 40,
                              plannedExercise: slot)
        slot.sets = [logged, open]
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        vm.snapPrescribedWeights(for: plan, modelContext: context)

        XCTAssertEqual(WeightConverter.toLbs(open.targetWeight ?? 0), 90, accuracy: 0.01,
                       "Open target re-snaps to the lbs lattice")
        XCTAssertEqual(logged.targetWeight, 40, "Logged set is history — untouched")
        XCTAssertEqual(logged.actualWeight, 40)

        // Idempotent: snapping again changes nothing.
        let once = open.targetWeight
        vm.snapPrescribedWeights(for: plan, modelContext: context)
        XCTAssertEqual(open.targetWeight, once)
    }

    func testSnapSkipsCompletedPlans() throws {
        let context = try makeContext()
        let settings = UserSettings()
        settings.weightUnit = .lbs
        context.insert(settings)

        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.status = .completed
        context.insert(plan)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        let set = PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 40, plannedExercise: slot)
        slot.sets = [set]
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        vm.snapPrescribedWeights(for: plan, modelContext: context)
        XCTAssertEqual(set.targetWeight, 40, "Completed plans are archives — never rewritten")
    }
}
