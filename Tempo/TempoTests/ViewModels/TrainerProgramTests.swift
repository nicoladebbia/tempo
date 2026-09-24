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

    /// 2026-09-21 is a Monday.
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
        let key = p.sessionKey(weekIndex: 0, dayIndex: 0)
        XCTAssertEqual(p.day(forSessionKey: key)?.workoutType, .pull)
        XCTAssertNil(p.day(forSessionKey: "bogus#0#5"))
    }

    func testLiftAndConditioningSameDayBecomeATwoPartDay() {
        let run = ProgramDay(
            weekday: 2, title: "Anaerobic run", focus: "sprint",
            exercises: [ProgramExercise(name: "Shuttle 1", sets: 1, repsLow: 1, detail: "4 × 25y out and back < 65\"")]
        )
        let p = program(weeks: [ProgramWeek(days: [day(2, "legs"), run, ProgramDay(
            weekday: 4, title: "Aerobic run", focus: "run",
            exercises: [ProgramExercise(name: "Fartlek", sets: 1, repsLow: 1, detail: "35'")]
        )])])
        let tue = WorkoutPlan(date: date("2026-09-22"), type: .pull)
        let thu = WorkoutPlan(date: date("2026-09-24"), type: .push)

        TrainingViewModel.applyTrainerProgram(p, to: [tue, thu], matchDayKeys: [])

        XCTAssertEqual(tue.type, .legs)
        XCTAssertEqual(tue.secondarySessionType, .sprint)
        XCTAssertEqual(p.day(forSessionKey: tue.programSecondaryKey ?? "")?.title, "Anaerobic run")
        XCTAssertEqual(thu.type, .run, "conditioning-only day becomes a run day")
        XCTAssertNotNil(thu.programSessionKey)
    }

    func testTwoConditioningSessionsSameDayBothShow() {
        let a = ProgramDay(
            weekday: 3,
            title: "Aerobic",
            focus: "run",
            exercises: [ProgramExercise(name: "Run", sets: 1, repsLow: 1, detail: "15'")]
        )
        let b = ProgramDay(
            weekday: 3,
            title: "Speed",
            focus: "sprint",
            exercises: [ProgramExercise(name: "T Drill", sets: 1, repsLow: 1, detail: "2 × 10")]
        )
        let p = program(weeks: [ProgramWeek(days: [a, b])])
        let wed = WorkoutPlan(date: date("2026-09-23"), type: .push)

        TrainingViewModel.applyTrainerProgram(p, to: [wed], matchDayKeys: [])

        XCTAssertEqual(wed.type, .run)
        XCTAssertEqual(wed.secondarySessionType, .sprint, "second conditioning session isn't dropped")
        XCTAssertEqual(p.day(forSessionKey: wed.programSecondaryKey ?? "")?.title, "Speed")
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
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
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

    /// Fix #9 — `ProgramExercise.perSide` must survive import onto the
    /// `PlannedExercise` the athlete actually trains from, with reps carried
    /// through UN-doubled (the trainer's "8 per side" stays targetReps: 8).
    func testPopulateCarriesPerSideFlagWithoutDoublingReps() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let row = Exercise(
            name: "SA DB Row", muscleGroup: .back, equipment: .dumbbell,
            movementPattern: .horizontalPull, isCompound: true
        )
        context.insert(row)
        let items = [
            ProgramExercise(name: "SA DB Row", sets: 3, repsLow: 8, weightKg: 20, perSide: true),
            ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8, weightKg: 60),
        ]
        let p = program(weeks: [ProgramWeek(days: [day(1, "pull", exercises: items)])])
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .pull)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        let slots = plan.orderedExercises
        XCTAssertTrue(slots[0].perSide, "trainer wrote per-side reps for this exercise")
        XCTAssertFalse(slots[1].perSide, "a normal bilateral exercise stays false")
        XCTAssertEqual(slots[0].orderedSets.first(where: { !$0.isWarmup })?.targetReps, 8, "never doubled")
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

    // MARK: - Today row follows a newly activated program

    func testActivatingAProgramReplacesAStalePlannedToday() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let vm = TrainingViewModel(
            trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        // Today already persisted as a generated gym day.
        let first = vm.ensureTodayPlanPersisted(modelContext: context).plan
        first.type = .push
        try context.save()

        // A program that trains only on a weekday that isn't today.
        let todayWeekday = TrainerProgram.isoWeekday(of: Date())
        let otherWeekday = todayWeekday == 1 ? 2 : 1
        context.insert(TrainerProgram(
            name: "PT", startDate: Date(),
            weeks: [ProgramWeek(days: [day(otherWeekday, "legs")])],
            sourceKind: "text"
        ))
        try context.save()

        vm.loadWeekPlan(modelContext: context)
        let resolved = vm.ensureTodayPlanPersisted(modelContext: context).plan

        XCTAssertNotEqual(resolved.type, .push, "stale generated push day was replaced")
        XCTAssertFalse(resolved.type.isGymWorkout, "not a program day → no lifting")
        XCTAssertTrue(vm.weekPlans.contains { $0 === resolved }, "Week Plan shows the same object as Today")
    }

    // MARK: - #4 — trainer target + adjustment note recorded

    func testYellowRecoveryRecordsTrainerTargetAndAdjustmentNote() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let items = [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 5, weightKg: 100)]
        let p = program(weeks: [ProgramWeek(days: [day(1, "push", exercises: items)])])
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .push, recoveryAdjustment: 0.8)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        let slot = plan.orderedExercises[0]
        XCTAssertEqual(slot.trainerTargetKg, 100, "the trainer's own number, unadjusted")
        XCTAssertEqual(slot.loadAdjustmentNote, "Recovery yellow −20%")
        let working = slot.orderedSets.first { !$0.isWarmup }
        XCTAssertEqual(working?.targetWeight, 80, "100 kg x 0.8 recovery")
    }

    func testPainNoteRecordsCappedAdjustmentNote() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let fly = Exercise(
            name: "Cable Fly", muscleGroup: .chest, equipment: .cable,
            movementPattern: .isolation, isCompound: false
        )
        context.insert(fly)
        let lastSession = ExerciseHistory(date: Date(), bestSetWeight: 20, exercise: fly)
        context.insert(lastSession)
        let painNote = SetFeedback(exerciseID: fly.id, rpe: 8, note: "sharp shoulder pain on this")
        painNote.userProvidedFeedback = true
        context.insert(painNote)
        let items = [ProgramExercise(name: "Cable Fly", sets: 3, repsLow: 12, weightKg: 30)]
        let p = program(weeks: [ProgramWeek(days: [day(1, "push", exercises: items)])])
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .push)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        let slot = plan.orderedExercises[0]
        XCTAssertEqual(slot.trainerTargetKg, 30, "the trainer's own number, unadjusted")
        XCTAssertEqual(slot.loadAdjustmentNote, "Pain note — capped at last session")
        let working = slot.orderedSets.first { !$0.isWarmup }
        XCTAssertEqual(working?.targetWeight, 20, "capped at last session's 20 kg, not the trainer's 30")
    }

    func testUseTrainerWeightRestoresTargetForRemainingSetsOnly() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .push)
        plan.status = .inProgress
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.trainerTargetKg = 100
        slot.loadAdjustmentNote = "Recovery yellow −20%"
        let warm1 = PlannedSet(setNumber: 1, targetReps: 5, targetWeight: 40, isWarmup: true, plannedExercise: slot)
        let warm2 = PlannedSet(setNumber: 2, targetReps: 5, targetWeight: 60, isWarmup: true, plannedExercise: slot)
        let completed = PlannedSet(
            setNumber: 3, targetReps: 5, targetWeight: 80,
            actualReps: 5, actualWeight: 80, completed: true, plannedExercise: slot
        )
        let pending = PlannedSet(setNumber: 4, targetReps: 5, targetWeight: 80, plannedExercise: slot)
        slot.sets = [warm1, warm2, completed, pending]
        context.insert(slot)
        context.insert(warm1)
        context.insert(warm2)
        context.insert(completed)
        context.insert(pending)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.useTrainerWeight(for: slot, modelContext: context)

        XCTAssertEqual(completed.targetWeight, 80, "a logged set is never rewritten")
        XCTAssertEqual(pending.targetWeight, 100, "remaining working set restored to the trainer's number")
        XCTAssertEqual(warm1.targetWeight, 50, "re-ramped 50% off the restored target")
        XCTAssertEqual(warm2.targetWeight, 75, "re-ramped 75% off the restored target")
        XCTAssertTrue(slot.trainerOverrideApplied, "records that the athlete overrode")
    }

    // MARK: - #5 — % read as a weight vs. an effort target

    func testReliableE1RMPercentResolvesToAWeight() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let squat = Exercise(
            name: "Barbell Back Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        context.insert(squat)
        let recent = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -10, to: Date()))
        context.insert(ExerciseHistory(date: recent, estimated1RM: 150, exercise: squat))
        let items = [ProgramExercise(name: "Barbell Back Squat", sets: 3, repsLow: 5, percentOf1RM: 0.8)]
        let p = program(weeks: [ProgramWeek(days: [day(1, "legs", exercises: items)])])
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .legs)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        let slot = plan.orderedExercises[0]
        XCTAssertEqual(slot.trainerTargetKg, 120, "150 kg e1RM x 80%")
        let working = slot.orderedSets.first { !$0.isWarmup }
        XCTAssertEqual(working?.targetWeight, 120)
        XCTAssertFalse(working?.isCalibration ?? true)
    }

    func testUnreliableE1RMReadsPercentAsEffortWithCalibration() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let press = Exercise(
            name: "Overhead Press", muscleGroup: .shoulders, equipment: .barbell,
            movementPattern: .verticalPush, isCompound: true
        )
        context.insert(press)
        // Outside the ~90-day reliability window — too stale to read a % against.
        let stale = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -120, to: Date()))
        context.insert(ExerciseHistory(date: stale, estimated1RM: 60, exercise: press))
        let items = [ProgramExercise(name: "Overhead Press", sets: 3, repsLow: 8, percentOf1RM: 0.7)]
        let p = program(weeks: [ProgramWeek(days: [day(1, "push", exercises: items)])])
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .push)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        let slot = plan.orderedExercises[0]
        XCTAssertNil(slot.trainerTargetKg, "a stale e1RM isn't reliable enough to read the % against")
        let sets = slot.orderedSets
        XCTAssertFalse(sets.isEmpty)
        XCTAssertTrue(sets.allSatisfy { $0.targetWeight == nil }, "no pre-filled weight")
        XCTAssertEqual(sets.filter(\.isCalibration).count, 1, "exactly the first working set")
        XCTAssertTrue(sets.first?.isCalibration ?? false)
        XCTAssertEqual(sets.first?.targetRIR, 5, "~13 reps possible at 70% (Epley) − 8 prescribed = 5")
        XCTAssertTrue(sets.allSatisfy { !$0.isWarmup }, "no ramp toward an unknown weight")
    }

    func testIsolationEquipmentPercentIsAlwaysEffortEvenWithAReliableMax() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let legExtension = Exercise(
            name: "Leg Extension", muscleGroup: .quads, equipment: .machine,
            movementPattern: .isolation, isCompound: false
        )
        context.insert(legExtension)
        context.insert(ExerciseHistory(date: Date(), estimated1RM: 60, exercise: legExtension))
        let items = [ProgramExercise(name: "Leg Extension", sets: 3, repsLow: 12, percentOf1RM: 0.7)]
        let p = program(weeks: [ProgramWeek(days: [day(1, "legs", exercises: items)])])
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .legs)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        let slot = plan.orderedExercises[0]
        XCTAssertNil(slot.trainerTargetKg, "a machine lift's % is never e1RM × %, even with a known max")
        XCTAssertTrue(slot.orderedSets.first?.isCalibration ?? false)
    }

    func testCalibrationPropagatesE1RMToRemainingSetsAtTheirOwnRepsSnapped() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let squat = Exercise(
            name: "Barbell Back Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        context.insert(squat)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .legs)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: squat)
        let calibration = PlannedSet(setNumber: 1, targetReps: 8, isCalibration: true, plannedExercise: slot)
        let sameReps = PlannedSet(setNumber: 2, targetReps: 8, plannedExercise: slot)
        let fewerReps = PlannedSet(setNumber: 3, targetReps: 5, plannedExercise: slot)
        slot.sets = [calibration, sameReps, fewerReps]
        context.insert(calibration)
        context.insert(sameReps)
        context.insert(fewerReps)
        context.insert(slot)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.propagateCalibration(from: calibration, weight: 100, reps: 8, modelContext: context)

        // e1RM = 100 x (1 + 8/30) ≈ 126.667
        XCTAssertEqual(sameReps.targetWeight ?? 0, 100, accuracy: 0.01, "round-trips at the SAME reps")
        XCTAssertEqual(fewerReps.targetWeight ?? 0, 107.5, accuracy: 0.01, "heavier at fewer reps, snapped to 2.5 kg")
        XCTAssertNil(calibration.targetWeight, "the calibration set's own row is untouched")
    }

    // MARK: - #13 — Tempo warm-up sets on/off

    func testAutoWarmupsOffBuildsNoRampOnTrainerDay() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let items = [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 5, weightKg: 80)]
        let p = TrainerProgram(
            name: "PT", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push", exercises: items)])],
            sourceKind: "text", autoWarmups: false
        )
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .push)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        XCTAssertTrue(
            plan.orderedExercises[0].orderedSets.allSatisfy { !$0.isWarmup },
            "autoWarmups off — no Tempo ramp sets"
        )
    }

    func testAutoWarmupsDefaultsOnAndBuildsRamp() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let items = [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 5, weightKg: 80)]
        // autoWarmups nil (never set) — nil-means-true default.
        let p = program(weeks: [ProgramWeek(days: [day(1, "push", exercises: items)])])
        XCTAssertNil(p.autoWarmups)
        XCTAssertTrue(p.warmupsEnabled)
        context.insert(p)
        let plan = WorkoutPlan(date: date("2026-09-21"), type: .push)
        plan.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.populateExercises(for: plan, modelContext: context)

        // Built (and, in TodayWorkoutView/ActiveWorkoutView/WorkoutHistoryView,
        // labelled "Tempo warm-up" wherever sets are listed — see
        // `prescriptionText(isTrainerDay:)` / the warm-up chip / the per-set row).
        XCTAssertTrue(
            plan.orderedExercises[0].orderedSets.contains { $0.isWarmup },
            "autoWarmups on (default) — Tempo builds its ramp"
        )
    }
}
