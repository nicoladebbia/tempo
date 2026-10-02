//
// ExerciseBestSetTests.swift
// Tempo
//
// "Best set" is one set that happened; "current 1RM" is steady.
//

@testable import Tempo
import XCTest

final class ExerciseBestSetTests: XCTestCase {
    private func row(_ weight: Double?, _ reps: Int?, e1RM: Double? = nil, daysAgo: Int = 0) -> ExerciseHistory {
        ExerciseHistory(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
            estimated1RM: e1RM, bestSetWeight: weight, bestSetReps: reps
        )
    }

    func testBestSetIsOneRealSetNotAComposite() {
        // 100 × 3 one week, 60 × 12 another: the old code showed "100 × 12".
        let best = ExerciseBestSet.pick(from: [row(100, 3), row(60, 12)])
        XCTAssertEqual(best, ExerciseBestSet(weightKg: 100, reps: 3))
    }

    func testTieOnWeightGoesToMoreReps() {
        XCTAssertEqual(ExerciseBestSet.pick(from: [row(80, 5), row(80, 8)]), ExerciseBestSet(weightKg: 80, reps: 8))
    }

    func testBodyweightBestIsMostReps() {
        XCTAssertEqual(ExerciseBestSet.pick(from: [row(0, 10), row(nil, 14)]), ExerciseBestSet(weightKg: 0, reps: 14))
        XCTAssertNil(ExerciseBestSet.pick(from: [row(80, nil)]))
    }

    func testCurrent1RMIgnoresOneLightDay() {
        let rows = [row(100, 5, e1RM: 116, daysAgo: 10), row(70, 5, e1RM: 81, daysAgo: 1)]
        XCTAssertEqual(Exercise.currentEstimated1RM(from: rows), 116, "A deload day isn't 'you got weaker'")
    }

    func testCurrent1RMSkipsSessionsWithoutAnEstimate() {
        let rows = [row(100, 5, e1RM: 116, daysAgo: 3), row(0, 12, e1RM: 0, daysAgo: 1), row(0, 12, daysAgo: 0)]
        XCTAssertEqual(Exercise.currentEstimated1RM(from: rows), 116, "Was nil / 0 when the latest row had none")
    }

    func testCurrent1RMFallsBackToLatestWhenNothingRecent() {
        let rows = [row(120, 3, e1RM: 132, daysAgo: 200), row(100, 5, e1RM: 116, daysAgo: 90)]
        XCTAssertEqual(Exercise.currentEstimated1RM(from: rows), 116, "Latest, not the old all-time high")
    }

    func testSessionBestSetBreaksWeightTiesByReps() {
        let slot = PlannedExercise(order: 0)
        slot.sets = [
            PlannedSet(setNumber: 1, targetReps: 8, actualReps: 6, actualWeight: 80, completed: true, plannedExercise: slot),
            PlannedSet(setNumber: 2, targetReps: 8, actualReps: 8, actualWeight: 80, completed: true, plannedExercise: slot),
        ]
        XCTAssertEqual(slot.bestSet?.actualReps, 8)
    }
}
