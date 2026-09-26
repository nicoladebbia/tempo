@testable import App
import Testing

@Suite("ExerciseImagePrompt")
struct ExerciseImagePromptTests {
    @Test func includesNameEquipmentAndMuscleGroup() {
        let prompt = ExerciseImagePrompt.build(
            name: "Barbell Back Squat",
            equipment: "barbell",
            muscleGroup: "quads"
        )
        #expect(prompt.contains("Barbell Back Squat"))
        #expect(prompt.contains("barbell"))
        #expect(prompt.contains("quads"))
        #expect(prompt.contains("no text, no logos, no watermark"))
    }

    @Test func bodyweightEquipmentReadsAsNoEquipment() {
        let prompt = ExerciseImagePrompt.build(name: "Push-Up", equipment: "bodyweight", muscleGroup: "chest")
        #expect(prompt.contains("no equipment (bodyweight only)"))
    }

    @Test func humanizesUnderscoredMuscleGroup() {
        let prompt = ExerciseImagePrompt.build(name: "Plank", equipment: "bodyweight", muscleGroup: "full_body")
        #expect(prompt.contains("full body"))
        #expect(!prompt.contains("full_body"))
    }

    @Test func appendsMovementPatternWhenPresent() {
        let prompt = ExerciseImagePrompt.build(
            name: "Barbell Row",
            equipment: "barbell",
            muscleGroup: "back",
            movementPattern: "horizontal_pull"
        )
        #expect(prompt.contains("Movement pattern: horizontal pull."))
    }

    @Test func usesFirstInstructionLineForDisambiguation() {
        let prompt = ExerciseImagePrompt.build(
            name: "Barbell Bench Press",
            equipment: "barbell",
            muscleGroup: "chest",
            instructions: "1. Lie on the bench with eyes under the bar.\n2. Grip the bar."
        )
        #expect(prompt.contains("Movement detail: Lie on the bench with eyes under the bar."))
        #expect(!prompt.contains("1."))
    }

    @Test func isDeterministic() {
        let a = ExerciseImagePrompt.build(name: "Deadlift", equipment: "barbell", muscleGroup: "back")
        let b = ExerciseImagePrompt.build(name: "Deadlift", equipment: "barbell", muscleGroup: "back")
        #expect(a == b)
    }

    @Test func handlesNilOptionalFields() {
        let prompt = ExerciseImagePrompt.build(
            name: "Jumping Jack",
            equipment: "bodyweight",
            muscleGroup: "cardio",
            movementPattern: nil,
            instructions: nil
        )
        #expect(!prompt.contains("Movement pattern:"))
        #expect(!prompt.contains("Movement detail:"))
    }
}
