//
// ExerciseResearchTests.swift
// Tempo
//
// New-exercise research for Trainer Program import: the parser tolerates
// fences and unknown enum values, the store batches, dedupes, keeps user
// edits and reports failures, and TrainerProgramSaver builds the new library
// Exercise from the research (trainer-written equipment still wins).
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - ExerciseResearchTests

@MainActor
final class ExerciseResearchTests: XCTestCase {
    // MARK: - Parser

    private let sampleJSON = """
    ```json
    {"exercises":[
      {"input":"Panca Larsen","muscle_group":"chest","secondary_muscles":["triceps","chest","wings"],
       "equipment":"barbell","movement_pattern":"horizontal_push","is_compound":true,
       "instructions":"Lie on a bench with feet off the floor. Press the bar.","cues":["Stay tight"," ","Drive up"]},
      {"input":"Mystery Move","muscle_group":"gills","equipment":"spaceship","movement_pattern":"warp"}
    ]}
    ```
    """

    func testParserReadsFencedJSONKeyedByNormalizedName() throws {
        let result = try ExerciseResearchParser.parse(sampleJSON)
        let larsen = try XCTUnwrap(result[ExerciseMatcher.normalize("Panca Larsen")])
        XCTAssertEqual(larsen.muscleGroup, .chest)
        XCTAssertEqual(larsen.secondaryMuscles, [.triceps], "Unknown and primary muscles are dropped")
        XCTAssertEqual(larsen.equipment, .barbell)
        XCTAssertEqual(larsen.movementPattern, .horizontalPush)
        XCTAssertTrue(larsen.isCompound)
        XCTAssertEqual(larsen.cues, ["Stay tight", "Drive up"])
        XCTAssertEqual(larsen.summary, "Chest · Barbell · Horizontal Push")
    }

    func testParserFallsBackOnUnknownEnumValues() throws {
        let result = try ExerciseResearchParser.parse(sampleJSON)
        let mystery = try XCTUnwrap(result[ExerciseMatcher.normalize("Mystery Move")])
        XCTAssertEqual(mystery.muscleGroup, .fullBody)
        XCTAssertEqual(mystery.equipment, Equipment.none)
        XCTAssertEqual(mystery.movementPattern, .isolation)
        XCTAssertFalse(mystery.isCompound)
    }

    func testParserRejectsNonJSON() {
        XCTAssertThrowsError(try ExerciseResearchParser.parse("Sorry, I can't help")) { error in
            XCTAssertEqual(error as? ExerciseResearchParser.ParseError, .noJSON)
        }
    }

    // MARK: - Store

    private final class FakeProvider: ExerciseResearchProviding, @unchecked Sendable {
        var calls: [[String]] = []
        var sessions: [String] = []
        var error: Error?
        var delay: Duration?

        func research(names: [String], sessionID: String) async throws -> [String: ExerciseResearch] {
            calls.append(names)
            sessions.append(sessionID)
            if let delay {
                try await Task.sleep(for: delay)
            }
            if let error {
                throw error
            }
            var out: [String: ExerciseResearch] = [:]
            for name in names where name != "Unknowable" {
                out[ExerciseMatcher.normalize(name)] = .sample
            }
            return out
        }
    }

    func testStoreResearchesOnceAndDedupes() async {
        let provider = FakeProvider()
        let store = ExerciseResearchStore(provider: provider, importSessionID: "import-1")
        XCTAssertTrue(store.isAutomatic)

        await store.research(names: ["Panca Larsen", "panca larsen", "Unknowable"], sessionID: "import-1")
        await store.research(names: ["Panca Larsen"], sessionID: "import-1")

        XCTAssertEqual(provider.calls, [["Panca Larsen", "Unknowable"]], "Duplicate and already-done names aren't re-sent")
        XCTAssertEqual(store.state(for: "Panca Larsen"), .done(.sample))
        XCTAssertEqual(store.state(for: "Unknowable"), .failed("Couldn't identify this exercise"))
        XCTAssertEqual(store.results.count, 1)
    }

    func testStoreBatchesLongLists() async {
        let provider = FakeProvider()
        let store = ExerciseResearchStore(provider: provider, importSessionID: "import-1")
        let names = (1 ... 25).map { "Move \($0)" }
        await store.research(names: names, sessionID: "import-1")
        XCTAssertEqual(provider.calls.map(\.count), [20, 5])
        XCTAssertEqual(store.results.count, 25)
    }

    func testSignedOutFailureSaysSignIn() async {
        let provider = FakeProvider()
        provider.error = APIError.unauthorized
        let store = ExerciseResearchStore(provider: provider, importSessionID: "import-1")
        await store.research(names: ["Panca Larsen"], sessionID: "import-1")
        XCTAssertEqual(store.state(for: "Panca Larsen"), .failed("Sign in to look up new exercises"))
    }

    func testCancelledLookupIsRetriedAutomatically() async {
        let provider = FakeProvider()
        provider.delay = .seconds(10)
        let store = ExerciseResearchStore(provider: provider, importSessionID: "import-1")
        let task = Task { await store.research(names: ["Panca Larsen", "Hip Airplane"], sessionID: "import-1") }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value
        XCTAssertNil(store.state(for: "Panca Larsen"), "A cancelled batch isn't a failure")

        provider.delay = nil
        await store.research(names: ["Panca Larsen", "Hip Airplane"], sessionID: "import-1")
        XCTAssertEqual(store.state(for: "Panca Larsen"), .done(.sample))
        XCTAssertEqual(provider.calls.count, 2)
    }

    func testEditModeIsManualAndReusesOneSession() async {
        let provider = FakeProvider()
        let store = ExerciseResearchStore(provider: provider, importSessionID: nil)
        XCTAssertFalse(store.isAutomatic)
        await store.lookUp("Panca Larsen")
        await store.lookUp("Hip Airplane")
        XCTAssertEqual(provider.sessions.count, 2)
        XCTAssertEqual(Set(provider.sessions).count, 1, "Manual lookups share one quota session")
    }

    func testUserEditReplacesResearch() async {
        let store = ExerciseResearchStore(provider: FakeProvider(), importSessionID: "import-1")
        await store.research(names: ["Panca Larsen"], sessionID: "import-1")
        var edited = ExerciseResearch.sample
        edited.muscleGroup = .triceps
        store.update(edited, for: "PANCA LARSEN")
        XCTAssertEqual(store.results[ExerciseMatcher.normalize("Panca Larsen")]?.muscleGroup, .triceps)
    }

    // MARK: - Saver

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TrainerProgram.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            ExerciseHistory.self,
            PersonalRecord.self,
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func program(_ names: [String]) -> [ProgramWeek] {
        [ProgramWeek(days: [
            ProgramDay(
                weekday: 1, title: nil, focus: nil,
                exercises: names.map {
                    ProgramExercise(
                        name: $0, exerciseID: nil, sets: 3, repsLow: 8, repsHigh: nil,
                        weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, notes: nil
                    )
                },
                notes: nil
            ),
        ])]
    }

    func testSaverCreatesNewExerciseFromResearch() throws {
        let context = try makeContext()
        let key = ExerciseMatcher.normalize("Panca Larsen")
        try TrainerProgramSaver.save(
            name: "P", startDate: Date(), weeks: program(["Panca Larsen"]), repeats: true,
            sourceKind: "text", sourceText: nil, modelContext: context,
            research: [key: .sample]
        )
        let created = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Panca Larsen" })
        XCTAssertTrue(created.isCustom)
        XCTAssertEqual(created.muscleGroup, .chest)
        XCTAssertEqual(created.secondaryMuscles, [.triceps])
        XCTAssertEqual(created.equipment, .barbell)
        XCTAssertEqual(created.movementPattern, .horizontalPush)
        XCTAssertTrue(created.isCompound)
        XCTAssertEqual(created.instructions, ExerciseResearch.sample.instructions)
        XCTAssertEqual(created.cues, ExerciseResearch.sample.cues)
    }

    func testTrainerWrittenEquipmentBeatsResearch() throws {
        let context = try makeContext()
        let name = "KB Panca Larsen"
        try TrainerProgramSaver.save(
            name: "P", startDate: Date(), weeks: program([name]), repeats: true,
            sourceKind: "text", sourceText: nil, modelContext: context,
            research: [ExerciseMatcher.normalize(name): .sample]
        )
        let created = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.name == name })
        XCTAssertEqual(created.equipment, .kettlebell)
        XCTAssertEqual(created.muscleGroup, .chest)
    }

    func testNoResearchKeepsBareCustomExercise() throws {
        let context = try makeContext()
        try TrainerProgramSaver.save(
            name: "P", startDate: Date(), weeks: program(["Panca Larsen"]), repeats: true,
            sourceKind: "text", sourceText: nil, modelContext: context
        )
        let created = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Panca Larsen" })
        XCTAssertEqual(created.muscleGroup, .fullBody)
        XCTAssertNil(created.instructions)
    }
}

extension ExerciseResearch {
    static let sample = ExerciseResearch(
        muscleGroup: .chest,
        secondaryMuscles: [.triceps],
        equipment: .barbell,
        movementPattern: .horizontalPush,
        isCompound: true,
        instructions: "Lie on a bench with feet off the floor. Press the bar.",
        cues: ["Stay tight", "Drive up"]
    )
}
