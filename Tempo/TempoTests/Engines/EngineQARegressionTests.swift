//
// EngineQARegressionTests.swift
// Tempo
//
// Regression pins for the training-engine QA pass: e1RM/prescription
// consistency, recovery x deload load scaling, structured pain reports,
// fatigue-deload decay, calendar-aligned deload weeks, safety-floor clamps
// and the plan-date variation seed.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class EngineQARegressionTests: XCTestCase {
    /// Containers must outlive their contexts — retained for the test's life.
    private var containers: [ModelContainer] = []

    private func makeContainerContext() throws -> ModelContext {
        let container = try TempoModelContainer.create(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
    }

    private func bench() -> Exercise {
        Exercise(name: "Barbell Bench Press", muscleGroup: .chest, equipment: .barbell,
                 movementPattern: .horizontalPush, isCompound: true)
    }

    private func loggedSet(weight: Double, reps: Int, targetReps: Int = 5, targetRIR: Int? = 2, rpe: Int? = nil) -> PlannedSet {
        PlannedSet(setNumber: 1, targetReps: targetReps, targetWeight: weight, targetRIR: targetRIR,
                   actualReps: reps, actualWeight: weight, rpe: rpe, completed: true)
    }

    // MARK: - #1 e1RM consistent with the prescription formula

    func testHittingPrescriptionReproducesTheAnchor() throws {
        let weight = PrescriptionMath.weight(e1RM: 120, reps: 5, rir: 2)
        let e1RM = try XCTUnwrap(loggedSet(weight: weight, reps: 5).estimated1RM)
        XCTAssertEqual(e1RM, 120, accuracy: 0.01, "5 @ RIR 2 as prescribed must not decay the e1RM")
    }

    func testLoggedRPEDrivesTheRIR() throws {
        let weight = PrescriptionMath.weight(e1RM: 120, reps: 5, rir: 2)
        let asPrescribed = try XCTUnwrap(loggedSet(weight: weight, reps: 5, rpe: 8).estimated1RM)
        let grind = try XCTUnwrap(loggedSet(weight: weight, reps: 5, rpe: 10).estimated1RM)
        let easy = try XCTUnwrap(loggedSet(weight: weight, reps: 5, rpe: 6).estimated1RM)
        XCTAssertEqual(asPrescribed, 120, accuracy: 0.01)
        XCTAssertLessThan(grind, 120, "RPE 10 = no reserve = a lower true max")
        XCTAssertGreaterThan(easy, 120, "RPE 6 = 4 in reserve = a higher true max")
    }

    func testBeatingThePrescriptionRaisesTheE1RM() throws {
        let weight = PrescriptionMath.weight(e1RM: 120, reps: 5, rir: 2)
        let sixReps = try XCTUnwrap(loggedSet(weight: weight, reps: 6).estimated1RM)
        XCTAssertGreaterThan(sixReps, 120)
    }

    func testMissedRepsAssumeFailureNotPrescribedRIR() throws {
        let weight = PrescriptionMath.weight(e1RM: 120, reps: 5, rir: 2)
        let missed = try XCTUnwrap(loggedSet(weight: weight, reps: 4).estimated1RM)
        XCTAssertEqual(missed, weight * (1 + 4.0 / 30.0), accuracy: 0.01, "Fell short → RIR 0")
    }

    func testDefaultUnratedSetKeepsPlainEpley() throws {
        let set = loggedSet(weight: 100, reps: 8, targetReps: 8, targetRIR: nil)
        XCTAssertEqual(try XCTUnwrap(set.estimated1RM), 100 * (1 + 8.0 / 30.0), accuracy: 0.001)
    }

    func testHighRepSetsCannotInflateE1RM() throws {
        let junk = try XCTUnwrap(loggedSet(weight: 20, reps: 60, targetReps: 12, targetRIR: nil).estimated1RM)
        XCTAssertEqual(junk, 20 * (1 + 12.0 / 30.0), accuracy: 0.001, "20 kg x 60 counts as 12 reps")
        XCTAssertEqual(StrengthStandards.epleyE1RM(weight: 20, reps: 60), junk, accuracy: 0.001)
    }

    func testPrescriptionAndEstimateAgreeAtEveryScheme() {
        for (reps, rir) in [(5, 2), (8, 2), (10, 2), (12, 1), (15, 1)] {
            let w = PrescriptionMath.weight(e1RM: 100, reps: reps, rir: rir)
            XCTAssertEqual(StrengthStandards.e1RM(weight: w, reps: reps, rir: rir), 100, accuracy: 0.001,
                           "\(reps) @ RIR \(rir) must round-trip")
        }
    }

    func testRepeatedlyHittingThePrescriptionDoesNotDecayOrPlateauReset() {
        // Weekly sessions, each logging exactly what was prescribed off the
        // rolling anchor. The anchor must hold (no compounding daily decay).
        let now = Date()
        var samples = [PrescriptionMath.HistorySample(date: now.addingTimeInterval(-9 * 7 * 86_400), e1RM: 120)]
        for week in stride(from: 8, through: 1, by: -1) {
            let date = now.addingTimeInterval(-Double(week) * 7 * 86_400)
            let anchor = PrescriptionMath.currentE1RM(samples: samples, now: date) ?? 120
            let w = PrescriptionMath.weight(e1RM: anchor, reps: 5, rir: 2)
            samples.append(.init(date: date, e1RM: StrengthStandards.e1RM(weight: w, reps: 5, rir: 2)))
        }
        let anchor = PrescriptionMath.currentE1RM(samples: samples, now: now) ?? 0
        XCTAssertEqual(anchor, 120, accuracy: 0.5, "Hitting the prescription maintains the e1RM")
    }

    func testOutcomeEvaluatorCountsE1RMNotHeaviestLoad() throws {
        let context = try makeContainerContext()
        let ex = bench()
        context.insert(ex)
        let day1 = Date().addingTimeInterval(-3 * 86_400)
        let day2 = Date().addingTimeInterval(-1 * 86_400)
        // Heavier single on day 2 but a LOWER e1RM: not progress.
        let a = ExerciseHistory(date: day1, estimated1RM: 120, totalVolume: 1000, bestSetWeight: 100, bestSetReps: 5, exercise: ex)
        let b = ExerciseHistory(date: day2, estimated1RM: 105, totalVolume: 300, bestSetWeight: 105, bestSetReps: 1, exercise: ex)
        context.insert(a)
        context.insert(b)
        let stalled = TrainingOutcomeEvaluator.evaluate(lastWeek: [a, b], plannedTrainingDays: 2, priorWeekVolume: 0)
        XCTAssertEqual(stalled.progressionHits, 0)

        b.estimated1RM = 125
        let progressed = TrainingOutcomeEvaluator.evaluate(lastWeek: [a, b], plannedTrainingDays: 2, priorWeekVolume: 0)
        XCTAssertEqual(progressed.progressionHits, 1)
    }

    // MARK: - #2 recovery / deload stacking

    func testYellowIsVolumeOnlyAndFloorHoldsAgainstStacking() {
        XCTAssertEqual(TrainingEngine.recoveryLoadScale(recoveryAdjustment: 0.8), 1.0, "upper yellow keeps the load")
        XCTAssertEqual(TrainingEngine.recoveryLoadScale(recoveryAdjustment: 0.75), 0.95, "lower yellow: -5% weight")
        XCTAssertEqual(TrainingEngine.recoveryLoadScale(recoveryAdjustment: 1.0), 1.0)
        // Yellow x deload, and an AI-trimmed 0.5, never fall under the deload value.
        for adj in [0.8, 0.75, 0.5] {
            XCTAssertGreaterThanOrEqual(
                TrainingEngine.combinedLoadScale(recoveryAdjustment: adj, deloadMultiplier: 0.6), 0.6
            )
        }
        XCTAssertEqual(TrainingEngine.combinedLoadScale(recoveryAdjustment: 0.8, deloadMultiplier: 1.0), 1.0)
    }

    private func populatedBenchSets(recoveryAdjustment: Double, deload: Bool = false) throws -> [PlannedSet] {
        let context = try makeContainerContext()
        let ex = bench()
        context.insert(ex)
        for (daysAgo, e1RM) in [(14.0, 115.0), (7.0, 118.0), (2.0, 120.0)] {
            context.insert(ExerciseHistory(date: Date().addingTimeInterval(-daysAgo * 86_400),
                                           estimated1RM: e1RM, totalVolume: 1000, exercise: ex))
        }
        let plan = WorkoutPlan(date: Date(), type: .push, recoveryAdjustment: recoveryAdjustment)
        context.insert(plan)
        try context.save()
        makeVM().populateExercises(for: plan, modelContext: context)
        return (plan.orderedExercises.first { $0.exercise?.name == ex.name }?.orderedSets ?? []).filter { !$0.isWarmup }
    }

    func testYellowDayKeepsWeightButLosesASet() throws {
        let green = try populatedBenchSets(recoveryAdjustment: 1.0)
        let yellow = try populatedBenchSets(recoveryAdjustment: 0.8)
        XCTAssertEqual(green.first?.targetWeight, yellow.first?.targetWeight, "Volume-only cut: same load")
        XCTAssertEqual(green.count - yellow.count, 1, "The cut lives in the set count")
    }

    // MARK: - #3 structured pain reports

    private func seedChest(_ context: ModelContext) -> (bench: Exercise, incline: Exercise) {
        let b = bench()
        let incline = Exercise(name: "Incline Dumbbell Press", muscleGroup: .chest, equipment: .dumbbell,
                               movementPattern: .horizontalPush, isCompound: true)
        context.insert(b)
        context.insert(incline)
        for ex in [b, incline] {
            for (daysAgo, e1RM) in [(14.0, 115.0), (7.0, 118.0), (2.0, 120.0)] {
                context.insert(ExerciseHistory(date: Date().addingTimeInterval(-daysAgo * 86_400),
                                               estimated1RM: e1RM, totalVolume: 1000, exercise: ex))
            }
        }
        return (b, incline)
    }

    func testStructuredPainReportFlagsExercise() throws {
        let context = try makeContainerContext()
        let (b, _) = seedChest(context)
        context.insert(PainReport(bodyArea: .shoulder, severity: 8, exerciseID: b.id))
        try context.save()
        XCTAssertTrue(makeVM().painFlaggedExerciseIDs(modelContext: context).contains(b.id))
    }

    func testSeverePainReportDropsExerciseFromPlannedSession() throws {
        let context = try makeContainerContext()
        let (b, incline) = seedChest(context)
        context.insert(PainReport(bodyArea: .shoulder, severity: 8, exerciseID: b.id))
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        try context.save()
        makeVM().populateExercises(for: plan, modelContext: context)
        let names = plan.orderedExercises.compactMap { $0.exercise?.name }
        XCTAssertFalse(names.contains(b.name), "Bench must not be prescribed on a severity-8 report")
        XCTAssertTrue(names.contains(incline.name))
    }

    func testMildPainReportKeepsExerciseAtReducedLoad() throws {
        let context = try makeContainerContext()
        let clean = try populatedBenchSets(recoveryAdjustment: 1.0)
        let (b, _) = seedChest(context)
        context.insert(PainReport(bodyArea: .shoulder, severity: 2, exerciseID: b.id))
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        try context.save()
        makeVM().populateExercises(for: plan, modelContext: context)
        let sets = (plan.orderedExercises.first { $0.exercise?.id == b.id }?.orderedSets ?? []).filter { !$0.isWarmup }
        let cleanWeight = try XCTUnwrap(clean.first?.targetWeight)
        let weight = try XCTUnwrap(sets.first?.targetWeight)
        XCTAssertLessThan(weight, cleanWeight * 0.85, "Mild report: ~-20% load")
    }

    func testExpiredPainReportIsIgnored() throws {
        let context = try makeContainerContext()
        let (b, _) = seedChest(context)
        context.insert(PainReport(date: Date().addingTimeInterval(-10 * 86_400), bodyArea: .shoulder, severity: 8, exerciseID: b.id))
        try context.save()
        XCTAssertFalse(makeVM().painFlaggedExerciseIDs(modelContext: context).contains(b.id))
    }

    // MARK: - #4 fatigue-triggered full rest can clear

    func testFatigueDecaysTowardBaselineDuringRest() {
        let now = Date()
        let fresh = AdaptiveProfile.decayedFatigue(9.5, lastUpdated: now, asOf: now)
        let weekLater = AdaptiveProfile.decayedFatigue(9.5, lastUpdated: now.addingTimeInterval(-8 * 86_400), asOf: now)
        XCTAssertEqual(fresh, 9.5)
        XCTAssertLessThan(weekLater ?? 99, 8.5, "A full-rest week clears the trigger")
        XCTAssertNil(AdaptiveProfile.decayedFatigue(nil, lastUpdated: now, asOf: now))
    }

    func testFullRestDeloadClearsAfterRestWeek() {
        let engine = TrainingEngine()
        let monday = Date()
        let start = Calendar.current.date(byAdding: .day, value: -3, to: monday)
        func deload(_ ewma: Double?) -> Bool {
            engine.isDeloadWeek(date: monday, deloadFrequencyWeeks: 5, trainingStartDate: start, fatigueEWMA: ewma)
        }
        XCTAssertTrue(deload(9.5))
        let decayed = AdaptiveProfile.decayedFatigue(9.5, lastUpdated: monday.addingTimeInterval(-8 * 86_400), asOf: monday)
        XCTAssertFalse(deload(decayed))
    }

    // MARK: - #5 calendar-aligned deload weeks

    func testDeloadWeekIsAlignedToMondayWeeks() throws {
        var cal = Calendar.current
        cal.timeZone = .current
        func date(_ d: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))!
        }
        // Started Wednesday 2 Sep 2026; frequency 2 → plan week of 14–20 Sep is the deload.
        let engine = TrainingEngine()
        func isDeload(_ day: Int) -> Bool {
            engine.isDeloadWeek(date: date(day), deloadFrequencyWeeks: 2, trainingStartDate: date(2), fatigueEWMA: nil)
        }
        XCTAssertFalse(isDeload(13), "Sunday before")
        for day in 14 ... 20 {
            XCTAssertTrue(isDeload(day), "Every day of the Mon–Sun week agrees (Sep \(day))")
        }
        XCTAssertFalse(isDeload(21))
        XCTAssertFalse(isDeload(2), "Start week itself is never a deload")
    }

    // MARK: - #6 safety floor clamp

    func testClampIntensityScalesTheNumbersNotJustTheLabel() {
        let block = SessionBlockDTO(
            kind: .field, label: "Sprints", notes: nil, cue: nil, scheduledMin: nil, split: nil,
            reps: 10, distanceM: 40, restSec: 90, intensityPct: 100, durationSec: nil, stroke: nil,
            runType: nil, paceSecPerKm: nil, sets: 6
        )
        let session = DailySessionDTO(
            modality: "field", intensity: .max, durationMin: 60, blocks: [block],
            shortWhy: "x", fullWhy: nil, expectedStrain: 15, expectedSessionRPE: 10
        )
        let clamped = TrainingSafetyFloor.clampIntensity(session, to: .moderate)
        XCTAssertEqual(clamped.intensity, .moderate)
        let b = clamped.blocks[0]
        XCTAssertEqual(b.intensityPct ?? 0, 70, accuracy: 0.001)
        XCTAssertEqual(b.sets, 4)
        XCTAssertEqual(b.reps, 7)
        XCTAssertLessThanOrEqual(clamped.expectedSessionRPE ?? 99, 6)
        XCTAssertEqual(TrainingSafetyFloor.clampIntensity(clamped, to: .moderate), clamped, "Already at cap → unchanged")
    }

    // MARK: - #7 variation seed follows plan.date

    func testSelectExercisesVariationFollowsPlanDate() {
        let pool = (0 ..< 5).map {
            Exercise(name: "Chest Comp \($0)", muscleGroup: .chest, equipment: .barbell,
                     movementPattern: .horizontalPush, isCompound: true)
        }
        let vm = makeVM()
        let cal = Calendar.current
        let d1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        let d2 = cal.date(byAdding: .day, value: 1, to: d1)!
        let pick1 = vm.selectExercises(from: pool, targetGroups: [.chest], workoutType: .push, date: d1).first
        let pick2 = vm.selectExercises(from: pool, targetGroups: [.chest], workoutType: .push, date: d2).first
        XCTAssertNotEqual(pick1?.name, pick2?.name, "Different plan days rotate through the pool")
        let doy = cal.ordinality(of: .day, in: .year, for: d1) ?? 0
        XCTAssertEqual(pick1?.name, pool[doy % 5].name)
    }
}
