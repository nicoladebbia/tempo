//
// TrainerProgramTests.swift
// Tempo
//
// Following a trainer's program: which week/day applies on a date, how it
// overlays the generated week (trainer days replace gym days; football,
// matches and red-recovery mobility stay), and how a session's exercises and
// loads are built.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainerProgramTests: XCTestCase {
    private let cal = TrainingCalendar.iso8601

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!
    }

    private func day(_ weekday: Int, _ focus: String = "upper", exercises: [ProgramExercise]? = nil) -> ProgramDay {
        ProgramDay(
            weekday: weekday,
            title: "Day \(weekday)",
            focus: focus,
            exercises: exercises ?? [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8)]
        )
    }

    // 2026-09-21 is a Monday.
    private func program(weeks: [ProgramWeek], repeats: Bool = true) -> TrainerProgram {
        TrainerProgram(name: "PT", startDate: date("2026-09-21"), weeks: weeks, repeats: repeats, sourceKind: "text")
    }

    // MARK: - Schedule

    func testOneWeekProgramRepeatsForever() {
        let p = program(weeks: [ProgramWeek(days: [day(1)])])
        XCTAssertEqual(p.weekIndex(on: date("2026-09-21")), 0)
        XCTAssertEqual(p.weekIndex(on: date("2026-12-07")), 0)
        XCTAssertNil(p.weekIndex(on: date("2026-09-20")), "before the start")
    }

    func testMultiWeekBlockAdvancesThenRepeatsOrEnds() {
        let weeks = (0 ..< 3).map { _ in ProgramWeek(days: [day(1)]) }
        let looping = program(weeks: weeks)
        XCTAssertEqual(looping.weekIndex(on: date("2026-09-28")), 1)
        XCTAssertEqual(looping.weekIndex(on: date("2026-10-11")), 2, "Sunday of week 3")
        XCTAssertEqual(looping.weekIndex(on: date("2026-10-12")), 0, "loops to week 1")

        let ending = program(weeks: weeks, repeats: false)
        XCTAssertNil(ending.weekIndex(on: date("2026-10-12")))
        XCTAssertTrue(ending.isFinished(on: date("2026-10-12")))
    }

    func testSessionMatchesIsoWeekday() {
        let p = program(weeks: [ProgramWeek(days: [day(1), day(3), day(7, "legs")])])
        XCTAssertEqual(p.session(on: date("2026-09-23"))?.day.weekday, 3, "Wednesday")
        XCTAssertEqual(p.session(on: date("2026-09-27"))?.day.workoutType, .legs, "Sunday = 7")
        XCTAssertNil(p.session(on: date("2026-09-22")), "Tuesday not programmed")
    }

    func testSessionKeyRoundTrips() {
        let p = program(weeks: [ProgramWeek(days: [day(5, "pull")])])
        let key = p.sessionKey(weekIndex: 0, weekday: 5)
        XCTAssertEqual(p.day(forSessionKey: key)?.workoutType, .pull)
        XCTAssertNil(p.day(forSessionKey: "bogus#0#5"))
    }

    // MARK: - Overlay

    func testOverlayReplacesGymDaysKeepsFootballMatchesAndRedRecovery() {
        let p = program(weeks: [ProgramWeek(days: [day(1, "legs"), day(3, "upper"), day(4, "pull"), day(5, "push")])])
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .push)
        let tue = WorkoutPlan(date: date("2026-09-22"), type: .pull)
        let wed = WorkoutPlan(date: date("2026-09-23"), type: .football)
        let thu = WorkoutPlan(date: date("2026-09-24"), type: .mobility, recoveryAdjustment: 0)
        let fri = WorkoutPlan(date: date("2026-09-25"), type: .legs)
        let sat = WorkoutPlan(date: date("2026-09-26"), type: .conditioning)
        let match = Calendar.current.startOfDay(for: date("2026-09-25"))

        TrainingViewModel.applyTrainerProgram(p, to: [mon, tue, wed, thu, fri, sat], matchDayKeys: [match])

        XCTAssertEqual(mon.type, .legs)
        XCTAssertNotNil(mon.programSessionKey)
        XCTAssertEqual(tue.type, .rest, "gym day not on the program → rest")
        XCTAssertEqual(wed.type, .upper, "program day on a recurring football day → trainer session")
        XCTAssertEqual(thu.type, .mobility, "red recovery stays mobility")
        XCTAssertNil(thu.programSessionKey)
        XCTAssertEqual(fri.type, .legs, "dated match day keeps the engine's plan")
        XCTAssertNil(fri.programSessionKey)
        XCTAssertEqual(sat.type, .rest, "extra conditioning not on the program → rest")
    }

    // MARK: - Session exercises

    func testPopulateBuildsTrainerExercisesWithTheirLoadsRestAndRPE() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: false
        )
        context.insert(bench)
        let items = [
            ProgramExercise(
                name: "bench press", sets: 4, repsLow: 6, repsHigh: 8, weightKg: 100,
                rpe: 8, restSeconds: 150, group: nil, notes: "Pause at the chest"
            ),
            ProgramExercise(name: "Zercher Carry", sets: 3, repsLow: 1, group: 1),
        ]
        let p = program(weeks: [ProgramWeek(days: [day(1, "push", exercises: items)])])
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .push)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, weekday: 1)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        let slots = plan.orderedExercises
        XCTAssertEqual(slots.map(\.displayName), ["Bench Press", "Zercher Carry"])
        let benchSets = slots[0].orderedSets.filter { !$0.isWarmup }
        XCTAssertEqual(benchSets.count, 4)
        XCTAssertEqual(benchSets.first?.targetReps, 6)
        XCTAssertEqual(benchSets.first?.targetWeight, 100)
        XCTAssertEqual(benchSets.first?.targetRIR, 2, "RPE 8 → 2 reps in reserve")
        XCTAssertEqual(slots[0].restSecondsOverride, 150)
        XCTAssertEqual(slots[0].programNote, "Pause at the chest")
        XCTAssertEqual(vm.restDuration(for: slots[0]), 150)
        XCTAssertEqual(slots[1].supersetGroup, 1)
        XCTAssertEqual(slots[1].exercise?.isCustom, true, "unknown name becomes a custom exercise")
    }

    func testPercentOf1RMUsesEstimatedMax() {
        let item = ProgramExercise(name: "Squat", sets: 5, repsLow: 5, percentOf1RM: 0.8)
        let squat = Exercise(name: "Squat", muscleGroup: .quads, equipment: .barbell, movementPattern: .squat, isCompound: true)
        XCTAssertNil(TrainingViewModel.programWeightKg(item, exercise: squat), "no history → Tempo prescribes")
        XCTAssertEqual(
            TrainingViewModel.programWeightKg(ProgramExercise(name: "x", sets: 1, repsLow: 1, weightKg: 60), exercise: squat),
            60
        )
    }
}
