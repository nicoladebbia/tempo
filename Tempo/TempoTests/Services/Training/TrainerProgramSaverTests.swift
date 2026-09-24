//
// TrainerProgramSaverTests.swift
// Tempo
//
// Pins the save-time contract: only one TrainerProgram is ever active,
// exercises matched against the library keep their existing Exercise
// (no duplicate), and an unmatched exercise repeated across days/weeks
// creates exactly ONE custom Exercise, not one per occurrence.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainerProgramSaverTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TrainerProgram.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            ExerciseHistory.self,
            PersonalRecord.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func exercise(named name: String, sets: Int = 3, repsLow: Int = 10) -> ProgramExercise {
        ProgramExercise(
            name: name, exerciseID: nil, sets: sets, repsLow: repsLow, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, notes: nil
        )
    }

    // MARK: - Only one active program

    func testSavingDeactivatesAnyExistingActiveProgram() throws {
        let context = try makeContext()
        let old = TrainerProgram(
            name: "Old", startDate: Date(), weeks: [ProgramWeek(days: [])],
            isActive: true, sourceKind: "text"
        )
        context.insert(old)
        try context.save()

        let newProgram = try TrainerProgramSaver.save(
            name: "New",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "Squat")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        XCTAssertFalse(old.isActive)
        XCTAssertTrue(newProgram.isActive)

        let all = try context.fetch(FetchDescriptor<TrainerProgram>())
        XCTAssertEqual(all.filter(\.isActive).count, 1)
    }

    // MARK: - Library matching reuses an existing Exercise

    func testMatchedExerciseReusesLibraryRowNoDuplicate() throws {
        let context = try makeContext()
        context.insert(Exercise(
            name: "Barbell Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        ))
        try context.save()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "bench press")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(allExercises.count, 1, "no duplicate created — the alias matched the existing row")
        let resolvedID = program.weeks[0].days[0].exercises[0].exerciseID
        XCTAssertEqual(resolvedID, allExercises.first?.id)
    }

    // MARK: - Unmatched exercise creates exactly one custom Exercise

    func testUnmatchedExerciseRepeatedAcrossDaysCreatesExactlyOneCustom() throws {
        let context = try makeContext()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "Nordic Curl Machine XYZ")], notes: nil),
                ProgramDay(weekday: 3, title: nil, focus: nil, exercises: [exercise(named: "nordic curl machine xyz")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let customExercises = try context.fetch(FetchDescriptor<Exercise>()).filter(\.isCustom)
        XCTAssertEqual(customExercises.count, 1, "same name (case-insensitive) across two days -> one custom exercise")

        let day1ID = program.weeks[0].days[0].exercises[0].exerciseID
        let day2ID = program.weeks[0].days[1].exercises[0].exerciseID
        XCTAssertNotNil(day1ID)
        XCTAssertEqual(day1ID, day2ID)
    }

    // MARK: - A pre-set exerciseID (user picked a match in review) is kept

    func testUserOverriddenMatchIsRespected() throws {
        let context = try makeContext()
        let chosen = Exercise(
            name: "Some Custom Row Variant", muscleGroup: .back, equipment: .cable,
            movementPattern: .horizontalPull, isCompound: false
        )
        context.insert(chosen)
        try context.save()

        var row = exercise(named: "Totally Unrelated Name")
        row.exerciseID = chosen.id

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [row], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        XCTAssertEqual(program.weeks[0].days[0].exercises[0].exerciseID, chosen.id)
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(allExercises.count, 1, "no custom exercise created — the user's pick was honored")
    }

    // MARK: - Activate / deactivate

    func testActivateSwapsWhichProgramIsActive() throws {
        let context = try makeContext()
        let a = TrainerProgram(name: "A", startDate: Date(), weeks: [ProgramWeek(days: [])], isActive: true, sourceKind: "text")
        let b = TrainerProgram(name: "B", startDate: Date(), weeks: [ProgramWeek(days: [])], isActive: false, sourceKind: "text")
        context.insert(a)
        context.insert(b)
        try context.save()

        TrainerProgramSaver.activate(b, modelContext: context)

        XCTAssertFalse(a.isActive)
        XCTAssertTrue(b.isActive)
    }
}
