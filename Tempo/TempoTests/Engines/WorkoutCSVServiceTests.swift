//
// WorkoutCSVServiceTests.swift
// Tempo
//
// §20 — pins the CSV import/export system: Strong and Hevy header
// detection, warmup/rest-row skipping, exercise matching vs custom
// creation, ExerciseHistory generation, idempotent re-import, and — the
// load-bearing one — a full export→import round-trip (the wire format must
// survive its own output, not just hand-built specimens).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WorkoutCSVServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            ExerciseHistory.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private let strongCSV = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2026-07-20 18:00:00,Push Day,1h 5m,Bench Press,W1,40,8,,,,,
    2026-07-20 18:00:00,Push Day,1h 5m,Bench Press,1,80,8,,,,,8
    2026-07-20 18:00:00,Push Day,1h 5m,Bench Press,2,82.5,6,,,,,9
    2026-07-20 18:00:00,Push Day,1h 5m,"Press, Overhead",1,50,10,,,,,
    2026-07-22 18:30:00,Pull Day,45m,Barbell Row,1,60,10,,,,,
    """

    private let hevyCSV = """
    title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
    Leg Day,"20 Jul 2026, 18:00","20 Jul 2026, 19:00",,Squat,,,0,warmup,60,5,,,
    Leg Day,"20 Jul 2026, 18:00","20 Jul 2026, 19:00",,Squat,,,1,normal,100,5,,,9
    """

    // MARK: - Parsing

    func testStrongParseSkipsWarmupsAndInfersFormat() throws {
        let parsed = try WorkoutCSVService.parse(strongCSV)
        let (format, sets) = (parsed.format, parsed.sets)
        XCTAssertEqual(format, .strong)
        XCTAssertEqual(sets.count, 4, "W1 warmup row is dropped")
        XCTAssertEqual(sets.filter { $0.exercise == "Press, Overhead" }.count, 1,
                       "Quoted field with comma survives parsing")
        XCTAssertEqual(sets.first?.durationMinutes, 65, "1h 5m → 65 minutes")
        XCTAssertEqual(sets.first?.rpe, 8)
    }

    func testUnrecognizedHeaderThrows() {
        XCTAssertThrowsError(try WorkoutCSVService.parse("foo,bar\n1,2\n"))
    }

    func testTypeInference() {
        XCTAssertEqual(WorkoutCSVService.inferType(from: "Push Day"), .push)
        XCTAssertEqual(WorkoutCSVService.inferType(from: "LEGS + core"), .legs)
        XCTAssertEqual(WorkoutCSVService.inferType(from: "Morning Session"), .fullBody)
    }

    // MARK: - Import

    func testStrongImportCreatesPlansSetsAndHistory() throws {
        let context = try makeContext()
        // Pre-existing library exercise — matched case-insensitively, no dupe.
        context.insert(Exercise(name: "bench press", muscleGroup: .chest,
                                equipment: .barbell, movementPattern: .horizontalPush,
                                isCompound: true))
        try context.save()

        let summary = try WorkoutCSVService.importCSV(strongCSV, modelContext: context)

        XCTAssertEqual(summary.workouts, 2)
        XCTAssertEqual(summary.sets, 4)
        XCTAssertEqual(summary.newExercises, 2, "Overhead press + row created custom; bench matched")

        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>(sortBy: [.init(\.date)]))
        XCTAssertEqual(plans.count, 2)
        let push = plans[0]
        XCTAssertEqual(push.status, .completed)
        XCTAssertEqual(push.type, .push)
        XCTAssertEqual(push.durationMinutes, 65)
        let bench = try XCTUnwrap(push.orderedExercises.first)
        XCTAssertEqual(bench.exercise?.name.lowercased(), "bench press")
        XCTAssertEqual(bench.orderedSets.count, 2)
        XCTAssertEqual(bench.orderedSets[1].actualWeight, 82.5)
        XCTAssertTrue(bench.orderedSets.allSatisfy(\.completed))

        let history = try context.fetch(FetchDescriptor<ExerciseHistory>())
        XCTAssertEqual(history.count, 3, "One trend row per exercise per workout")
        let benchHistory = try XCTUnwrap(history.first { $0.exercise?.name.lowercased() == "bench press" })
        XCTAssertEqual(benchHistory.totalVolume, 80 * 8 + 82.5 * 6)
        XCTAssertEqual(benchHistory.bestSetWeight, 82.5)
        XCTAssertEqual(benchHistory.workoutPlanID, push.id)

        let customs = try context.fetch(FetchDescriptor<Exercise>()).filter(\.isCustom)
        XCTAssertEqual(customs.count, 2)
    }

    func testHevyImportSkipsWarmupsAndMapsColumns() throws {
        let context = try makeContext()
        let summary = try WorkoutCSVService.importCSV(hevyCSV, modelContext: context)

        XCTAssertEqual(summary.format, .hevy)
        XCTAssertEqual(summary.workouts, 1)
        XCTAssertEqual(summary.sets, 1, "Warmup set_type row dropped")
        let plan = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutPlan>()).first)
        XCTAssertEqual(plan.type, .legs)
        XCTAssertEqual(plan.orderedExercises.first?.orderedSets.first?.actualWeight, 100)
    }

    func testReimportIsIdempotent() throws {
        let context = try makeContext()
        _ = try WorkoutCSVService.importCSV(strongCSV, modelContext: context)
        let second = try WorkoutCSVService.importCSV(strongCSV, modelContext: context)

        XCTAssertEqual(second.workouts, 0)
        XCTAssertEqual(second.duplicates, 2, "Both workouts recognized by start time")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutPlan>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseHistory>()), 3)
    }

    // MARK: - Export round-trip

    func testExportRoundTripsThroughImport() throws {
        let source = try makeContext()
        _ = try WorkoutCSVService.importCSV(strongCSV, modelContext: source)
        let plans = try source.fetch(FetchDescriptor<WorkoutPlan>())
        let csv = WorkoutCSVService.exportCSV(plans: plans)

        let destination = try makeContext()
        let summary = try WorkoutCSVService.importCSV(csv, modelContext: destination)

        XCTAssertEqual(summary.format, .strong, "Export is Strong-compatible")
        XCTAssertEqual(summary.workouts, 2)
        XCTAssertEqual(summary.sets, 4, "Every working set survives the round-trip")

        let imported = try destination.fetch(FetchDescriptor<WorkoutPlan>(sortBy: [.init(\.date)]))
        let bench = try XCTUnwrap(imported[0].orderedExercises.first?.orderedSets)
        XCTAssertEqual(bench.map(\.actualWeight), [80, 82.5])
        XCTAssertEqual(bench.map(\.actualReps), [8, 6])
        XCTAssertEqual(bench.compactMap(\.rpe), [8, 9], "RPE survives the round-trip")
    }

    func testExportSkipsIncompletePlans() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan) // .planned — never exported
        XCTAssertEqual(WorkoutCSVService.exportCSV(plans: [plan])
            .split(separator: "\n").count, 1, "Header only")
    }

    // MARK: - Units

    private let strongPounds = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Weight Unit,Reps,RPE,Distance,Distance Unit,Seconds,Notes,Workout Notes,Workout Duration
    2026-07-20 18:00:00,Push Day,1h,Bench Press (Barbell),1,225,lbs,5,,0,,0,,,1h
    2026-07-20 18:00:00,Push Day,1h,Pull Up,1,,lbs,8,,0,,0,,,1h
    """

    private let strongNoUnit = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps
    2026-07-20 18:00:00,Push Day,1h,Bench Press (Barbell),1,225,5
    """

    private func firstWeight(_ context: ModelContext) throws -> Double? {
        try context.fetch(FetchDescriptor<PlannedSet>()).compactMap(\.actualWeight).first
    }

    func testPoundsFileIsConvertedNotReadAsKilos() throws {
        let context = try makeContext()
        let summary = try WorkoutCSVService.importCSV(strongPounds, modelContext: context)
        XCTAssertEqual(try XCTUnwrap(firstWeight(context)), 225 / 2.20462, accuracy: 0.001)
        XCTAssertEqual(summary.unit, .lbs)
        XCTAssertTrue(summary.label.contains("lbs"))
        let sets = try context.fetch(FetchDescriptor<PlannedSet>())
        XCTAssertEqual(sets.filter { $0.actualWeight == nil }.count, 1, "Bodyweight set stays weightless")
    }

    func testUnitPickedByTheUserAppliesWhenFileDoesNotSay() throws {
        let lbs = try makeContext()
        _ = try WorkoutCSVService.importCSV(strongNoUnit, assumedUnit: .lbs, modelContext: lbs)
        XCTAssertEqual(try XCTUnwrap(firstWeight(lbs)), 225 / 2.20462, accuracy: 0.001)

        let kg = try makeContext()
        _ = try WorkoutCSVService.importCSV(strongNoUnit, assumedUnit: .kg, modelContext: kg)
        XCTAssertEqual(try firstWeight(kg), 225)

        let history = try lbs.fetch(FetchDescriptor<ExerciseHistory>())
        XCTAssertEqual(try XCTUnwrap(history.first?.bestSetWeight), 225 / 2.20462, accuracy: 0.001)
    }

    // MARK: - Undo

    func testUndoRemovesOnlyTheImportedBatch() throws {
        let context = try makeContext()
        let library = Exercise(name: "Barbell Row", muscleGroup: .back, equipment: .barbell,
                               movementPattern: .horizontalPull, isCompound: true)
        context.insert(library)
        let live = WorkoutPlan(date: Date(), type: .pull)
        live.status = .completed
        context.insert(live)
        try context.save()

        let summary = try WorkoutCSVService.importCSV(strongCSV, modelContext: context)
        let batch = try XCTUnwrap(summary.batchID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutPlan>()), 3)

        let removed = try WorkoutCSVService.undoImport(batchID: batch, modelContext: context)

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutPlan>()), 1, "Live workout untouched")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseHistory>()), 0)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.map(\.name), ["Barbell Row"], "Custom exercises the import made are removed, library stays")
    }

    func testUndoKeepsACustomExerciseALaterImportReused() throws {
        let context = try makeContext()
        let first = try WorkoutCSVService.importCSV(strongNoUnit, modelContext: context)
        let laterCSV = strongNoUnit.replacingOccurrences(of: "2026-07-20", with: "2026-07-27")
        _ = try WorkoutCSVService.importCSV(laterCSV, modelContext: context)

        try WorkoutCSVService.undoImport(batchID: try XCTUnwrap(first.batchID), modelContext: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutPlan>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1, "Still used by the second import")
    }

    // MARK: - Exercise matching

    func testStrongNameMatchesLibraryExerciseInsteadOfForkingACustomOne() throws {
        let context = try makeContext()
        let library = Exercise(name: "Barbell Bench Press", muscleGroup: .chest, equipment: .barbell,
                               movementPattern: .horizontalPush, isCompound: true)
        context.insert(library)
        try context.save()

        let summary = try WorkoutCSVService.importCSV(strongPounds, modelContext: context)

        XCTAssertEqual(summary.newExercises, 1, "Only Pull Up is new; Bench Press (Barbell) is the library lift")
        XCTAssertEqual(library.history?.count, 1, "History lands on the library exercise")
        XCTAssertEqual(library.plannedExercises?.count, 1)
        let customs = try context.fetch(FetchDescriptor<Exercise>()).filter(\.isCustom)
        XCTAssertEqual(customs.map(\.name), ["Pull Up"])
        XCTAssertEqual(customs.first?.muscleGroup, .back, "Inferred, not Full Body")
        XCTAssertEqual(customs.first?.equipment, .bodyweight)
    }

    func testTwoSpellingsOfOneLiftShareOneExercise() throws {
        let context = try makeContext()
        let csv = """
        Date,Workout Name,Exercise Name,Set Order,Weight,Reps
        2026-07-20 18:00:00,Push,Bench Press (Barbell),1,80,5
        2026-07-22 18:00:00,Push,Barbell Bench Press,1,82.5,5
        """
        let summary = try WorkoutCSVService.importCSV(csv, assumedUnit: .kg, modelContext: context)
        XCTAssertEqual(summary.newExercises, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    // MARK: - Records from imported history

    private let benchHistoryCSV = """
    Date,Workout Name,Exercise Name,Set Order,Weight,Reps,RPE
    2026-06-10 18:00:00,Push,Bench Press (Barbell),1,80,5,
    2026-06-10 18:00:00,Push,Pull Up,1,,8,
    2026-06-17 18:00:00,Push,Bench Press (Barbell),1,85,5,
    2026-06-17 18:00:00,Push,Bench Press (Barbell),2,90,3,
    2026-06-17 18:00:00,Push,Pull Up,1,,10,
    2026-06-24 18:00:00,Push,Bench Press (Barbell),1,80,5,
    2026-06-24 18:00:00,Push,Pull Up,1,,9,
    """

    private func records(_ context: ModelContext) throws -> [PersonalRecord] {
        try context.fetch(FetchDescriptor<PersonalRecord>(sortBy: [.init(\.date)]))
    }

    func testImportedHistoryEstablishesRecordsOnTheirRealDates() throws {
        let context = try makeContext()
        let summary = try WorkoutCSVService.importCSV(benchHistoryCSV, assumedUnit: .kg, modelContext: context)

        let rows = try records(context)
        // First session of each lift = baseline (no PR). Second session beats
        // it. Third session beats nothing.
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(summary.records, 2)
        let bench = try XCTUnwrap(rows.first { $0.exercise?.name == "Bench Press (Barbell)" })
        XCTAssertEqual(bench.type, .oneRepMax, "e1RM PR; no separate heaviest-weight row for the same set")
        XCTAssertEqual(bench.contextWeightKg, 85, "Best e1RM set of the session (85 x 5 ≈ 99 beats 90 x 3 ≈ 99 by a hair)")
        let pullUp = try XCTUnwrap(rows.first { $0.exercise?.name == "Pull Up" })
        XCTAssertEqual(pullUp.type, .mostReps)
        XCTAssertEqual(pullUp.value, 10)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: bench.date), 17, "Dated at the session, not the import")
        XCTAssertEqual(calendar.component(.month, from: bench.date), 6)
        XCTAssertEqual(Set(rows.map(\.workoutPlanID)).count, 1, "One record per lift per session, same session here")
    }

    func testRowsInAnyOrderStillReplayChronologically() throws {
        let lines = benchHistoryCSV.split(separator: "\n")
        let newestFirst = ([lines[0]] + lines.dropFirst().reversed()).joined(separator: "\n")
        let context = try makeContext()
        _ = try WorkoutCSVService.importCSV(newestFirst, assumedUnit: .kg, modelContext: context)
        XCTAssertEqual(try records(context).count, 2)
    }

    func testFirstLiveSetAfterImportIsNotABogusFirstLogRecord() throws {
        let context = try makeContext()
        _ = try WorkoutCSVService.importCSV(benchHistoryCSV, assumedUnit: .kg, modelContext: context)
        let bench = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Bench Press (Barbell)" })
        let engine = TrainingEngine()

        XCTAssertNil(engine.detectPersonalRecord(exercise: bench, weight: 60, reps: 8, rir: 2),
                     "Imported history is the baseline: a lighter set is not a first-log PR")
        XCTAssertNotNil(engine.detectPersonalRecord(exercise: bench, weight: 100, reps: 3, rir: 1),
                        "A genuine record against imported history still fires")
    }

    func testImportedPoundsRecordsAreStoredInKilos() throws {
        let context = try makeContext()
        let csv = """
        Date,Workout Name,Exercise Name,Set Order,Weight,Reps
        2026-06-10 18:00:00,Push,Bench Press (Barbell),1,185,5
        2026-06-17 18:00:00,Push,Bench Press (Barbell),1,225,5
        """
        _ = try WorkoutCSVService.importCSV(csv, assumedUnit: .lbs, modelContext: context)
        let record = try XCTUnwrap(records(context).first)
        XCTAssertEqual(try XCTUnwrap(record.contextWeightKg), 225 / 2.20462, accuracy: 0.001)
    }

    func testOlderImportedSessionsNeverMintRecordsAgainstNewerLiveHistory() throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press (Barbell)", muscleGroup: .chest, equipment: .barbell,
                             movementPattern: .horizontalPush, isCompound: true)
        context.insert(bench)
        // Live history from August: 120 kg.
        context.insert(ExerciseHistory(date: ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z") ?? Date(),
                                       estimated1RM: 135, totalVolume: 600, bestSetWeight: 120, bestSetReps: 5,
                                       setsPerformed: 1, workoutPlanID: UUID(), exercise: bench))
        try context.save()

        _ = try WorkoutCSVService.importCSV(benchHistoryCSV, assumedUnit: .kg, modelContext: context)

        // June sessions: the first is the earliest log (baseline); the 90 kg
        // session beats it. Nothing is compared against August's 120 kg.
        let rows = try records(context).filter { $0.exercise?.id == bench.id }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(Calendar.current.component(.day, from: try XCTUnwrap(rows.first?.date)), 17)
    }

    func testUndoRemovesImportedRecordsToo() throws {
        let context = try makeContext()
        let summary = try WorkoutCSVService.importCSV(benchHistoryCSV, assumedUnit: .kg, modelContext: context)
        XCTAssertEqual(try records(context).count, 2)
        try WorkoutCSVService.undoImport(batchID: try XCTUnwrap(summary.batchID), modelContext: context)
        XCTAssertEqual(try records(context).count, 0)
    }
}
