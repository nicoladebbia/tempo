//
// WeekOverWeekProgressTests.swift
// Tempo
//
// Sunday wrap-up / trainer-report feature — pins the week-over-week
// comparator's core contract: an exercise/block with no earlier session is
// left out (not a zero-delta row), the MOST RECENT occurrence on each side
// wins when there's more than one, and conditioning matches by NAME/SHAPE
// rather than an ID (every weekly re-upload mints fresh `ProgramExercise`
// ids, so matching by id would never work across weeks).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WeekOverWeekProgressTests: XCTestCase {
    // MARK: - Fixture

    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = TrainingCalendar.iso8601
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Exercise.self, ExerciseHistory.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeExercise(_ context: ModelContext, name: String = "RDL") -> Exercise {
        let exercise = Exercise(
            name: name, muscleGroup: .hamstrings, equipment: .barbell,
            movementPattern: .hinge, isCompound: true
        )
        context.insert(exercise)
        return exercise
    }

    @discardableResult
    private func makeHistory(
        _ context: ModelContext,
        exercise: Exercise?,
        date: Date,
        estimated1RM: Double? = nil,
        totalVolume: Double = 0,
        bestSetWeight: Double? = nil,
        bestSetReps: Int? = nil
    ) -> ExerciseHistory {
        let history = ExerciseHistory(
            date: date, estimated1RM: estimated1RM, totalVolume: totalVolume,
            bestSetWeight: bestSetWeight, bestSetReps: bestSetReps, exercise: exercise
        )
        context.insert(history)
        return history
    }

    // MARK: - Exercise comparison

    func testExerciseWithNoPriorHistoryIsExcluded() throws {
        let context = try makeContext()
        let exercise = makeExercise(context)
        makeHistory(context, exercise: exercise, date: Self.date("2026-09-21"), bestSetWeight: 60, bestSetReps: 8)

        let deltas = WeekOverWeekProgress.compareExercises(currentHistories: [], priorHistories: [])
        XCTAssertTrue(deltas.isEmpty)
    }

    func testWeightAndE1RMDeltaComputedAgainstMostRecentPriorSession() throws {
        let context = try makeContext()
        let exercise = makeExercise(context)
        let twoWeeksAgo = makeHistory(
            context, exercise: exercise, date: Self.date("2026-09-07"),
            estimated1RM: 70, totalVolume: 1000, bestSetWeight: 55, bestSetReps: 8
        )
        let lastWeek = makeHistory(
            context, exercise: exercise, date: Self.date("2026-09-14"),
            estimated1RM: 75, totalVolume: 1100, bestSetWeight: 60, bestSetReps: 8
        )
        let thisWeek = makeHistory(
            context, exercise: exercise, date: Self.date("2026-09-21"),
            estimated1RM: 80, totalVolume: 1200, bestSetWeight: 65, bestSetReps: 8
        )

        let deltas = WeekOverWeekProgress.compareExercises(
            currentHistories: [thisWeek],
            priorHistories: [twoWeeksAgo, lastWeek]
        )

        let delta = try XCTUnwrap(deltas.first)
        XCTAssertEqual(delta.exerciseID, exercise.id)
        // Most recent prior (lastWeek), NOT the oldest one.
        XCTAssertEqual(delta.previousBestWeightKg, 60)
        XCTAssertEqual(delta.currentBestWeightKg, 65)
        XCTAssertEqual(delta.e1RMDelta, 5)
        XCTAssertEqual(delta.volumeDelta, 100)
        XCTAssertEqual(delta.recapLine, "RDL 60→65 kg (1RM +5)")
    }

    func testMultipleCurrentOccurrencesUseTheMostRecentOne() throws {
        let context = try makeContext()
        let exercise = makeExercise(context)
        let prior = makeHistory(context, exercise: exercise, date: Self.date("2026-09-14"), bestSetWeight: 60, bestSetReps: 8)
        let earlierThisWeek = makeHistory(context, exercise: exercise, date: Self.date("2026-09-15"), bestSetWeight: 62, bestSetReps: 8)
        let laterThisWeek = makeHistory(context, exercise: exercise, date: Self.date("2026-09-19"), bestSetWeight: 65, bestSetReps: 8)

        let deltas = WeekOverWeekProgress.compareExercises(
            currentHistories: [earlierThisWeek, laterThisWeek],
            priorHistories: [prior]
        )

        let delta = try XCTUnwrap(deltas.first)
        XCTAssertEqual(delta.currentBestWeightKg, 65)
    }

    func testDifferentExercisesDoNotCrossMatch() throws {
        let context = try makeContext()
        let rdl = makeExercise(context, name: "RDL")
        let squat = makeExercise(context, name: "Back Squat")
        let priorRDL = makeHistory(context, exercise: rdl, date: Self.date("2026-09-14"), bestSetWeight: 60, bestSetReps: 8)
        makeHistory(context, exercise: squat, date: Self.date("2026-09-14"), bestSetWeight: 100, bestSetReps: 5)
        let currentRDL = makeHistory(context, exercise: rdl, date: Self.date("2026-09-21"), bestSetWeight: 65, bestSetReps: 8)

        let deltas = WeekOverWeekProgress.compareExercises(currentHistories: [currentRDL], priorHistories: [priorRDL])

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas.first?.name, "RDL")
    }

    func testWeightChangeTextFromBodyweightToLoadedReadsBWNotZero() {
        let delta = WeekOverWeekProgress.ExerciseDelta(
            exerciseID: UUID(), name: "Dip",
            currentDate: Self.date("2026-09-21"), previousDate: Self.date("2026-09-14"),
            currentBestWeightKg: 20, currentBestReps: 6,
            previousBestWeightKg: 0, previousBestReps: 12,
            e1RMDelta: nil, volumeDelta: 0
        )
        XCTAssertEqual(delta.weightChangeText(unit: .kg), "BW→20 kg")
    }

    func testWeightChangeTextFallsBackToCurrentOnlyWhenWeightUnchanged() {
        let delta = WeekOverWeekProgress.ExerciseDelta(
            exerciseID: UUID(), name: "Bench Press",
            currentDate: Self.date("2026-09-21"), previousDate: Self.date("2026-09-14"),
            currentBestWeightKg: 80, currentBestReps: 10,
            previousBestWeightKg: 80, previousBestReps: 8,
            e1RMDelta: nil, volumeDelta: 0
        )
        XCTAssertEqual(delta.weightChangeText, "80 kg")
    }

    // MARK: - Conditioning comparison

    private func snapshot(
        label: String,
        detail: String? = nil,
        date: Date,
        repTimes: [Double] = [],
        duration: Double? = nil
    ) -> WeekOverWeekProgress.ConditioningBlockSnapshot {
        WeekOverWeekProgress.ConditioningBlockSnapshot(
            label: label, detail: detail, date: date, repTimesSeconds: repTimes, durationSeconds: duration
        )
    }

    func testConditioningMatchesByNameAcrossWeeks() throws {
        let prior = snapshot(label: "Shuttle 1", date: Self.date("2026-09-14"), repTimes: [62, 63, 61, 60])
        let current = snapshot(label: "Shuttle 1", date: Self.date("2026-09-21"), repTimes: [58, 59, 57, 60])

        let deltas = WeekOverWeekProgress.compareConditioning(currentBlocks: [current], priorBlocks: [prior])

        let delta = try XCTUnwrap(deltas.first)
        XCTAssertEqual(delta.blockLabel, "Shuttle 1")
        XCTAssertNotNil(delta.avgChangeText)
        XCTAssertTrue(delta.recapLine.hasPrefix("Shuttle 1 avg"))
    }

    func testConditioningWithNoNameFallsBackToShapeMatch() {
        // No label (freeform block) — matched by identical parsed shape
        // instead: same reps × distance × cap both weeks.
        let prior = snapshot(
            label: "",
            detail: "4 reps of 25y out and back in < 65\"",
            date: Self.date("2026-09-14"),
            repTimes: [64, 63, 62, 61]
        )
        let current = snapshot(
            label: "",
            detail: "4 reps of 25y out and back in < 65\"",
            date: Self.date("2026-09-21"),
            repTimes: [61, 60, 59, 58]
        )

        let deltas = WeekOverWeekProgress.compareConditioning(currentBlocks: [current], priorBlocks: [prior])

        XCTAssertEqual(deltas.count, 1)
    }

    func testConditioningBlockWithNoPriorIsExcluded() {
        let current = snapshot(label: "New Drill", date: Self.date("2026-09-21"), repTimes: [30])
        let deltas = WeekOverWeekProgress.compareConditioning(currentBlocks: [current], priorBlocks: [])
        XCTAssertTrue(deltas.isEmpty)
    }

    func testDurationOnlyBlockUsesDurationAsAvgAndBest() throws {
        let prior = snapshot(label: "Aerobic Run", date: Self.date("2026-09-14"), duration: 35 * 60)
        let current = snapshot(label: "Aerobic Run", date: Self.date("2026-09-21"), duration: 32 * 60)

        let deltas = WeekOverWeekProgress.compareConditioning(currentBlocks: [current], priorBlocks: [prior])

        let delta = try XCTUnwrap(deltas.first)
        XCTAssertEqual(delta.previousAvgSeconds, 35 * 60)
        XCTAssertEqual(delta.currentAvgSeconds, 32 * 60)
    }

    // MARK: - Result lookup helpers

    func testResultLooksUpExerciseDeltaByID() {
        let exerciseID = UUID()
        let delta = WeekOverWeekProgress.ExerciseDelta(
            exerciseID: exerciseID, name: "RDL",
            currentDate: Self.date("2026-09-21"), previousDate: Self.date("2026-09-14"),
            currentBestWeightKg: 65, currentBestReps: 8,
            previousBestWeightKg: 60, previousBestReps: 8,
            e1RMDelta: 5, volumeDelta: 100
        )
        let result = WeekOverWeekProgress.Result(exercises: [delta], conditioning: [])

        XCTAssertEqual(result.exerciseDelta(forExerciseID: exerciseID)?.name, "RDL")
        XCTAssertNil(result.exerciseDelta(forExerciseID: UUID()))
    }

    func testResultLooksUpConditioningDeltaByLabelCaseAndWhitespaceInsensitively() {
        let prior = snapshot(label: "Shuttle 1", date: Self.date("2026-09-14"), repTimes: [62])
        let current = snapshot(label: "Shuttle 1", date: Self.date("2026-09-21"), repTimes: [58])
        let deltas = WeekOverWeekProgress.compareConditioning(currentBlocks: [current], priorBlocks: [prior])
        let result = WeekOverWeekProgress.Result(exercises: [], conditioning: deltas)

        XCTAssertNotNil(result.conditioningDelta(forBlockLabel: "  shuttle 1  "))
        XCTAssertNil(result.conditioningDelta(forBlockLabel: "Shuttle 2"))
    }
}
