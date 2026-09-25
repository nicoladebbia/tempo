//
// GuidedRunPlanBuilderTests.swift
// Tempo
//
// Guided run mode — the plan builder against the REAL sample program blocks
// from TrainerProgramImportView's DEBUG "Load Sample Program" data (Aerobic
// Run, Anaerobic Run's two shuttle blocks, Speed Development's T/Arrow
// drills), plus a couple of synthetic edge cases (rest resolution order,
// multi-set repeats).
//

@testable import Tempo
import XCTest

final class GuidedRunPlanBuilderTests: XCTestCase {
    // MARK: - Sample program fixtures (verbatim from TrainerProgramImportView)

    private func aerobicRunDay() -> ProgramDay {
        ProgramDay(
            weekday: 2,
            title: "Aerobic Run",
            focus: WorkoutType.run.rawValue,
            exercises: [
                ProgramExercise(
                    name: "Warm Up", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: 6, percentOf1RM: nil, restSeconds: nil, group: nil,
                    notes: "Without ball", detail: "5'", perSide: nil
                ),
                ProgramExercise(
                    name: "Fartleck", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: 8, percentOf1RM: nil, restSeconds: nil, group: nil,
                    notes: "With the ball", detail: "35' — 2' slow / 1' fast / 30\" walk + juggling", perSide: nil
                ),
                ProgramExercise(
                    name: "Cool Down", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: 6, percentOf1RM: nil, restSeconds: nil, group: nil,
                    notes: "Without ball", detail: "10'", perSide: nil
                ),
            ],
            notes: nil,
            weekdayGuessed: true
        )
    }

    private func anaerobicRunDay() -> ProgramDay {
        ProgramDay(
            weekday: 4,
            title: "Anaerobic Run",
            focus: WorkoutType.sprint.rawValue,
            exercises: [
                ProgramExercise(
                    name: "Shuttle 1", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: 9, percentOf1RM: nil, restSeconds: 90, group: nil,
                    notes: "300y total", detail: "4 reps of 25y out and back in < 65\"", perSide: nil
                ),
                ProgramExercise(
                    name: "Shuttle 2", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: 9, percentOf1RM: nil, restSeconds: 90, group: nil,
                    notes: "320y total", detail: "4 reps 80y out and back in < 55\"", perSide: nil
                ),
            ],
            notes: "Follow the order: S1 - Rest - S2 - Rest - S2 - Rest - S1",
            weekdayGuessed: true
        )
    }

    private func speedDevelopmentDay() -> ProgramDay {
        ProgramDay(
            weekday: 6,
            title: "Speed Development Conditioning",
            focus: WorkoutType.conditioning.rawValue,
            exercises: [
                ProgramExercise(
                    name: "Run", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: 7, percentOf1RM: nil, restSeconds: nil, group: nil,
                    notes: nil, detail: "15' easy", perSide: nil
                ),
                ProgramExercise(
                    name: "T Drill", exerciseID: nil, sets: 2, repsLow: 10, repsHigh: nil,
                    weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: 1,
                    notes: "When you feel ready, but 2' in between", detail: "10m + 5m", perSide: nil
                ),
                ProgramExercise(
                    name: "Arrow Drill", exerciseID: nil, sets: 2, repsLow: 10, repsHigh: nil,
                    weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: 1,
                    notes: "When you feel ready, but 2' in between", detail: "10m + 5m", perSide: nil
                ),
                ProgramExercise(
                    name: "Run", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: 6, percentOf1RM: nil, restSeconds: nil, group: nil,
                    notes: nil, detail: "10' easy", perSide: nil
                ),
            ],
            notes: nil,
            weekdayGuessed: true
        )
    }

    // MARK: - Duration shape (Aerobic Run)

    func testAerobicRunBuildsThreeContinuousDurationBlocksNoRests() {
        let plan = GuidedRunPlanBuilder.build(day: aerobicRunDay())

        XCTAssertEqual(plan.blocks.count, 3)
        // Each block is sets:1 -> a single continuous step, no rest steps at
        // all (no reps within, no sets between).
        XCTAssertEqual(plan.steps.count, 3)
        XCTAssertTrue(plan.steps.allSatisfy(\.isWork))

        guard case let .work(.continuousDuration(warmUp)) = plan.steps[0].kind,
              case let .work(.continuousDuration(fartleck)) = plan.steps[1].kind,
              case let .work(.continuousDuration(coolDown)) = plan.steps[2].kind
        else {
            return XCTFail("expected continuousDuration steps")
        }
        XCTAssertEqual(warmUp, 5 * 60)
        // "35' — 2' slow / 1' fast / 30\" walk" — parser takes the FIRST
        // duration marker only (35'), not the parenthetical breakdown.
        XCTAssertEqual(fartleck, 35 * 60)
        XCTAssertEqual(coolDown, 10 * 60)
    }

    // MARK: - repsDistance shape (Anaerobic Run)

    func testAnaerobicRunBuildsFourTimedRepsPerShuttleWithTrainerRest() throws {
        let plan = GuidedRunPlanBuilder.build(day: anaerobicRunDay())

        XCTAssertEqual(plan.blocks.count, 2)
        let shuttle1 = plan.blocks[0]
        let shuttle2 = plan.blocks[1]

        // Trainer wrote restSeconds: 90 on both blocks (structured field) —
        // not Tempo's own default, so restIsDefault is false even though
        // 90 happens to equal the shuttle default too.
        XCTAssertEqual(shuttle1.restSeconds, 90)
        XCTAssertFalse(shuttle1.restIsDefault)
        XCTAssertEqual(shuttle2.restSeconds, 90)
        XCTAssertFalse(shuttle2.restIsDefault)

        // 4 reps each: work, rest, work, rest, work, rest, work = 7 steps
        // per block, 14 total.
        XCTAssertEqual(plan.steps.count, 14)
        let shuttle1Steps = plan.steps.filter { $0.blockID == shuttle1.id }
        XCTAssertEqual(shuttle1Steps.count, 7)
        let shuttle1Work = shuttle1Steps.filter(\.isWork)
        XCTAssertEqual(shuttle1Work.count, 4)

        guard case let .work(.timedRep(rep)) = shuttle1Work[0].kind else {
            return XCTFail("expected timedRep")
        }
        XCTAssertEqual(rep.index, 0)
        XCTAssertEqual(rep.of, 4)
        XCTAssertEqual(rep.capSeconds, 65)
        XCTAssertEqual(rep.distanceMeters ?? 0, 25 * 0.9144, accuracy: 0.001)
        XCTAssertEqual(rep.distanceLabel, "25y")

        // No rest AFTER the last rep of the block.
        XCTAssertTrue(try XCTUnwrap(shuttle1Steps.last?.isWork))

        // Shuttle 2: "4 reps 80y out and back in < 55\"".
        let shuttle2Work = plan.steps.filter { $0.blockID == shuttle2.id }.filter(\.isWork)
        guard case let .work(.timedRep(rep2)) = shuttle2Work[0].kind else {
            return XCTFail("expected timedRep")
        }
        XCTAssertEqual(rep2.of, 4)
        XCTAssertEqual(rep2.capSeconds, 55)
    }

    func testShuttleRepChecksCapSecondsMatchLiveVerdict() throws {
        // Sanity: the cap parsed here is exactly what
        // ConditioningTargetEvaluator already uses for the manual log
        // sheet — guided-run "live ✓/✗" and the after-the-fact sheet must
        // agree on the same number.
        let plan = GuidedRunPlanBuilder.build(day: anaerobicRunDay())
        guard case let .work(.timedRep(rep)) = try XCTUnwrap(plan.steps.first(where: \.isWork)?.kind) else {
            return XCTFail("expected timedRep")
        }
        let target = ConditioningTargetParser.parse(detail: "4 reps of 25y out and back in < 65\"")
        guard case let .repsDistance(_, _, _, parsedCap) = target.kind else {
            return XCTFail("expected repsDistance")
        }
        XCTAssertEqual(rep.capSeconds, parsedCap)
    }

    // MARK: - Distance shape with trainer sets (Speed Development drills)

    func testDrillsWithMultipleSetsBuildRepeatedDistanceRoundsWithDefaultRest() {
        let plan = GuidedRunPlanBuilder.build(day: speedDevelopmentDay())

        XCTAssertEqual(plan.blocks.count, 4)
        let tDrill = plan.blocks[1]
        XCTAssertEqual(tDrill.name, "T Drill")
        // No structured restSeconds, no parseable rest in "10m + 5m" ->
        // Tempo's own 60s drill default.
        XCTAssertEqual(tDrill.restSeconds, 60)
        XCTAssertTrue(tDrill.restIsDefault)

        // sets: 2 -> 2 continuousDistance rounds with one rest between.
        let tDrillSteps = plan.steps.filter { $0.blockID == tDrill.id }
        XCTAssertEqual(tDrillSteps.count, 3) // work, rest, work
        XCTAssertEqual(tDrillSteps.filter(\.isWork).count, 2)
        guard case let .rest(seconds) = tDrillSteps[1].kind else {
            return XCTFail("expected a rest between the two drill sets")
        }
        XCTAssertEqual(seconds, 60)
        guard case let .work(.continuousDistance(targetMeters, label)) = tDrillSteps[0].kind else {
            return XCTFail("expected continuousDistance")
        }
        XCTAssertEqual(targetMeters, 10, accuracy: 0.001) // first "10m" match
        XCTAssertEqual(label, "10m")
    }

    func testRestOverrideOnlyAppliesToDefaultRestBlocks() {
        let day = speedDevelopmentDay()
        let tDrillID = day.exercises[1].id

        let plan = GuidedRunPlanBuilder.build(day: day, restOverrides: [tDrillID: 45])
        XCTAssertEqual(plan.blocks[1].restSeconds, 45)

        // Overriding a block whose rest is NOT a default (shuttle blocks
        // with structured restSeconds:90) must be ignored.
        let anaerobicDay = anaerobicRunDay()
        let anaerobic = GuidedRunPlanBuilder.build(
            day: anaerobicDay,
            restOverrides: [anaerobicDay.exercises[0].id: 10]
        )
        XCTAssertEqual(anaerobic.blocks[0].restSeconds, 90)
    }

    // MARK: - Rest resolution priority

    func testRestResolutionPrefersStructuredThenParsedThenDefault() {
        let target = ConditioningTargetParser.parse(detail: nil)

        let structured = ProgramExercise(
            name: "X", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: 45, group: nil, detail: "rest 90\""
        )
        let structuredResult = GuidedRunPlanBuilder.resolveRest(for: structured, target: target)
        XCTAssertEqual(structuredResult.seconds, 45, "structured restSeconds must win over text")
        XCTAssertFalse(structuredResult.isDefault)

        let parsedEnglish = ProgramExercise(
            name: "X", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, detail: "rest 45\""
        )
        let parsedResult = GuidedRunPlanBuilder.resolveRest(for: parsedEnglish, target: target)
        XCTAssertEqual(parsedResult.seconds, 45)
        XCTAssertFalse(parsedResult.isDefault)

        let parsedItalian = ProgramExercise(
            name: "X", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, detail: "1' rec"
        )
        let italianResult = GuidedRunPlanBuilder.resolveRest(for: parsedItalian, target: target)
        XCTAssertEqual(italianResult.seconds, 60)
        XCTAssertFalse(italianResult.isDefault)

        let recupero = ProgramExercise(
            name: "X", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, detail: "recupero 30\""
        )
        let recuperoResult = GuidedRunPlanBuilder.resolveRest(for: recupero, target: target)
        XCTAssertEqual(recuperoResult.seconds, 30)
        XCTAssertFalse(recuperoResult.isDefault)

        // Combined minutes + seconds ("1'30\"" = 90s) must not silently
        // drop the seconds portion by matching only the bare-minutes shape.
        let combined = ProgramExercise(
            name: "X", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, detail: "rec 1'30\""
        )
        let combinedResult = GuidedRunPlanBuilder.resolveRest(for: combined, target: target)
        XCTAssertEqual(combinedResult.seconds, 90)
        XCTAssertFalse(combinedResult.isDefault)

        let combinedTrailingKeyword = ProgramExercise(
            name: "X", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, detail: "1'30\" recupero"
        )
        let combinedTrailingResult = GuidedRunPlanBuilder.resolveRest(for: combinedTrailingKeyword, target: target)
        XCTAssertEqual(combinedTrailingResult.seconds, 90)
        XCTAssertFalse(combinedTrailingResult.isDefault)

        let none = ProgramExercise(
            name: "X", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
            weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil, detail: nil
        )
        let repsDistanceTarget = ConditioningTargetParser.parse(detail: "4 reps of 25y in < 65\"")
        let defaultResult = GuidedRunPlanBuilder.resolveRest(for: none, target: repsDistanceTarget)
        XCTAssertEqual(defaultResult.seconds, 90)
        XCTAssertTrue(defaultResult.isDefault)

        let drillDefault = GuidedRunPlanBuilder.resolveRest(for: none, target: target)
        XCTAssertEqual(drillDefault.seconds, 60)
        XCTAssertTrue(drillDefault.isDefault)
    }

    // MARK: - intervalSets shape

    func testIntervalSetsTextBuildsCountedRounds() throws {
        let day = ProgramDay(
            weekday: 3,
            title: "Ladder",
            focus: WorkoutType.conditioning.rawValue,
            exercises: [
                ProgramExercise(
                    name: "Ladder Drill", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                    weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: nil,
                    detail: "2 x 10times"
                ),
            ]
        )
        let plan = GuidedRunPlanBuilder.build(day: day)
        XCTAssertEqual(plan.steps.filter(\.isWork).count, 20)
        guard case let .work(.round(index, of)) = try XCTUnwrap(plan.steps.first(where: \.isWork)?.kind) else {
            return XCTFail("expected round")
        }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(of, 20)
    }

    // MARK: - Lift day guard

    func testStrengthDayBuildsEmptyPlan() {
        let day = ProgramDay(weekday: 1, title: "Upper", focus: WorkoutType.upper.rawValue, exercises: [
            ProgramExercise(
                name: "Bench",
                exerciseID: nil,
                sets: 3,
                repsLow: 8,
                repsHigh: nil,
                weightKg: nil,
                rpe: nil,
                percentOf1RM: nil,
                restSeconds: nil,
                group: nil
            ),
        ])
        let plan = GuidedRunPlanBuilder.build(day: day)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.blocks.isEmpty)
    }
}
