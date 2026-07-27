//
// SetFeedbackExerciseIDTests.swift
// Tempo
//
// Pins the crash fix for the SwiftData invalidated-backing fatal in
// noteSignals: SetFeedback now denormalizes exerciseID at capture time (same
// survives-deletion pattern as setID), so aggregation never traverses the
// one-way plannedSet relationship (whose .nullify does not fire, leaving a
// dangling reference that faults). These pin the capture; the crash-avoidance
// itself (reading nil on orphaned rows → skip) is verified on-device.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class SetFeedbackExerciseIDTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Exercise.self, PlannedExercise.self, PlannedSet.self,
            SetFeedback.self, WorkoutPlan.self,
            configurations: config
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testCapturesExerciseIDFromLiveSetGraph() throws {
        let ex = Exercise(name: "Barbell Row", muscleGroup: .quads, equipment: .barbell,
                          movementPattern: .squat, isCompound: true)
        let pe = PlannedExercise(order: 0, exercise: ex)
        let set = PlannedSet(setNumber: 1, targetReps: 8, plannedExercise: pe)
        context.insert(ex)
        context.insert(pe)
        context.insert(set)

        let feedback = SetFeedback(plannedSet: set, rpe: 7)
        XCTAssertEqual(feedback.exerciseID, ex.id,
                       "exerciseID must be captured from the live set graph at creation")
        XCTAssertEqual(feedback.setID, set.id, "setID still captured (unchanged behavior)")
    }

    func testExerciseIDNilWhenNoSet() {
        let feedback = SetFeedback(plannedSet: nil, rpe: 7)
        XCTAssertNil(feedback.exerciseID,
                     "No set → nil exerciseID; noteSignals skips it rather than faulting")
    }

    func testExplicitExerciseIDWins() {
        let forced = UUID()
        let feedback = SetFeedback(plannedSet: nil, exerciseID: forced, rpe: 7)
        XCTAssertEqual(feedback.exerciseID, forced)
    }
}
