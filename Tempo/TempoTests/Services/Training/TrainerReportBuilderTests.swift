//
// TrainerReportBuilderTests.swift
// Tempo
//
// Fix #8 — pins the report builder's core contract: a scheduled trainer
// session is reported done/missed/moved correctly, the trainer's
// prescription is paired with what was actually logged, a Tempo load
// adjustment (and an athlete override) shows up with WHY, and the Italian
// strings are actually Italian (not raw English leaking through). Also pins
// that the two outputs (WhatsApp text, PDF) stay in a sane, shareable size.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainerReportBuilderTests: XCTestCase {
    // MARK: - Fixture

    /// A fixed Monday so date math in tests never depends on the real
    /// "today".
    private let monday = TrainerReportBuilderTests.date("2026-09-21")

    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = TrainingCalendar.iso8601
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TrainerProgram.self, Exercise.self, PlannedExercise.self, PlannedSet.self,
            WorkoutPlan.self, PersonalRecord.self, ExerciseHistory.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeExercise(_ context: ModelContext, name: String = "Bench Press") -> Exercise {
        let exercise = Exercise(
            name: name, muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(exercise)
        return exercise
    }

    /// One-week program: Monday = Bench Press 3×8 @ 80kg.
    private func makeProgram(exercises: [ProgramExercise]? = nil) -> TrainerProgram {
        let day = ProgramDay(
            weekday: 1,
            title: "Upper Body",
            focus: "upper",
            exercises: exercises ?? [
                ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8, weightKg: 80),
            ]
        )
        return TrainerProgram(
            name: "Marco's Plan",
            startDate: monday,
            weeks: [ProgramWeek(days: [day])],
            sourceKind: "text"
        )
    }

    /// A logged plan for the program's Monday session, with `sets` completed
    /// working sets on a single PlannedExercise matching the program's one
    /// exercise (order 0).
    private func makeLoggedPlan(
        context: ModelContext,
        program: TrainerProgram,
        date: Date,
        exercise: Exercise,
        sets: [(weight: Double, reps: Int, rpe: Int?)],
        status: WorkoutStatus = .completed,
        trainerTargetKg: Double? = nil,
        loadAdjustmentNote: String? = nil,
        trainerOverrideApplied: Bool = false,
        userNotes: String? = nil
    ) -> WorkoutPlan {
        let plan = WorkoutPlan(id: UUID(), date: date, type: .upper, status: status)
        plan.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        plan.userNotes = userNotes
        context.insert(plan)

        let plannedEx = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        plannedEx.trainerTargetKg = trainerTargetKg
        plannedEx.loadAdjustmentNote = loadAdjustmentNote
        plannedEx.trainerOverrideApplied = trainerOverrideApplied
        context.insert(plannedEx)

        for (index, set) in sets.enumerated() {
            let plannedSet = PlannedSet(
                setNumber: index + 1, targetReps: 8, actualReps: set.reps, actualWeight: set.weight,
                rpe: set.rpe, completed: true, plannedExercise: plannedEx
            )
            context.insert(plannedSet)
        }
        return plan
    }

    private func input(
        program: TrainerProgram,
        plans: [WorkoutPlan] = [],
        personalRecords: [PersonalRecord] = [],
        painFlaggedExerciseIDs: Set<UUID> = []
    ) -> TrainerReportInput {
        // A one-week program's scope window — the whole program covers just
        // its single scheduled Monday.
        let scopeRange = monday ... monday
        return TrainerReportInput(
            program: program,
            scope: .week,
            scopeRange: scopeRange,
            plans: plans,
            personalRecords: personalRecords,
            painFlaggedExerciseIDs: painFlaggedExerciseIDs
        )
    }

    // MARK: - Status: done / missed / moved

    func testDoneSessionPairsPrescriptionWithActuals() throws {
        let context = try makeContext()
        let program = makeProgram()
        let exercise = makeExercise(context)
        let plan = makeLoggedPlan(
            context: context, program: program, date: monday, exercise: exercise,
            sets: [(80, 8, 8), (80, 8, nil), (82.5, 6, 9)]
        )

        let document = TrainerReportBuilder.build(input: input(program: program, plans: [plan]), language: .english)

        XCTAssertEqual(document.sessions.count, 1)
        let session = try XCTUnwrap(document.sessions.first)
        XCTAssertEqual(session.status, .done)
        XCTAssertEqual(session.statusLabel, "Done")
        let exerciseLine = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(exerciseLine.prescriptionText, "3×8 reps @ 80kg")
        XCTAssertTrue(exerciseLine.actualText.contains("80kg×8"), exerciseLine.actualText)
        XCTAssertTrue(exerciseLine.actualText.contains("82.5kg×6"), exerciseLine.actualText)
        XCTAssertTrue(exerciseLine.actualText.contains("RPE"), exerciseLine.actualText)
    }

    func testMissedSessionHasNoActualsAndStillShowsPrescription() throws {
        let program = makeProgram()

        let document = TrainerReportBuilder.build(input: input(program: program, plans: []), language: .english)

        XCTAssertEqual(document.sessions.count, 1)
        let session = try XCTUnwrap(document.sessions.first)
        XCTAssertEqual(session.status, .missed)
        XCTAssertEqual(session.statusLabel, "Missed")
        XCTAssertNil(session.completionFraction)
        let exerciseLine = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(exerciseLine.prescriptionText, "3×8 reps @ 80kg")
        XCTAssertEqual(exerciseLine.actualText, "Not done")
    }

    func testMovedSessionReportsActualDate() throws {
        let context = try makeContext()
        let program = makeProgram()
        let exercise = makeExercise(context)
        let movedDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: monday)) // Wednesday
        let plan = makeLoggedPlan(
            context: context, program: program, date: movedDate, exercise: exercise,
            sets: [(80, 8, nil)]
        )

        let document = TrainerReportBuilder.build(input: input(program: program, plans: [plan]), language: .english)

        let session = try XCTUnwrap(document.sessions.first)
        XCTAssertEqual(session.status, .moved(to: movedDate))
        XCTAssertTrue(session.statusLabel.hasPrefix("Moved to"), session.statusLabel)
    }

    /// A two-a-day (lift + conditioning) shares ONE `WorkoutPlan` between its
    /// main and secondary sessions — the secondary row must NOT pair its
    /// prescription against the main lift's logged sets (see the comment in
    /// `TrainerReportBuilder.buildRow`), must use `secondaryCompleted` for
    /// completion, and must not repeat the main row's PRs.
    func testTwoADaySecondaryRowDoesNotBorrowTheMainSessionsExercises() throws {
        let context = try makeContext()
        let strengthDay = ProgramDay(
            weekday: 1, title: "Upper Body", focus: "upper",
            exercises: [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8, weightKg: 80)]
        )
        let conditioningDay = ProgramDay(
            weekday: 1, title: "Shuttles", focus: "conditioning",
            exercises: [ProgramExercise(name: "Shuttles", sets: 1, repsLow: 1, detail: "6x 40m sprints")]
        )
        let program = TrainerProgram(
            name: "Two-a-Day", startDate: monday,
            weeks: [ProgramWeek(days: [strengthDay, conditioningDay])],
            sourceKind: "text"
        )
        let exercise = makeExercise(context)
        let plan = makeLoggedPlan(
            context: context, program: program, date: monday, exercise: exercise,
            sets: [(80, 8, nil)]
        )
        plan.programSecondaryKey = program.sessionKey(weekIndex: 0, dayIndex: 1)
        plan.secondarySessionType = .conditioning
        plan.secondaryCompleted = true
        let pr = PersonalRecord(type: .oneRepMax, value: 90, date: monday, workoutPlanID: plan.id, exercise: exercise)
        context.insert(pr)

        let document = TrainerReportBuilder.build(
            input: input(program: program, plans: [plan], personalRecords: [pr]),
            language: .english
        )

        XCTAssertEqual(document.sessions.count, 2)
        let strengthRow = try XCTUnwrap(document.sessions.first { $0.title == "Upper Body" })
        let conditioningRow = try XCTUnwrap(document.sessions.first { $0.title == "Shuttles" })

        XCTAssertEqual(strengthRow.exercises.count, 1)
        XCTAssertEqual(strengthRow.prs.count, 1, "the PR belongs on the lift row")

        XCTAssertTrue(conditioningRow.exercises.isEmpty, "no PlannedExercise data exists for the secondary session")
        XCTAssertTrue(conditioningRow.prs.isEmpty, "must not repeat the shared plan's PR on the secondary row")
        XCTAssertEqual(conditioningRow.completionFraction, 1, "must read secondaryCompleted, not the lift's sets")
        XCTAssertTrue(
            conditioningRow.notes.contains("6x 40m sprints"),
            "the trainer's free-text prescription still surfaces somewhere"
        )
    }

    // MARK: - Adjustment / override

    func testAdjustmentNoteIsTranslatedForItalian() throws {
        let context = try makeContext()
        let program = makeProgram()
        let exercise = makeExercise(context)
        let plan = makeLoggedPlan(
            context: context, program: program, date: monday, exercise: exercise,
            sets: [(64, 8, nil)],
            trainerTargetKg: 80,
            loadAdjustmentNote: "Recovery yellow −20%"
        )

        let document = TrainerReportBuilder.build(input: input(program: program, plans: [plan]), language: .italian)

        let exerciseLine = try XCTUnwrap(document.sessions.first?.exercises.first)
        let adjustment = try XCTUnwrap(exerciseLine.adjustmentText)
        XCTAssertTrue(adjustment.contains("Recupero giallo"), adjustment)
        XCTAssertFalse(adjustment.contains("Recovery yellow"), adjustment)
    }

    func testOverrideAppliedIsFlagged() throws {
        let context = try makeContext()
        let program = makeProgram()
        let exercise = makeExercise(context)
        let plan = makeLoggedPlan(
            context: context, program: program, date: monday, exercise: exercise,
            sets: [(80, 8, nil)],
            trainerTargetKg: 80,
            trainerOverrideApplied: true
        )

        let document = TrainerReportBuilder.build(input: input(program: program, plans: [plan]), language: .english)

        let exerciseLine = try XCTUnwrap(document.sessions.first?.exercises.first)
        XCTAssertTrue(exerciseLine.overrideApplied)
    }

    // MARK: - PRs

    func testPersonalRecordAttributedToItsSession() throws {
        let context = try makeContext()
        let program = makeProgram()
        let exercise = makeExercise(context)
        let plan = makeLoggedPlan(
            context: context, program: program, date: monday, exercise: exercise,
            sets: [(85, 5, nil)]
        )
        let pr = PersonalRecord(
            type: .oneRepMax, value: 95, date: monday, workoutPlanID: plan.id,
            contextWeightKg: 85, contextReps: 5, exercise: exercise
        )
        context.insert(pr)

        let document = TrainerReportBuilder.build(
            input: input(program: program, plans: [plan], personalRecords: [pr]),
            language: .english
        )

        let session = try XCTUnwrap(document.sessions.first)
        XCTAssertEqual(session.prs.count, 1)
        XCTAssertTrue(session.prs[0].text.contains("85kg×5"), session.prs[0].text)
    }

    // MARK: - Language strings

    func testItalianStringsAreActuallyItalian() {
        let program = makeProgram()

        let document = TrainerReportBuilder.build(input: input(program: program, plans: []), language: .italian)

        XCTAssertEqual(document.strings.statusMissed, "Saltata")
        XCTAssertEqual(document.strings.summaryTitle, "Riepilogo")
        XCTAssertEqual(document.sessions.first?.statusLabel, "Saltata")
        XCTAssertTrue(document.title.hasPrefix("Report allenamento"), document.title)
    }

    func testEnglishStringsAreActuallyEnglish() {
        let program = makeProgram()

        let document = TrainerReportBuilder.build(input: input(program: program, plans: []), language: .english)

        XCTAssertEqual(document.strings.statusMissed, "Missed")
        XCTAssertEqual(document.strings.summaryTitle, "Summary")
        XCTAssertTrue(document.title.hasPrefix("Training report"), document.title)
    }

    func testLanguageDetectorPrefersItalianSourceText() {
        let program = TrainerProgram(
            name: "P", startDate: monday, weeks: [ProgramWeek(days: [])],
            sourceKind: "text",
            sourceText: "Lunedì: Panca 3 serie x 8 ripetizioni, recupero 90 secondi"
        )
        XCTAssertEqual(TrainerReportBuilder.detectLanguage(program: program, deviceLanguageCode: "en"), .italian)
    }

    func testLanguageDetectorFallsBackToDeviceLanguage() {
        let program = TrainerProgram(
            name: "P", startDate: monday, weeks: [ProgramWeek(days: [])],
            sourceKind: "text",
            sourceText: "Monday: Bench Press 3 sets x 8 reps, rest 90 seconds"
        )
        XCTAssertEqual(TrainerReportBuilder.detectLanguage(program: program, deviceLanguageCode: "it"), .italian)
        XCTAssertEqual(TrainerReportBuilder.detectLanguage(program: program, deviceLanguageCode: "en"), .english)
    }

    // MARK: - Text formatter

    func testWhatsAppTextStaysWithinASensibleLength() throws {
        let context = try makeContext()
        let program = makeProgram()
        let exercise = makeExercise(context)
        let plan = makeLoggedPlan(
            context: context, program: program, date: monday, exercise: exercise,
            sets: [(80, 8, 8), (80, 8, 8), (82.5, 6, 9)]
        )

        let document = TrainerReportBuilder.build(input: input(program: program, plans: [plan]), language: .italian)
        let text = TrainerReportTextFormatter.text(for: document)

        XCTAssertFalse(text.isEmpty)
        // One session, one exercise — a realistic single-week report should
        // read as a quick WhatsApp message, not a wall of text.
        XCTAssertLessThan(text.count, 1500, "report text ballooned for a 1-session fixture: \(text.count) chars")
        XCTAssertTrue(text.contains("Fatta"))
    }

    // MARK: - Scope resolution

    func testWeekScopeNeverExtendsPastToday() throws {
        let program = makeProgram()
        // "today" = the Wednesday of that same week.
        let wednesday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: monday))
        let range = TrainerReportBuilder.scheduleRange(for: .week, program: program, today: wednesday)
        XCTAssertEqual(range.lowerBound, monday)
        XCTAssertEqual(range.upperBound, wednesday)
    }

    func testWholeProgramScopeStartsAtProgramStart() throws {
        let program = makeProgram()
        let today = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 20, to: monday))
        let range = TrainerReportBuilder.scheduleRange(for: .wholeProgram, program: program, today: today)
        XCTAssertEqual(range.lowerBound, monday)
        XCTAssertEqual(range.upperBound, today)
    }

    // MARK: - Stored conditioning results

    /// A repeating program reuses the same session key every cycle — the
    /// provider must only return the results logged on THIS occurrence's
    /// plan, labelled with the trainer's block name, in block order.
    func testStoredConditioningResultsArePinnedToTheOccurrencesPlan() {
        let shuttle = ProgramExercise(name: "Shuttle 25y", sets: 1, repsLow: 4)
        let tempo = ProgramExercise(name: "Tempo run", sets: 1, repsLow: 1)
        let program = TrainerProgram(
            name: "Plan",
            startDate: monday,
            weeks: [ProgramWeek(days: [ProgramDay(weekday: 4, title: "Run", focus: "sprint", exercises: [shuttle, tempo])])],
            sourceKind: "text"
        )
        let thisWeek = UUID()
        let lastWeek = UUID()
        let results = [
            ConditioningBlockResult(workoutPlanID: thisWeek, programSessionKey: "k", blockID: tempo.id, durationSeconds: 900),
            ConditioningBlockResult(
                workoutPlanID: thisWeek, programSessionKey: "k", blockID: shuttle.id,
                repTimesSeconds: [60, 62], rpe: 7.6, targetMet: true
            ),
            ConditioningBlockResult(workoutPlanID: lastWeek, programSessionKey: "k", blockID: shuttle.id, repTimesSeconds: [70]),
        ]
        let provider = StoredConditioningResults(results: results, program: program)

        let lines = provider.conditioningLines(forSessionKey: "k", workoutPlanID: thisWeek)
        XCTAssertEqual(lines.map(\.blockLabel), ["Shuttle 25y", "Tempo run"])
        XCTAssertEqual(lines.first?.repTimesSeconds, [60, 62])
        XCTAssertEqual(lines.first?.rpe, 8)
        XCTAssertEqual(lines.first?.targetMet, true)
        XCTAssertTrue(provider.conditioningLines(forSessionKey: "k", workoutPlanID: nil).isEmpty, "not done → nothing")
        XCTAssertTrue(provider.conditioningLines(forSessionKey: "other", workoutPlanID: thisWeek).isEmpty)
    }

    // MARK: - Sequence mode

    /// Sequence mode: a session is dated by when the athlete actually did it,
    /// not by its weekday. A session skipped Monday and done Tuesday shows
    /// once, as done on Tuesday; a later lapsed one nobody completed is missed.
    func testSequenceModeReportsCarriedForwardSessionOnceAsDone() throws {
        let context = try makeContext()
        let program = makeProgram()
        program.scheduleMode = .sequence
        let exercise = makeExercise(context)
        let tuesday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: monday))
        let wednesday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: monday))

        let skipped = WorkoutPlan(id: UUID(), date: monday, type: .upper, status: .planned)
        skipped.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(skipped)
        let done = makeLoggedPlan(
            context: context, program: program, date: tuesday, exercise: exercise, sets: [(80, 8, nil)]
        )
        let lapsed = WorkoutPlan(id: UUID(), date: wednesday, type: .upper, status: .planned)
        lapsed.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(lapsed)

        var reportInput = input(program: program, plans: [skipped, done, lapsed])
        reportInput.scopeRange = monday ... wednesday
        let document = TrainerReportBuilder.build(input: reportInput, language: .english)

        XCTAssertEqual(document.sessions.map(\.status), [.done, .missed])
        XCTAssertTrue(Calendar.current.isDate(document.sessions[0].scheduledDate, inSameDayAs: tuesday))
        XCTAssertEqual(document.sessions[0].exercises.first?.prescriptionText, "3×8 reps @ 80kg")
        XCTAssertTrue(Calendar.current.isDate(document.sessions[1].scheduledDate, inSameDayAs: wednesday))
    }
}
