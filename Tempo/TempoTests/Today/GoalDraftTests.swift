//
// GoalDraftTests.swift
// TempoTests
//
// What the goal editor accepts: numbers in the person's own unit, a lift for a
// lift goal, a run time with minutes or seconds, and a date after today.
//

@testable import Tempo
import XCTest

final class GoalDraftTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var later: Date {
        calendar.date(byAdding: .day, value: 30, to: now)!
    }

    private func draft(_ kind: GoalKind) -> GoalDraft {
        var draft = GoalDraft(targetDate: later)
        draft.kind = kind
        return draft
    }

    func testANumberReadsWithACommaOrADot() {
        XCTAssertEqual(GoalDraft.number("82.5"), 82.5)
        XCTAssertEqual(GoalDraft.number("82,5"), 82.5)
        XCTAssertEqual(GoalDraft.number("  70 "), 70)
        XCTAssertNil(GoalDraft.number(""))
        XCTAssertNil(GoalDraft.number("abc"))
        XCTAssertNil(GoalDraft.number("nan"))
    }

    func testBodyWeightNeedsATarget() {
        var weight = draft(.bodyWeight)
        XCTAssertEqual(weight.problem(now: now, unit: .kg, calendar: calendar), .needsTarget)
        weight.weightText = "0"
        XCTAssertEqual(weight.problem(now: now, unit: .kg, calendar: calendar), .needsTarget)
        weight.weightText = "78"
        XCTAssertNil(weight.problem(now: now, unit: .kg, calendar: calendar))
        XCTAssertEqual(weight.targetValue(unit: .kg), 78)
    }

    func testPoundsAreStoredAsKilograms() {
        var weight = draft(.bodyWeight)
        weight.weightText = "165"
        XCTAssertEqual(weight.targetValue(unit: .lbs) ?? 0, 165 / 2.20462, accuracy: 0.001)
    }

    func testALiftNeedsAnExerciseAndAWeight() {
        var lift = draft(.liftE1RM)
        lift.weightText = "100"
        XCTAssertEqual(lift.problem(now: now, unit: .kg, calendar: calendar), .needsExercise)
        lift.exercise = "Barbell Bench Press"
        XCTAssertNil(lift.problem(now: now, unit: .kg, calendar: calendar))
    }

    func testARunTimeAddsMinutesAndSeconds() {
        var run = draft(.runTime)
        XCTAssertEqual(run.problem(now: now, unit: .kg, calendar: calendar), .needsTarget)
        run.minutesText = "24"
        run.secondsText = "30"
        XCTAssertEqual(run.targetValue(unit: .kg), 1470)
        run.minutesText = ""
        run.secondsText = "90"
        XCTAssertEqual(run.targetValue(unit: .kg), 90)
        run.minutesText = "-3"
        XCTAssertNil(run.targetValue(unit: .kg))
    }

    func testTheDateMustBeAfterToday() throws {
        var weight = draft(.bodyWeight)
        weight.weightText = "78"
        weight.targetDate = now
        XCTAssertEqual(weight.problem(now: now, unit: .kg, calendar: calendar), .needsDate)
        weight.targetDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        XCTAssertNil(weight.problem(now: now, unit: .kg, calendar: calendar))
    }

    func testAGoalReadsBackIntoADraftInTheSameUnit() {
        let goal = Goal(kind: .bodyWeight, targetValue: 75, targetDate: later)
        XCTAssertEqual(GoalDraft(goal: goal, unit: .kg).weightText, "75")
        XCTAssertEqual(GoalDraft(goal: goal, unit: .lbs).weightText, WeightFormat.number(kg: 75, unit: .lbs))

        let run = Goal(kind: .runTime, targetValue: 1470, targetDate: later, runDistanceKm: 5)
        let runDraft = GoalDraft(goal: run, unit: .kg)
        XCTAssertEqual(runDraft.minutesText, "24")
        XCTAssertEqual(runDraft.secondsText, "30")
    }

    func testApplyingADraftReBaselinesTheLine() {
        let goal = Goal(kind: .bodyWeight, targetValue: 75, targetDate: later, startValue: 90)
        var lift = draft(.liftE1RM)
        lift.weightText = "120"
        lift.exercise = "Squat"
        lift.apply(to: goal, unit: .kg, start: 100, now: now)
        XCTAssertEqual(goal.kind, .liftE1RM)
        XCTAssertEqual(goal.targetValue, 120)
        XCTAssertEqual(goal.startValue, 100)
        XCTAssertEqual(goal.startDate, now)
        XCTAssertEqual(goal.exerciseName, "Squat")
        XCTAssertNil(goal.runDistanceKm)
        XCTAssertTrue(goal.isActive)
    }
}
