//
// TravelSwapEngineTests.swift
// Tempo
//
// Pause/travel-pain feature — "closest library exercise with the same
// movement pattern and muscle group on the available equipment".
//

@testable import Tempo
import XCTest

final class TravelSwapEngineTests: XCTestCase {
    private func candidate(
        _ name: String,
        equipment: Equipment,
        pattern: MovementPattern,
        muscle: MuscleGroup,
        compound: Bool = true
    ) -> TravelSwapEngine.Candidate {
        TravelSwapEngine.Candidate(
            id: UUID(), name: name, equipment: equipment, movementPattern: pattern, muscleGroup: muscle, isCompound: compound
        )
    }

    func testPicksSameMovementAndMuscleOnAvailableEquipment() {
        let source = candidate("Barbell RDL", equipment: .barbell, pattern: .hinge, muscle: .hamstrings)
        let library = [
            source,
            candidate("Dumbbell RDL", equipment: .dumbbell, pattern: .hinge, muscle: .hamstrings),
            candidate("Leg Curl", equipment: .machine, pattern: .isolation, muscle: .hamstrings),
            candidate("Barbell Bench Press", equipment: .barbell, pattern: .horizontalPush, muscle: .chest),
        ]
        let picked = TravelSwapEngine.pickReplacement(for: source, in: library, available: [.dumbbell])
        XCTAssertEqual(picked?.name, "Dumbbell RDL")
    }

    func testBodyweightAlwaysUsableEvenWithNoEquipmentSelected() {
        let source = candidate("Barbell Back Squat", equipment: .barbell, pattern: .squat, muscle: .quads)
        let library = [
            source,
            candidate("Bodyweight Squat", equipment: .bodyweight, pattern: .squat, muscle: .quads),
        ]
        let picked = TravelSwapEngine.pickReplacement(for: source, in: library, available: [])
        XCTAssertEqual(picked?.name, "Bodyweight Squat")
    }

    func testReturnsNilWhenNothingMatchesThePattern() {
        let source = candidate("Barbell RDL", equipment: .barbell, pattern: .hinge, muscle: .hamstrings)
        let library = [
            source,
            candidate("Barbell Bench Press", equipment: .barbell, pattern: .horizontalPush, muscle: .chest),
        ]
        XCTAssertNil(TravelSwapEngine.pickReplacement(for: source, in: library, available: [.dumbbell]))
    }

    func testFallsBackToDifferentMuscleGroupWhenSameMuscleHasNoUsableMatch() {
        let source = candidate("Barbell RDL", equipment: .barbell, pattern: .hinge, muscle: .hamstrings)
        let library = [
            source,
            candidate("Kettlebell Swing", equipment: .kettlebell, pattern: .hinge, muscle: .glutes),
        ]
        let picked = TravelSwapEngine.pickReplacement(for: source, in: library, available: [.kettlebell])
        XCTAssertEqual(picked?.name, "Kettlebell Swing")
    }

    func testDeterministicTieBreakPrefersCompoundMatchThenShorterName() {
        let source = candidate("Barbell RDL", equipment: .barbell, pattern: .hinge, muscle: .hamstrings, compound: true)
        let library = [
            source,
            candidate("Dumbbell Romanian Deadlift", equipment: .dumbbell, pattern: .hinge, muscle: .hamstrings, compound: true),
            candidate("Dumbbell RDL", equipment: .dumbbell, pattern: .hinge, muscle: .hamstrings, compound: true),
        ]
        let picked = TravelSwapEngine.pickReplacement(for: source, in: library, available: [.dumbbell])
        XCTAssertEqual(picked?.name, "Dumbbell RDL", "shortest name wins the tie")
    }

    func testIsUsable() {
        XCTAssertTrue(TravelSwapEngine.isUsable(.bodyweight, available: []))
        XCTAssertTrue(TravelSwapEngine.isUsable(.none, available: []))
        XCTAssertFalse(TravelSwapEngine.isUsable(.barbell, available: []))
        XCTAssertTrue(TravelSwapEngine.isUsable(.barbell, available: [.barbell]))
    }

    /// The trainer's 60 kg was for the barbell bench — it must not follow the
    /// exercise onto a hotel swap (it showed "Push-up 3 x 8 @ 7kg").
    func testTravelSwapDropsTheTrainerLoadAndUsesEffort() {
        let item = ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8, weightKg: 60)
        let pushUp = Exercise(
            name: "Push-Up", muscleGroup: .chest, equipment: .bodyweight,
            movementPattern: .horizontalPush, isCompound: true
        )
        let swapped = TrainingViewModel.trainerLoad(item, exercise: pushUp, travelSwapped: true)
        XCTAssertTrue(swapped.isEffort)
        XCTAssertNil(swapped.kg)

        let bench = Exercise(
            name: "Barbell Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        let normal = TrainingViewModel.trainerLoad(item, exercise: bench, travelSwapped: false)
        XCTAssertEqual(normal.kg, 60)
        XCTAssertFalse(normal.isEffort)
    }
}
