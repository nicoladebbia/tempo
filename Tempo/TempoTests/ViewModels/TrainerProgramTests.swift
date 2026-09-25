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

    // MARK: - Fix #6 — sequence mode

    private func sequenceProgram(
        days: [ProgramDay],
        repeats: Bool = true
    ) -> TrainerProgram {
        TrainerProgram(
            name: "Sequence PT", startDate: date("2026-09-21"), weeks: [ProgramWeek(days: days)],
            repeats: repeats, sourceKind: "text", scheduleMode: .sequence
        )
    }

    func testSequenceStepsFollowArrayOrderNotWeekday() {
        // Authored out of weekday order: index0=Fri, index1=Mon, index2=Wed.
        let p = sequenceProgram(days: [day(5, "push"), day(1, "legs"), day(3, "pull")])
        let steps = p.sequenceSteps
        XCTAssertEqual(steps.map(\.dayIndex), [0, 1, 2], "program order = array order, not weekday order")
        XCTAssertEqual(p.sequenceSession(completedCount: 0)?.day.workoutType, .push)
        XCTAssertEqual(p.sequenceSession(completedCount: 1)?.day.workoutType, .legs)
        XCTAssertEqual(p.sequenceSession(completedCount: 2)?.day.workoutType, .pull)
    }

    func testSequenceSessionRepeatsWrapsAroundSteps() {
        let p = sequenceProgram(days: [day(1, "push"), day(3, "legs")], repeats: true)
        XCTAssertEqual(p.sequenceSession(completedCount: 2)?.day.workoutType, .push, "wraps back to step 0")
        XCTAssertEqual(p.sequenceSession(completedCount: 3)?.day.workoutType, .legs)
    }

    func testSequenceSessionNonRepeatingFinishesAfterLastStep() {
        // Two weeks so the "1-week always repeats" special case doesn't apply.
        let p = TrainerProgram(
            name: "Block", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push")]), ProgramWeek(days: [day(1, "legs")])],
            repeats: false, sourceKind: "text", scheduleMode: .sequence
        )
        XCTAssertNotNil(p.sequenceSession(completedCount: 1), "step 1 (index 1) still due")
        XCTAssertNil(p.sequenceSession(completedCount: 2), "both steps done, doesn't repeat → finished")
    }

    func testSequenceModeCadenceMatchesAuthoredWeekdayCountAndAdvancesCursor() {
        // Cadence: Monday + Thursday only (2 training days/week).
        let p = sequenceProgram(days: [day(1, "push"), day(4, "legs")])
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .rest)
        let tue = WorkoutPlan(date: date("2026-09-22"), type: .rest)
        let thu = WorkoutPlan(date: date("2026-09-24"), type: .rest)

        TrainingViewModel.applyTrainerProgram(p, to: [mon, tue, thu], matchDayKeys: [])

        XCTAssertEqual(mon.type, .push, "cursor 0 → step 0 lands on the first cadence day")
        XCTAssertNotNil(mon.programSessionKey)
        XCTAssertEqual(tue.type, .rest, "Tuesday isn't in this week's cadence — no session at all")
        XCTAssertNil(tue.programSessionKey)
        XCTAssertEqual(thu.type, .legs, "cursor advanced to step 1 after Monday consumed step 0")
        XCTAssertNotNil(thu.programSessionKey)
    }

    func testSequenceModeMissedSessionCarriesForwardAcrossWeeks() {
        let p = sequenceProgram(days: [day(1, "push"), day(4, "legs")])
        // Nothing was ever completed (completedSequenceCount stays 0) — as if
        // week 1's Monday session was missed entirely.
        let week2Monday = WorkoutPlan(date: date("2026-09-28"), type: .rest)
        TrainingViewModel.applyTrainerProgram(p, to: [week2Monday], matchDayKeys: [], completedSequenceCount: 0)
        XCTAssertEqual(week2Monday.type, .push, "still step 0 — a missed session is never skipped ahead")
    }

    func testSequenceModeNeverSchedulesTwoStrengthSessionsOnConsecutiveDays() {
        // Cadence: Monday + Tuesday, BOTH strength — back to back on the
        // calendar. Yesterday (before this batch) already ran a lift.
        let p = sequenceProgram(days: [day(1, "push"), day(2, "legs")])
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .rest)
        let tue = WorkoutPlan(date: date("2026-09-22"), type: .rest)

        TrainingViewModel.applyTrainerProgram(
            p, to: [mon, tue], matchDayKeys: [], completedSequenceCount: 0, priorDayWasLift: true
        )

        XCTAssertNil(mon.programSessionKey, "step 0 deferred — yesterday was already a lift")
        XCTAssertEqual(mon.type, .rest)
        XCTAssertEqual(
            tue.programSessionKey, p.sessionKey(weekIndex: 0, dayIndex: 0),
            "the deferred step 0 (not step 1) runs the very next training day — nothing was skipped"
        )
        XCTAssertEqual(tue.type, .push)
    }

    // MARK: - Fix #6 — missed fixed-mode session (Today's swap banner)

    func testMissedFixedSessionFindsMostRecentUncompletedTrainerDay() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let p = TrainerProgram(
            name: "PT", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push")])], sourceKind: "text"
        )
        context.insert(p)
        // Monday's session was never touched — it's missed by Tuesday.
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .push, status: .planned)
        mon.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(mon)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        let missed = vm.missedFixedSession(asOf: date("2026-09-22"), modelContext: context)

        XCTAssertNotNil(missed)
        XCTAssertEqual(missed?.sessionKey, p.sessionKey(weekIndex: 0, dayIndex: 0))
        XCTAssertEqual(missed?.date, date("2026-09-21"))
    }

    func testMissedFixedSessionSkipsACompletedDay() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let p = TrainerProgram(
            name: "PT", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push")])], sourceKind: "text"
        )
        context.insert(p)
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .push, status: .completed)
        mon.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(mon)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        XCTAssertNil(vm.missedFixedSession(asOf: date("2026-09-22"), modelContext: context), "Monday was done — nothing missed")
    }

    func testMissedFixedSessionIgnoresSequenceModePrograms() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let p = sequenceProgram(days: [day(1, "push")])
        context.insert(p)
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .push, status: .planned)
        mon.programSessionKey = p.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(mon)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        XCTAssertNil(
            vm.missedFixedSession(asOf: date("2026-09-22"), modelContext: context),
            "sequence mode carries forward on its own — no separate 'missed' banner"
        )
    }

    func testSwapInMissedSessionReplacesTodaysPlannedRow() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let items = [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 5, weightKg: 60)]
        let p = TrainerProgram(
            name: "PT", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push", exercises: items)])], sourceKind: "text"
        )
        context.insert(p)
        try context.save()

        // Real engine — `ensureTodayPlanPersisted` (called inside
        // `swapInMissedSession`) needs a real week-plan resolution, not the
        // trivial stub MockTrainingEngine returns.
        let vm = TrainingViewModel(
            trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        let missed = TrainingViewModel.MissedTrainerSession(
            date: date("2026-09-21"),
            sessionKey: p.sessionKey(weekIndex: 0, dayIndex: 0),
            day: p.weeks[0].days[0]
        )
        vm.swapInMissedSession(missed, modelContext: context)

        let today = vm.ensureTodayPlanPersisted(modelContext: context).plan
        XCTAssertEqual(today.programSessionKey, missed.sessionKey)
        XCTAssertEqual(today.type, .push)
        XCTAssertEqual(today.orderedExercises.map(\.displayName), ["Bench Press"], "today's exercises rebuilt from the missed session")
    }

    // MARK: - Fix #11(a) — edit re-apply doesn't orphan Today

    func testReapplyEditedProgramTodayRebuildsStaleExercises() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        let row = Exercise(
            name: "Barbell Row", muscleGroup: .back, equipment: .barbell,
            movementPattern: .horizontalPull, isCompound: true
        )
        context.insert(bench)
        context.insert(row)
        let p = TrainerProgram(
            name: "PT", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push", exercises: [
                ProgramExercise(name: "Barbell Row", sets: 3, repsLow: 8),
            ])])],
            isActive: true, sourceKind: "text"
        )
        context.insert(p)
        let key = p.sessionKey(weekIndex: 0, dayIndex: 0)

        // Today's row was populated from the PRE-edit content (Bench Press)
        // and is still stale relative to `p` above (now Barbell Row).
        let today = WorkoutPlan(date: Calendar.current.startOfDay(for: Date()), type: .push, status: .planned)
        today.programSessionKey = key
        context.insert(today)
        let stale = PlannedExercise(order: 0, workoutPlan: today, exercise: bench)
        context.insert(stale)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        vm.reapplyEditedProgramToday(program: p, modelContext: context)

        XCTAssertEqual(today.orderedExercises.map(\.displayName), ["Barbell Row"], "rebuilt from the EDITED program content")
    }

    func testTrainerProgramSaverUpdateEditsInPlaceKeepingSameID() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let p = try TrainerProgramSaver.save(
            name: "Original", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push", exercises: [
                ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8),
            ])])],
            repeats: true, sourceKind: "text", sourceText: nil, modelContext: context
        )
        let originalID = p.id

        try TrainerProgramSaver.update(
            p, name: "Renamed", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1, "push", exercises: [
                ProgramExercise(name: "Incline Bench Press", sets: 4, repsLow: 6),
            ])])],
            repeats: true, autoWarmups: false, scheduleMode: .sequence, modelContext: context,
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )

        XCTAssertEqual(p.id, originalID, "edits the SAME program object")
        XCTAssertEqual(p.name, "Renamed")
        XCTAssertEqual(p.weeks[0].days[0].exercises.first?.name, "Incline Bench Press")
        XCTAssertEqual(p.scheduleMode, .sequence)
        XCTAssertEqual(p.warmupsEnabled, false)
    }

    // MARK: - Fix #11(b) — queue the next block

    func testQueuedProgramDoesNotActivateBeforeItsDate() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let current = TrainerProgram(
            name: "Current",
            startDate: Date(),
            weeks: [ProgramWeek(days: [day(1)])],
            isActive: true,
            sourceKind: "text"
        )
        context.insert(current)
        let future = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 14, to: Date()))
        let queued = TrainerProgram(
            name: "Queued", startDate: future, weeks: [ProgramWeek(days: [day(1)])],
            isActive: false, sourceKind: "text", queuedActivationDate: future
        )
        context.insert(queued)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        let active = vm.activeTrainerProgram(modelContext: context)

        XCTAssertEqual(active?.id, current.id, "queued program not due yet — current one still runs")
        XCTAssertFalse(queued.isActive)
    }

    func testQueuedProgramPromotesOnceItsDateArrives() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let current = TrainerProgram(
            name: "Current",
            startDate: Date(),
            weeks: [ProgramWeek(days: [day(1)])],
            isActive: true,
            sourceKind: "text"
        )
        context.insert(current)
        let due = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let queued = TrainerProgram(
            name: "Queued", startDate: due, weeks: [ProgramWeek(days: [day(1)])],
            isActive: false, sourceKind: "text", queuedActivationDate: due
        )
        context.insert(queued)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        let active = vm.activeTrainerProgram(modelContext: context)

        XCTAssertEqual(active?.id, queued.id, "the due date has passed — the queued program takes over")
        XCTAssertTrue(queued.isActive)
        XCTAssertNil(queued.queuedActivationDate, "cleared once promoted")
        XCTAssertFalse(current.isActive, "the outgoing program is archived (just isActive == false)")
    }

    /// Regression — `applyTrainerProgram` must reset `previousDayWasLift` on
    /// EVERY day, including one that resolves no session AND is red-recovery
    /// at once (a cadence gap in sequence mode, or a plain non-program day
    /// in fixed mode, that the engine independently flagged red). Missing
    /// that reset left the flag stuck from an earlier lift, wrongly
    /// deferring a later, unrelated step under the consecutive-lift guard.
    func testConsecutiveLiftGuardResetsAfterAnUnrelatedRedRecoveryDay() {
        // Cadence: Monday + Wednesday, both strength.
        let p = sequenceProgram(days: [day(1, "push"), day(3, "legs")])
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .rest)
        // Tuesday isn't a cadence day at all, but the engine already flagged
        // it red-recovery (zero-multiplier mobility) — unrelated to the
        // program, and not itself a lift.
        let tue = WorkoutPlan(date: date("2026-09-22"), type: .mobility, recoveryAdjustment: 0)
        let wed = WorkoutPlan(date: date("2026-09-23"), type: .rest)

        TrainingViewModel.applyTrainerProgram(p, to: [mon, tue, wed], matchDayKeys: [])

        XCTAssertEqual(mon.type, .push, "step 0 assigned Monday")
        XCTAssertEqual(
            wed.type, .legs,
            "step 1 still assigned Wednesday — Tuesday's unrelated recovery day must not stall the guard"
        )
        XCTAssertNotNil(wed.programSessionKey)
    }

    // MARK: - Fix #11(b) regression — at most one queued program at a time

    func testSavingASecondQueuedProgramCancelsTheFirstsQueue() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let current = TrainerProgram(
            name: "Current", startDate: Date(), weeks: [ProgramWeek(days: [day(1)])],
            isActive: true, sourceKind: "text"
        )
        context.insert(current)
        try context.save()

        let firstDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: Date()))
        let first = try TrainerProgramSaver.save(
            name: "First Queued", startDate: firstDate, weeks: [ProgramWeek(days: [day(1)])],
            repeats: true, sourceKind: "text", sourceText: nil, modelContext: context,
            queuedActivationDate: firstDate
        )

        let secondDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 14, to: Date()))
        let second = try TrainerProgramSaver.save(
            name: "Second Queued", startDate: secondDate, weeks: [ProgramWeek(days: [day(1)])],
            repeats: true, sourceKind: "text", sourceText: nil, modelContext: context,
            queuedActivationDate: secondDate
        )

        XCTAssertNil(first.queuedActivationDate, "queuing a second program cancels the first's own queue")
        XCTAssertEqual(second.queuedActivationDate, secondDate, "the new queue's own date is kept as given")
        XCTAssertTrue(current.isActive, "the currently active program is untouched by queuing")
    }

    /// Regression — `promoteQueuedProgramIfDue` must settle on ONE program
    /// even if two are somehow both already due, and stay settled across
    /// repeated reads (it used to `first(where:)` non-deterministically,
    /// which could flip-flop the active program on every subsequent call).
    func testPromoteQueuedProgramPicksOneDeterministicallyAndDoesNotThrash() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let current = TrainerProgram(
            name: "Current", startDate: Date(), weeks: [ProgramWeek(days: [day(1)])],
            isActive: true, sourceKind: "text"
        )
        context.insert(current)
        let earlierDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -2, to: Date()))
        let laterDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let a = TrainerProgram(
            name: "A", startDate: earlierDue, weeks: [ProgramWeek(days: [day(1)])],
            isActive: false, sourceKind: "text", queuedActivationDate: earlierDue
        )
        let b = TrainerProgram(
            name: "B", startDate: laterDue, weeks: [ProgramWeek(days: [day(1)])],
            isActive: false, sourceKind: "text", queuedActivationDate: laterDue
        )
        context.insert(a)
        context.insert(b)
        try context.save()

        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        let first = vm.activeTrainerProgram(modelContext: context)
        let second = vm.activeTrainerProgram(modelContext: context)
        let third = vm.activeTrainerProgram(modelContext: context)

        XCTAssertEqual(first?.id, a.id, "earliest queuedActivationDate wins")
        XCTAssertEqual(second?.id, a.id, "stays settled on repeated reads")
        XCTAssertEqual(third?.id, a.id)
        XCTAssertNil(b.queuedActivationDate, "the unchosen due program's queue is cleared, not left to flip-flop later")
        XCTAssertFalse(b.isActive)
    }
}
