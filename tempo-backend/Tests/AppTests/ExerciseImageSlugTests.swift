@testable import App
import Testing

// MARK: - ExerciseImageSlug

//
// Shared test vectors with the iOS counterpart
// (TempoTests/ExerciseImageSlugTests.swift) — keep both files' `vectors`
// array identical. Backend and iOS MUST derive the same slug for the same
// exercise name or the app will 404 against an image generated under a
// different key.

@Suite("ExerciseImageSlug")
struct ExerciseImageSlugTests {
    /// (input, expected slug)
    static let vectors: [(String, String)] = [
        ("Barbell Back Squat", "barbell-back-squat"),
        ("Kettlebell Lateral Step-Up", "kettlebell-lateral-step-up"),
        ("Barbell Bench Press", "barbell-bench-press"),
        ("  Leading and trailing spaces  ", "leading-and-trailing-spaces"),
        ("Multiple   Internal    Spaces", "multiple-internal-spaces"),
        ("Ünïcode Nâme", "unicode-name"),
        ("Push-Up (Wide Grip)", "push-up-wide-grip"),
        ("90/90 Hip Switch", "90-90-hip-switch"),
        ("A", "a"),
        ("", ""),
        ("!!!", ""),
        ("Single-Arm Dumbbell Row", "single-arm-dumbbell-row"),
    ]

    @Test func matchesExpectedSlugs() {
        for (input, expected) in Self.vectors {
            #expect(ExerciseImageSlug.make(from: input) == expected, "input: \(input)")
        }
    }

    @Test func isDeterministic() {
        let name = "Barbell Back Squat"
        #expect(ExerciseImageSlug.make(from: name) == ExerciseImageSlug.make(from: name))
    }

    @Test func neverStartsOrEndsWithHyphen() {
        for (input, _) in Self.vectors {
            let slug = ExerciseImageSlug.make(from: input)
            #expect(!slug.hasPrefix("-"))
            #expect(!slug.hasSuffix("-"))
        }
    }
}
