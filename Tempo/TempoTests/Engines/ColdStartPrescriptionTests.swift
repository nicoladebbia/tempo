//
// ColdStartPrescriptionTests.swift
// Tempo
//
// QA bug C — a brand-new user (no bodyweight on file) was prescribed
// "Pull-Up 3 x 8 @ 7kg" and "Barbell Row 4 x 8 @ 20kg + 2 warmup" where both
// warmups were also 20 kg. Pins: bodyweight lifts cold-start at plain
// bodyweight, ramp sets are never identical to the working weight, and a
// deload never scales bodyweight itself.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ColdStartPrescriptionTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    private func pullPlan(with exercises: [Exercise], bodyweightKg: Double?, context: ModelContext) -> WorkoutPlan {
        context.insert(UserSettings())
        if let bodyweightKg {
            let profile = UserProfile(appleID: "a", username: "u", displayName: "Athlete")
            profile.weightKg = bodyweightKg
            context.insert(profile)
        }
        exercises.forEach(context.insert)
        let plan = WorkoutPlan(date: Date(), type: .pull)
        context.insert(plan)
        try? context.save()
        return plan
    }

    private var pullUp: Exercise {
        Exercise(name: "Pull-Up", muscleGroup: .back, equipment: .pullUpBar,
                 movementPattern: .verticalPull, isCompound: true)
    }

    private var row: Exercise {
        Exercise(name: "Barbell Row", muscleGroup: .back, equipment: .barbell,
                 movementPattern: .horizontalPull, isCompound: true)
    }

    private func sets(_ name: String, in plan: WorkoutPlan) -> [PlannedSet] {
        plan.orderedExercises.first { $0.exercise?.name == name }?.orderedSets ?? []
    }

    func testPullUpWithoutBodyweightIsPlainBodyweight() throws {
        let context = try makeContext()
        let plan = pullPlan(with: [pullUp], bodyweightKg: nil, context: context)
        makeVM().populateExercises(for: plan, modelContext: context)

        let working = sets("Pull-Up", in: plan).filter { !$0.isWarmup }
        XCTAssertFalse(working.isEmpty)
        XCTAssertEqual(working.first?.targetWeight ?? 0, 0, "No phantom external load on a bodyweight lift")
        XCTAssertNil(working.first?.addedLoadKg)
        XCTAssertEqual(TodayWorkoutView.bodyweightLoadText(addedKg: nil, unit: .kg), "(BW)")
    }

    func testPullUpWithBodyweightStartsUnassisted() throws {
        let context = try makeContext()
        let plan = pullPlan(with: [pullUp], bodyweightKg: 80, context: context)
        makeVM().populateExercises(for: plan, modelContext: context)

        let first = sets("Pull-Up", in: plan).first { !$0.isWarmup }
        XCTAssertEqual(first?.targetWeight, 80, "Effective load = bodyweight")
        XCTAssertEqual(first?.addedLoadKg, 0, "Cold start is bodyweight +0, not a negative assist")
    }

    func testDeloadNeverScalesBodyweight() throws {
        let context = try makeContext()
        let plan = pullPlan(with: [pullUp], bodyweightKg: 80, context: context)
        let vm = makeVM()
        vm.isDeloadWeek = true
        vm.populateExercises(for: plan, modelContext: context)

        let first = sets("Pull-Up", in: plan).first { !$0.isWarmup }
        XCTAssertEqual(first?.addedLoadKg, 0, "A deload must not turn a bodyweight pull-up into an assisted one")
    }

    func testEmptyBarWorkingWeightHasNoDuplicateWarmups() throws {
        let context = try makeContext()
        let plan = pullPlan(with: [row], bodyweightKg: nil, context: context)
        makeVM().populateExercises(for: plan, modelContext: context)

        let rowSets = sets("Barbell Row", in: plan)
        let working = rowSets.filter { !$0.isWarmup }
        let warmups = rowSets.filter(\.isWarmup)
        let workingWeight = try XCTUnwrap(working.first?.targetWeight)
        XCTAssertTrue(warmups.allSatisfy { ($0.targetWeight ?? 0) < workingWeight },
                      "Every ramp set must be lighter than the working weight")
        XCTAssertEqual(Set(warmups.compactMap(\.targetWeight)).count, warmups.count, "No duplicate ramp steps")
    }

    func testPlanTextKeepsHalfKilos() {
        XCTAssertEqual(TodayWorkoutView.weightText(22.5), "22.5")
        XCTAssertEqual(TodayWorkoutView.weightText(20), "20")
        XCTAssertEqual(TodayWorkoutView.bodyweightLoadText(addedKg: 10, unit: .kg), "@ BW +10kg")
        XCTAssertEqual(TodayWorkoutView.bodyweightLoadText(addedKg: -15, unit: .kg), "@ BW −15kg assist")
    }
}
