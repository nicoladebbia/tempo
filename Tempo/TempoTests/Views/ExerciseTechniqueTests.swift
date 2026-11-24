//
// ExerciseTechniqueTests.swift
// Tempo
//
// The bundled form guide: every lift it covers must be a real library
// exercise (the guide is matched by name), every entry must be the right size
// and written cleanly, and lookups must ignore case and spacing.
//

@testable import Tempo
import XCTest

final class ExerciseTechniqueTests: XCTestCase {
    private func libraryNames() throws -> Set<String> {
        let url = try XCTUnwrap(
            (Bundle.allBundles + Bundle.allFrameworks).compactMap {
                $0.url(forResource: "Exercises", withExtension: "json")
            }.first,
            "Exercises.json is not in any loaded bundle"
        )
        let data = try Data(contentsOf: url)
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return Set(rows.compactMap { $0["name"] as? String })
    }

    func testEveryCoveredLiftIsARealLibraryExercise() throws {
        let library = try libraryNames()
        XCTAssertGreaterThan(library.count, 100)
        for name in ExerciseTechniqueLibrary.coveredNames {
            XCTAssertTrue(library.contains(name), "\"\(name)\" is not in Exercises.json, so no exercise would ever match it")
        }
    }

    func testTheGuideCoversTheCommonLifts() {
        let covered = Set(ExerciseTechniqueLibrary.coveredNames)
        let essentials = [
            "Barbell Bench Press", "Barbell Back Squat", "Conventional Deadlift", "Overhead Press",
            "Barbell Row", "Pull-Up", "Lat Pulldown", "Romanian Deadlift", "Hip Thrust", "Barbell Curl",
        ]
        for name in essentials {
            XCTAssertTrue(covered.contains(name), "\(name) is missing from the form guide")
        }
        XCTAssertGreaterThanOrEqual(covered.count, 30)
    }

    func testNoLiftIsListedTwice() {
        let names = ExerciseTechniqueLibrary.coveredNames.map { $0.lowercased() }
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testEveryEntryHasTwoOrThreeCuesAndTwoOrThreeMistakes() {
        for name in ExerciseTechniqueLibrary.coveredNames {
            guard let technique = ExerciseTechniqueLibrary.technique(forName: name) else {
                XCTFail("\(name) is listed but cannot be looked up")
                continue
            }
            XCTAssertTrue((2 ... 3).contains(technique.cues.count), "\(name): \(technique.cues.count) cues")
            XCTAssertTrue((2 ... 3).contains(technique.mistakes.count), "\(name): \(technique.mistakes.count) mistakes")
        }
    }

    func testEveryLineIsShortPlainAndDistinct() {
        for name in ExerciseTechniqueLibrary.coveredNames {
            let technique = ExerciseTechniqueLibrary.technique(forName: name)
            let lines = (technique?.cues ?? []) + (technique?.mistakes ?? [])
            XCTAssertEqual(lines.count, Set(lines).count, "\(name) repeats a line")
            for line in lines {
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, "\(name) has an empty line")
                XCTAssertLessThanOrEqual(line.count, 70, "\"\(line)\" is too long to read between sets")
                XCTAssertFalse(line.hasSuffix("."), "\"\(line)\" should not end with a full stop")
                XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), "\"\(line)\" has a long dash")
                XCTAssertEqual(line, line.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    func testLookupIgnoresCaseAndSpacing() {
        let exact = ExerciseTechniqueLibrary.technique(forName: "Barbell Bench Press")
        XCTAssertNotNil(exact)
        XCTAssertEqual(ExerciseTechniqueLibrary.technique(forName: "  barbell bench press "), exact)
        XCTAssertEqual(ExerciseTechniqueLibrary.technique(forName: "BARBELL BENCH PRESS"), exact)
    }

    func testALiftOutsideTheGuideHasNoTechnique() {
        XCTAssertNil(ExerciseTechniqueLibrary.technique(forName: "Turkish Get-Up Variation Nobody Teaches"))
        XCTAssertNil(ExerciseTechniqueLibrary.technique(forName: ""))
    }

    func testLookupByExerciseUsesItsName() {
        let squat = Exercise(
            name: "Barbell Back Squat",
            muscleGroup: .quads,
            equipment: .barbell,
            movementPattern: .squat,
            isCompound: true
        )
        XCTAssertEqual(ExerciseTechniqueLibrary.technique(for: squat)?.cues.first, "Big breath and brace before every rep")
        let custom = Exercise(
            name: "My Cable Thing",
            muscleGroup: .back,
            equipment: .cable,
            movementPattern: .horizontalPull,
            isCompound: false
        )
        XCTAssertNil(ExerciseTechniqueLibrary.technique(for: custom))
    }
}
