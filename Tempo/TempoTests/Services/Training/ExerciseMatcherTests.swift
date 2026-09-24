//
// ExerciseMatcherTests.swift
// Tempo
//
// Pins trainer-sheet exercise-name matching: exact (case/diacritic
// insensitive), the English/Italian alias table, the token-overlap fallback,
// and the "no match -> nil" contract that lets the saver fall back to
// creating a custom exercise.
//

@testable import Tempo
import XCTest

final class ExerciseMatcherTests: XCTestCase {
    private let library: [ExerciseMatcher.Candidate] = [
        .init(id: UUID(), name: "Barbell Bench Press"),
        .init(id: UUID(), name: "Incline Dumbbell Press"),
        .init(id: UUID(), name: "Romanian Deadlift"),
        .init(id: UUID(), name: "Conventional Deadlift"),
        .init(id: UUID(), name: "Lat Pulldown"),
        .init(id: UUID(), name: "Pull-Up"),
        .init(id: UUID(), name: "Barbell Back Squat"),
    ]

    private func name(_ candidate: ExerciseMatcher.Candidate?) -> String? {
        candidate?.name
    }

    // MARK: - Exact match

    func testExactCaseInsensitiveMatch() {
        XCTAssertEqual(name(ExerciseMatcher.match("barbell bench press", in: library)), "Barbell Bench Press")
        XCTAssertEqual(name(ExerciseMatcher.match("BARBELL BENCH PRESS", in: library)), "Barbell Bench Press")
    }

    func testDiacriticInsensitiveMatch() {
        let libraryWithAccent: [ExerciseMatcher.Candidate] = [.init(id: UUID(), name: "Stacchi Rumeni")]
        XCTAssertEqual(name(ExerciseMatcher.match("stacchi rumeni", in: libraryWithAccent)), "Stacchi Rumeni")
    }

    // MARK: - Alias table

    func testEnglishAliases() {
        XCTAssertEqual(name(ExerciseMatcher.match("bench", in: library)), "Barbell Bench Press")
        XCTAssertEqual(name(ExerciseMatcher.match("Bench Press", in: library)), "Barbell Bench Press")
        XCTAssertEqual(name(ExerciseMatcher.match("RDL", in: library)), "Romanian Deadlift")
        XCTAssertEqual(name(ExerciseMatcher.match("lat pulldown", in: library)), "Lat Pulldown")
        XCTAssertEqual(name(ExerciseMatcher.match("deadlift", in: library)), "Conventional Deadlift")
        XCTAssertEqual(name(ExerciseMatcher.match("squat", in: library)), "Barbell Back Squat")
        XCTAssertEqual(name(ExerciseMatcher.match("pull up", in: library)), "Pull-Up")
    }

    func testItalianAliases() {
        XCTAssertEqual(name(ExerciseMatcher.match("panca piana", in: library)), "Barbell Bench Press")
        XCTAssertEqual(name(ExerciseMatcher.match("stacchi", in: library)), "Conventional Deadlift")
        XCTAssertEqual(name(ExerciseMatcher.match("stacco rumeno", in: library)), "Romanian Deadlift")
        XCTAssertEqual(name(ExerciseMatcher.match("trazioni", in: library)), "Pull-Up")
    }

    // MARK: - Token-overlap fallback

    func testTokenOverlapFallbackMatchesPartialName() {
        // "Incline Dumbbell" shares 2/2 query tokens with "Incline Dumbbell
        // Press" and 0 with everything else.
        XCTAssertEqual(name(ExerciseMatcher.match("Incline Dumbbell", in: library)), "Incline Dumbbell Press")
    }

    // MARK: - No match -> nil (caller creates custom)

    func testUnrelatedNameReturnsNil() {
        XCTAssertNil(ExerciseMatcher.match("Bulgarian Nose Flute Press", in: library))
    }

    /// Regression: a 2-token query sharing only one generic word ("press")
    /// with a candidate must NOT match — that used to hit the old 0.5
    /// threshold (1/2 tokens) and silently mis-map "band press" onto
    /// "Overhead Press".
    func testShortQuerySharingOnlyOneGenericTokenDoesNotMatch() {
        let libraryWithOverheadPress: [ExerciseMatcher.Candidate] = [
            .init(id: UUID(), name: "Overhead Press"),
        ]
        XCTAssertNil(ExerciseMatcher.match("band press", in: libraryWithOverheadPress))
    }

    func testEmptyNameReturnsNil() {
        XCTAssertNil(ExerciseMatcher.match("   ", in: library))
    }

    func testEmptyLibraryReturnsNil() {
        XCTAssertNil(ExerciseMatcher.match("bench", in: []))
    }
}
