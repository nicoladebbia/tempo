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

    // MARK: - Weekly-upload feature — cadence persists through save

    func testCadenceDefaultsToBlockWhenNotPassed() throws {
        let context = try makeContext()
        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "Squat")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )
        XCTAssertEqual(program.cadence, .block)
    }

    func testWeeklyCadencePersists() throws {
        let context = try makeContext()
        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "Squat")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context,
            cadence: .weekly
        )
        XCTAssertEqual(program.cadence, .weekly)
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

    // MARK: - Equipment variants (fix #10)

    /// "KT Lat Step Up" matches the library's dumbbell "Step-Up" on
    /// movement, but the trainer wrote kettlebell — a different variant
    /// exercise, cloned from the match, must be created and linked instead
    /// of silently reusing the dumbbell row's equipment/increments.
    func testCreatesEquipmentVariantWhenTrainerEquipmentConflictsWithMatch() throws {
        let context = try makeContext()
        let stepUp = Exercise(
            name: "Step-Up", muscleGroup: .quads, secondaryMuscles: [.glutes],
            equipment: .dumbbell, movementPattern: .lunge, isCompound: true,
            instructions: "Step onto elevated platform.", cues: ["Control the descent"]
        )
        context.insert(stepUp)
        try context.save()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "KT Lat Step Up")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let all = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(all.count, 2, "the dumbbell Step-Up plus one new kettlebell variant")

        let resolvedID = try XCTUnwrap(program.weeks[0].days[0].exercises[0].exerciseID)
        XCTAssertNotEqual(resolvedID, stepUp.id, "linked to the variant, not the dumbbell row")

        let variant = try XCTUnwrap(all.first { $0.id == resolvedID })
        XCTAssertEqual(variant.name, "Kettlebell Lateral Step-Up")
        XCTAssertEqual(variant.equipment, .kettlebell)
        XCTAssertTrue(variant.isCustom)
        XCTAssertEqual(variant.muscleGroup, .quads, "cloned muscle group")
        XCTAssertEqual(variant.secondaryMuscles, [.glutes], "cloned secondary muscles")
        XCTAssertEqual(variant.movementPattern, .lunge, "cloned movement pattern")
        XCTAssertTrue(variant.isCompound, "cloned compound flag")
        XCTAssertEqual(variant.instructions, "Step onto elevated platform.", "cloned instructions")
        XCTAssertEqual(variant.cues, ["Control the descent"], "cloned cues")
    }

    /// No extra qualifier words beyond the matched name -> just "<Equipment>
    /// <Matched Name>", not a doubled-up name.
    func testVariantNameHasNoExtraWordsWhenNoneAreNeeded() throws {
        let context = try makeContext()
        context.insert(Exercise(
            name: "Reverse Lunge",
            muscleGroup: .quads,
            equipment: .dumbbell,
            movementPattern: .lunge,
            isCompound: true
        ))
        try context.save()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "KT Reverse Lunge")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let resolvedID = try XCTUnwrap(program.weeks[0].days[0].exercises[0].exerciseID)
        let variant = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == resolvedID })
        XCTAssertEqual(variant.name, "Kettlebell Reverse Lunge")
    }

    /// A repeated qualifier word ("single leg") carries through, and a
    /// SECOND, differently-worded occurrence that derives the SAME variant
    /// name (so the raw-name cache alone can't be what's deduping it)
    /// dedupes onto that one variant instead of creating a second.
    func testVariantWithQualifierWordsDedupedAcrossDays() throws {
        let context = try makeContext()
        context.insert(Exercise(
            name: "Romanian Deadlift",
            muscleGroup: .hamstrings,
            equipment: .barbell,
            movementPattern: .hinge,
            isCompound: true
        ))
        try context.save()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "KT SL RDL")], notes: nil),
                ProgramDay(weekday: 3, title: nil, focus: nil, exercises: [exercise(named: "Kettlebell Single Leg RDL")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let all = try context.fetch(FetchDescriptor<Exercise>())
        let variants = all.filter(\.isCustom)
        XCTAssertEqual(variants.count, 1, "same variant across two days -> created once")
        XCTAssertEqual(variants.first?.name, "Kettlebell Single Leg Romanian Deadlift")

        let day1ID = program.weeks[0].days[0].exercises[0].exerciseID
        let day2ID = program.weeks[0].days[1].exercises[0].exerciseID
        XCTAssertEqual(day1ID, day2ID)
    }

    /// The trainer wrote the SAME equipment the library row already uses —
    /// no variant, reuse the existing row.
    func testNoVariantWhenWrittenEquipmentMatchesLibraryRow() throws {
        let context = try makeContext()
        let stepUp = Exercise(name: "Step-Up", muscleGroup: .quads, equipment: .dumbbell, movementPattern: .lunge, isCompound: true)
        context.insert(stepUp)
        try context.save()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "DB Step Up")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let all = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(all.count, 1, "no variant created — the trainer's equipment already matches")
        XCTAssertEqual(program.weeks[0].days[0].exercises[0].exerciseID, stepUp.id)
    }

    /// The trainer's shorthand names no equipment at all — nothing to
    /// conflict with, so the plain library match is used as-is.
    func testNoVariantWhenNoEquipmentIsWritten() throws {
        let context = try makeContext()
        let stepUp = Exercise(name: "Step-Up", muscleGroup: .quads, equipment: .dumbbell, movementPattern: .lunge, isCompound: true)
        context.insert(stepUp)
        try context.save()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "Step Up")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let all = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(all.count, 1, "no equipment named -> no variant")
        XCTAssertEqual(program.weeks[0].days[0].exercises[0].exerciseID, stepUp.id)
    }

    /// A wholly unmatched exercise (no library row at all) still picks up
    /// the trainer's written equipment on the new custom Exercise instead of
    /// the old hardcoded `.none`.
    func testUnmatchedCustomExerciseCarriesWrittenEquipment() throws {
        let context = try makeContext()

        let program = try TrainerProgramSaver.save(
            name: "P",
            startDate: Date(),
            weeks: [ProgramWeek(days: [
                ProgramDay(weekday: 1, title: nil, focus: nil, exercises: [exercise(named: "KT Turkish Get Up Complex XYZ")], notes: nil),
            ])],
            repeats: true,
            sourceKind: "text",
            sourceText: nil,
            modelContext: context
        )

        let resolvedID = try XCTUnwrap(program.weeks[0].days[0].exercises[0].exerciseID)
        let custom = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == resolvedID })
        XCTAssertTrue(custom.isCustom)
        XCTAssertEqual(custom.equipment, .kettlebell)
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
