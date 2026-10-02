//
// ImportedExerciseResolverTests.swift
// Tempo
//
// CSV exercise names against the REAL built-in library names: the common
// Strong/Hevy spellings must land on the existing exercise (one history, not
// a forked custom twin), look-alike variants must not, and unmatched names
// get a sensible muscle group instead of Full Body.
//

@testable import Tempo
import XCTest

final class ImportedExerciseResolverTests: XCTestCase {
    private let libraryNames: [String] = [
        "Ab Wheel Rollout", "Arnold Press", "Band Pull-Apart", "Banded Face Pull", "Barbell Back Squat", "Barbell Bench Press", "Barbell Curl", "Barbell Row", "Barbell Shrug", "Battle Rope", "Bear Crawl", "Bench Dip", "Bicycle Crunch", "Box Jump", "Box Squat", "Bulgarian Split Squat", "Burpee", "Cable Crossover", "Cable Crunch", "Cable Curl", "Cable Face Pull with External Rotation", "Cable Fly", "Cable Lateral Raise", "Cable Pull-Through", "Cable Woodchop Low to High", "Chest Dip", "Chest Supported Row", "Chin-Up", "Close-Grip Bench Press", "Concentration Curl", "Conventional Deadlift", "Dead Bug", "Decline Bench Press", "Decline Crunch", "Deficit Deadlift", "Diamond Push-Up", "Donkey Calf Raise", "Dragon Flag", "Dumbbell Calf Raise", "Dumbbell Curl", "Dumbbell Flat Bench Press", "Dumbbell Floor Press", "Dumbbell Fly", "Dumbbell Lateral Lunge", "Dumbbell Pullover", "Dumbbell Reverse Fly", "Dumbbell Romanian Deadlift", "Dumbbell Shoulder Press", "Dumbbell Shrug", "Dumbbell Snatch", "Dumbbell Tricep Kickback", "Dumbbell Wrist Curl", "EZ Bar Curl", "Face Pull", "Farmer's Walk", "Front Raise", "Front Squat", "Glute Bridge", "Glute Kickback", "Goblet Squat", "Good Morning", "Hack Squat", "Hammer Curl", "Handstand Push-Up", "Hanging Leg Raise", "Hip Abductor Machine", "Hip Adductor Machine", "Hip Flexor Stretch", "Hip Thrust", "Incline Cable Fly", "Incline Dumbbell Curl", "Incline Dumbbell Press", "Incline Hammer Curl", "Inverted Row", "JM Press", "Jump Squat", "Kettlebell Clean and Press", "Kettlebell Goblet Squat", "Kettlebell Swing", "Kettlebell Turkish Get-Up", "L-Sit", "Landmine Press", "Landmine Row", "Lat Pulldown", "Lateral Raise", "Leg Curl", "Leg Extension", "Leg Press", "Leg Press Calf Raise", "Machine Chest Press", "Machine Shoulder Press", "Meadows Row", "Mountain Climber", "Muscle-Up", "Nordic Hamstring Curl", "Overhead Press", "Overhead Squat", "Overhead Tricep Extension", "Pallof Press", "Pec Deck", "Pendlay Row", "Pike Push-Up", "Plank", "Preacher Curl", "Pull-Up", "Push-Up", "Rack Pull", "Rear Delt Fly", "Reverse Grip Barbell Row", "Reverse Lunge", "Reverse Pec Deck", "Reverse Wrist Curl", "Romanian Deadlift", "Rope Pushdown", "Russian Twist", "Seated Cable Row", "Seated Calf Raise", "Seated Dumbbell Press", "Seated Leg Curl", "Side Plank", "Single-Arm Dumbbell Row", "Single-Leg Deadlift", "Sissy Squat", "Skull Crusher", "Sled Push", "Smith Machine Squat", "Spider Curl", "Standing Barbell Calf Raise", "Standing Cable Fly", "Standing Calf Raise", "Step-Up", "Stiff-Leg Deadlift", "Straight-Arm Pulldown", "Suitcase Carry", "Sumo Deadlift", "Sumo Squat", "T-Bar Row", "Toes to Bar", "Trap Bar Deadlift", "Tricep Dip", "Tricep Pushdown", "Upright Row", "V-Bar Pulldown", "Walking Lunge", "Woodchop", "Wrist Curl", "Z Press",
    ]

    private lazy var library: [ExerciseMatcher.Candidate] = libraryNames.map {
        ExerciseMatcher.Candidate(id: UUID(), name: $0)
    }

    private func resolved(_ name: String) -> String? {
        ImportedExerciseResolver.resolve(name, in: library)?.name
    }

    func testStrongAndHevySpellingsLandOnTheLibraryExercise() {
        let expected: [String: String] = [
            "Bench Press (Barbell)": "Barbell Bench Press",
            "Barbell Bench Press": "Barbell Bench Press",
            "bench press (barbell)": "Barbell Bench Press",
            "Bench Press (Dumbbell)": "Dumbbell Flat Bench Press",
            "Incline Bench Press (Dumbbell)": "Incline Dumbbell Press",
            "Squat (Barbell)": "Barbell Back Squat",
            "Deadlift (Barbell)": "Conventional Deadlift",
            "Romanian Deadlift (Barbell)": "Romanian Deadlift",
            "Overhead Press (Barbell)": "Overhead Press",
            "Bent Over Row (Barbell)": "Barbell Row",
            "Lat Pulldown (Cable)": "Lat Pulldown",
            "Seated Row (Cable)": "Seated Cable Row",
            "Bicep Curl (Dumbbell)": "Dumbbell Curl",
            "Bicep Curl (Barbell)": "Barbell Curl",
            "Triceps Pushdown (Cable)": "Tricep Pushdown",
            "Pull Up": "Pull-Up",
            "Pull Up (Bodyweight)": "Pull-Up",
            "Chin Up": "Chin-Up",
            "Push Up": "Push-Up",
            "Lateral Raise (Dumbbell)": "Lateral Raise",
            "Leg Extension (Machine)": "Leg Extension",
            "Seated Leg Curl (Machine)": "Seated Leg Curl",
            "Hip Thrust (Barbell)": "Hip Thrust",
            "Standing Calf Raise (Machine)": "Standing Calf Raise",
            "Face Pull (Cable)": "Face Pull",
            "Shoulder Press (Dumbbell)": "Dumbbell Shoulder Press",
            "Goblet Squat (Kettlebell)": "Kettlebell Goblet Squat",
            "DB Row": "Single-Arm Dumbbell Row",
        ]
        for (raw, library) in expected {
            XCTAssertEqual(resolved(raw), library, "\(raw)")
        }
    }

    func testLookAlikeVariantsAreNotMergedIntoTheWrongLift() {
        // The library has no flat/low-incline barbell variant of these: a
        // wrong confident match would corrupt both lifts' history.
        XCTAssertNil(resolved("Incline Bench Press (Barbell)"), "Incline Dumbbell Press is a different lift")
        XCTAssertNotEqual(resolved("Lying Leg Curl (Machine)"), "Seated Leg Curl")
        XCTAssertNotEqual(resolved("Seated Calf Raise (Machine)"), "Standing Calf Raise")
        XCTAssertNotEqual(resolved("Pull Up (Assisted)"), "Pull-Up", "Assisted loads are a different number")
        XCTAssertNil(resolved("Zercher Squat (Barbell)"))
        XCTAssertNil(resolved("Underwater Basket Weaving"))
        XCTAssertNil(resolved(""))
    }

    func testEquipmentWrittenInTheFileIsRespected() {
        XCTAssertNotEqual(resolved("Bicep Curl (Dumbbell)"), "Barbell Curl")
        XCTAssertNotEqual(resolved("Bench Press (Dumbbell)"), "Barbell Bench Press")
        XCTAssertNotEqual(resolved("Row (Dumbbell)"), "Barbell Row")
    }

    func testExactNameWinsEvenForAnEarlierCustomExercise() {
        var withCustom = library
        let custom = ExerciseMatcher.Candidate(id: UUID(), name: "Bench Press (Barbell)")
        withCustom.append(custom)
        XCTAssertEqual(ImportedExerciseResolver.resolve("Bench Press (Barbell)", in: withCustom)?.id, custom.id)
    }

    func testSplitEquipmentSuffix() {
        XCTAssertEqual(ImportedExerciseResolver.splitEquipmentSuffix("Bench Press (Barbell)").base, "Bench Press")
        XCTAssertEqual(ImportedExerciseResolver.splitEquipmentSuffix("Bench Press (Barbell)").parenthetical, "Barbell")
        XCTAssertEqual(ImportedExerciseResolver.splitEquipmentSuffix("Plank").parenthetical, "")
    }

    func testCustomExercisesGetASensibleMuscleGroup() {
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Cable Crossover Press").muscleGroup, .chest)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Preacher Curl (Machine)").muscleGroup, .biceps)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Preacher Curl (Machine)").equipment, .machine)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Zercher Squat (Barbell)").muscleGroup, .quads)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Zercher Squat (Barbell)").movementPattern, .squat)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Zercher Squat (Barbell)").isCompound, true)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Lying Leg Curl (Machine)").muscleGroup, .hamstrings)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Seated Calf Raise").muscleGroup, .calves)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Triceps Extension (Cable)").muscleGroup, .triceps)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Ab Crunch Machine").muscleGroup, .core)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Crunch").muscleGroup, .core, "'crunch' is not 'run'")
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Skull Crusher (EZ Bar)").muscleGroup, .triceps)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Chest Supported Row (Machine)").muscleGroup, .back)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Pull Up (Weighted)").equipment, .bodyweight)
        XCTAssertEqual(ImportedExerciseResolver.traits(for: "Mystery Thing").muscleGroup, .fullBody)
    }
}
