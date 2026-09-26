//
// ExerciseImageSlugTests.swift
// Tempo
//
// Shared test vectors with the backend counterpart
// (tempo-backend/Tests/AppTests/ExerciseImageSlugTests.swift) — keep both
// files' vectors identical. Backend and iOS MUST derive the same slug for
// the same exercise name or the app 404s against an image generated under a
// different key.
//

@testable import Tempo
import XCTest

final class ExerciseImageSlugTests: XCTestCase {
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

    func testMatchesExpectedSlugs() {
        for (input, expected) in Self.vectors {
            XCTAssertEqual(ExerciseImageSlug.make(from: input), expected, "input: \(input)")
        }
    }

    func testIsDeterministic() {
        let name = "Barbell Back Squat"
        XCTAssertEqual(ExerciseImageSlug.make(from: name), ExerciseImageSlug.make(from: name))
    }

    func testNeverStartsOrEndsWithHyphen() {
        for (input, _) in Self.vectors {
            let slug = ExerciseImageSlug.make(from: input)
            XCTAssertFalse(slug.hasPrefix("-"))
            XCTAssertFalse(slug.hasSuffix("-"))
        }
    }
}
