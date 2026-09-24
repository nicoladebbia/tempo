//
// DailyHydrationTargetTests.swift
// Tempo
//
// RecoverIQ's prescription hydration and the Dashboard's NutritionEngine
// hydration must be the same number for the same inputs. RecoveryEngine used
// a hardcoded 80 kg + its own +500 ml/session rule; it now goes through
// DailyHydrationTarget, which runs NutritionEngine's own hydration math.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class DailyHydrationTargetTests: XCTestCase {
    // MARK: - Pure math

    func testBaseUsesWeightOrFallsBackToDashboardDefault() {
        XCTAssertEqual(DailyHydrationTarget.baseMl(bodyWeightKg: 70), 2450)
        XCTAssertEqual(DailyHydrationTarget.baseMl(bodyWeightKg: 90), 3150)
        XCTAssertEqual(DailyHydrationTarget.baseMl(bodyWeightKg: nil), 2500)
        XCTAssertEqual(DailyHydrationTarget.baseMl(bodyWeightKg: 0), 2500, "bad reading → fallback")
    }

    /// The contract: for every zone × training × activity × weight combo,
    /// RecoveryEngine's hydration equals NutritionEngine.adjustedTargets
    /// fed the same base — i.e. the Dashboard formula.
    func testRecoveryEngineMatchesNutritionEngineAcrossInputs() {
        let scores: [Double] = [10, 40, 50, 66, 80, 95]
        let weights: [Double?] = [nil, 62, 80, 104]
        let activities: [(Double?, Double?)] = [(nil, nil), (931, 134), (1200, 20)]
        for score in scores {
            for training in [true, false] {
                for weight in weights {
                    for (kcal, mins) in activities {
                        let recovery = RecoveryEngine.hydrationTarget(
                            recoveryScore: score,
                            plannedTraining: training,
                            bodyWeightKg: weight,
                            activityCaloriesBurned: kcal,
                            activityDurationMin: mins
                        )
                        let dashboard = NutritionEngine.adjustedTargets(
                            baseCalories: 2400,
                            baseProtein: 180,
                            baseCarbs: 280,
                            baseFat: 80,
                            recoveryZone: RecoveryZone(score: score),
                            currentStrain: 12,
                            isTrainingDay: training,
                            isRestDay: !training,
                            baseHydrationMl: DailyHydrationTarget.baseMl(bodyWeightKg: weight),
                            activityCaloriesBurned: kcal,
                            activityDurationMin: mins
                        ).hydrationTargetMl
                        XCTAssertEqual(
                            recovery, dashboard,
                            "score \(score) training \(training) weight \(String(describing: weight)) kcal \(String(describing: kcal))"
                        )
                    }
                }
            }
        }
    }

    /// With no weight known the prescription equals today's Dashboard number
    /// exactly (Dashboard uses NutritionEngine's default 2500 ml base).
    func testPrescriptionWithoutWeightEqualsCurrentDashboardDefault() {
        let rx = RecoveryEngine().generatePrescription(
            recovery: DailyRecovery(date: Date(), recoveryScore: 20, sleepHours: 8, sleepEfficiency: 90),
            schedule: []
        )
        let dashboard = NutritionEngine.adjustedTargets(
            baseCalories: 2400, baseProtein: 180, baseCarbs: 280, baseFat: 80,
            recoveryZone: .red, currentStrain: nil, isTrainingDay: false, isRestDay: false
        ).hydrationTargetMl
        XCTAssertEqual(rx.hydrationTargetMl, dashboard)
        XCTAssertEqual(rx.hydrationTargetMl, 3000) // 2500 × 1.2 red
    }

    // MARK: - Store inputs

    func testStoreTargetUsesRealWeightAndTodaysActivity() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())
        context.insert(DietaryProfile(currentWeightKg: 70))
        context.insert(ActivitySession(
            date: today, startTime: Date(), workoutType: "Soccer", sportID: 0,
            source: "whoop", caloriesBurned: 931, durationMinutes: 134
        ))
        try context.save()

        XCTAssertEqual(DailyHydrationTarget.bodyWeightKg(in: context), 70)
        let target = DailyHydrationTarget.targetMl(in: context, recoveryZone: .yellow, isTrainingDay: true)
        let expected = 2450 + HydrationMath.activityBonusMl(caloriesBurned: 931, durationMinutes: 134)
        XCTAssertEqual(target, expected)
    }

    func testHealthKitSnapshotWeightWinsOverDietaryProfile() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(DietaryProfile(currentWeightKg: 70))
        context.insert(BodyComposition(date: Date(), weightKg: 82))
        try context.save()

        XCTAssertEqual(DailyHydrationTarget.bodyWeightKg(in: context), 82)
    }

    func testTrainingDayFollowsTodaysWorkoutPlan() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        XCTAssertNil(DailyHydrationTarget.todayIsTrainingDay(in: context))

        let plan = WorkoutPlan(date: Date(), type: .rest)
        context.insert(plan)
        try context.save()
        XCTAssertEqual(DailyHydrationTarget.todayIsTrainingDay(in: context), false)

        plan.type = .push
        try context.save()
        XCTAssertEqual(DailyHydrationTarget.todayIsTrainingDay(in: context), true)
    }
}
