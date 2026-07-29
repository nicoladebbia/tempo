//
// PrescriptionMathTests.swift
// Tempo
//
// §11.12 — pins the e1RM-anchored prescription brain: reverse-Epley loads,
// recency-decayed rolling e1RM, DUP schemes by role/occurrence, plateau
// detection, and the populateExercises integration (rich history → zones +
// RIR; thin history → the legacy 8/12 increment path untouched).
//

import SwiftData
@testable import Tempo
import XCTest

final class PrescriptionMathTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private var now: Date { Date(timeIntervalSince1970: 1_753_800_000) }

    private func sample(daysAgo: Double, e1RM: Double?) -> PrescriptionMath.HistorySample {
        PrescriptionMath.HistorySample(date: now.addingTimeInterval(-daysAgo * day), e1RM: e1RM)
    }

    // MARK: - Reverse Epley

    func testWeightForRepsAtRIR() {
        // 8 @ RIR 2 is a 10RM: e1RM / (1 + 10/30) = e1RM × 0.75 exactly.
        XCTAssertEqual(PrescriptionMath.weight(e1RM: 100, reps: 8, rir: 2), 75.0, accuracy: 0.001)
        // 5 @ RIR 2 is a 7RM: 120 / (1 + 7/30) ≈ 97.30.
        XCTAssertEqual(PrescriptionMath.weight(e1RM: 120, reps: 5, rir: 2), 97.297, accuracy: 0.01)
        XCTAssertEqual(PrescriptionMath.weight(e1RM: 0, reps: 5, rir: 2), 0, "No anchor → no load")
    }

    // MARK: - Rolling e1RM

    func testCurrentE1RMDecaysOldSessions() {
        // 100 ten days ago decays to ~95.1 and still beats a fresh 92.
        let value = PrescriptionMath.currentE1RM(
            samples: [sample(daysAgo: 10, e1RM: 100), sample(daysAgo: 2, e1RM: 92)],
            now: now
        )
        XCTAssertEqual(value ?? 0, 100 * pow(0.995, 10), accuracy: 0.01)
    }

    func testCurrentE1RMNeedsTwoScoredSessionsInWindow() {
        XCTAssertNil(PrescriptionMath.currentE1RM(samples: [sample(daysAgo: 3, e1RM: 100)], now: now))
        // A second session OUTSIDE the 60-day window doesn't count.
        XCTAssertNil(PrescriptionMath.currentE1RM(
            samples: [sample(daysAgo: 3, e1RM: 100), sample(daysAgo: 90, e1RM: 110)],
            now: now
        ))
        // nil e1RMs never count.
        XCTAssertNil(PrescriptionMath.currentE1RM(
            samples: [sample(daysAgo: 3, e1RM: 100), sample(daysAgo: 5, e1RM: nil)],
            now: now
        ))
    }

    // MARK: - Schemes (DUP)

    func testFirstOccurrenceSchemes() {
        XCTAssertEqual(PrescriptionMath.scheme(role: .primaryCompound, weekOccurrence: 0),
                       PrescriptionMath.Scheme(reps: 5, rir: 2, zoneLabel: "HEAVY"))
        XCTAssertEqual(PrescriptionMath.scheme(role: .secondaryCompound, weekOccurrence: 0),
                       PrescriptionMath.Scheme(reps: 8, rir: 2, zoneLabel: "BUILD"))
        XCTAssertEqual(PrescriptionMath.scheme(role: .isolation, weekOccurrence: 0),
                       PrescriptionMath.Scheme(reps: 12, rir: 1, zoneLabel: "PUMP"))
    }

    func testSecondOccurrenceUndulatesToVolume() {
        XCTAssertEqual(PrescriptionMath.scheme(role: .primaryCompound, weekOccurrence: 1).reps, 8,
                       "Second same-type day this week trades heavy 5s for volume 8s")
        XCTAssertEqual(PrescriptionMath.scheme(role: .isolation, weekOccurrence: 1).reps, 15)
    }

    // MARK: - Plateau

    func testFlatE1RMReadsPlateaued() {
        let flat = (0 ..< 8).map { sample(daysAgo: Double(56 - $0 * 7), e1RM: 100) }
        XCTAssertTrue(PrescriptionMath.isPlateaued(samples: flat))
    }

    func testRisingE1RMIsNotPlateaued() {
        let rising = (0 ..< 8).map { sample(daysAgo: Double(56 - $0 * 7), e1RM: 100 + Double($0) * 2) }
        XCTAssertFalse(PrescriptionMath.isPlateaued(samples: rising))
    }

    func testYoungLiftNeverReadsPlateaued() {
        let young = (0 ..< 5).map { sample(daysAgo: Double($0 * 7), e1RM: 100) }
        XCTAssertFalse(PrescriptionMath.isPlateaued(samples: young), "Needs two full windows")
    }

    func testZoneLabelFromReps() {
        XCTAssertEqual(PrescriptionMath.zoneLabel(forReps: 5), "HEAVY")
        XCTAssertEqual(PrescriptionMath.zoneLabel(forReps: 8), "BUILD")
        XCTAssertEqual(PrescriptionMath.zoneLabel(forReps: 10), "BUILD")
        XCTAssertEqual(PrescriptionMath.zoneLabel(forReps: 12), "PUMP")
    }
}

// MARK: - populateExercises integration

@MainActor
final class PrescriptionEngineIntegrationTests: XCTestCase {
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

    func testRichHistoryGetsE1RMAnchoredHeavyScheme() throws {
        let context = try makeContext()
        let vm = makeVM()

        let bench = Exercise(name: "Barbell Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush,
                             isCompound: true)
        context.insert(bench)
        // Three scored sessions, freshest e1RM 120 → rolling anchor ≈ 120.
        for (daysAgo, e1RM) in [(14.0, 115.0), (7.0, 118.0), (2.0, 120.0)] {
            context.insert(ExerciseHistory(
                date: Date().addingTimeInterval(-daysAgo * 86_400),
                estimated1RM: e1RM, totalVolume: 1000, exercise: bench
            ))
        }
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        try context.save()

        vm.populateExercises(for: plan, modelContext: context)

        let working = plan.orderedExercises.first?.orderedSets.filter { !$0.isWarmup } ?? []
        XCTAssertEqual(working.first?.targetReps, 5, "Primary compound, first occurrence → HEAVY 5s")
        XCTAssertEqual(working.first?.targetRIR, 2)
        // Anchor ~119-120 (2 days of decay) → 5 @ RIR 2 ≈ /1.2333 ≈ 96.5-97.3,
        // snapped to the 2.5 kg barbell lattice.
        let weight = working.first?.targetWeight ?? 0
        XCTAssertTrue((95.0 ... 100.0).contains(weight),
                      "e1RM-anchored heavy load expected ≈97 kg, got \(weight)")
    }

    func testThinHistoryKeepsLegacyPath() throws {
        let context = try makeContext()
        let vm = makeVM()

        let bench = Exercise(name: "Barbell Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush,
                             isCompound: true)
        context.insert(bench)
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        try context.save()

        vm.populateExercises(for: plan, modelContext: context)

        let working = plan.orderedExercises.first?.orderedSets.filter { !$0.isWarmup } ?? []
        XCTAssertEqual(working.first?.targetReps, 8, "No history → legacy 8-rep compound path")
        XCTAssertNil(working.first?.targetRIR, "Legacy path carries no RIR target")
    }
}
