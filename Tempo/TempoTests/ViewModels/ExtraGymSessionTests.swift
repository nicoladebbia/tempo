//
// ExtraGymSessionTests.swift
// Tempo
//
// Add / remove a gym session on a soccer day: one composite row (gym anchor +
// completed football companion), the football ActivitySession is never lost,
// the throwaway-VM ensurer keeps the row, sRPE moves with the part it belongs
// to, and a manually logged soccer start time is persisted.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ExtraGymSessionTests: XCTestCase {
    private var context: ModelContext!
    private var vm: TrainingViewModel!
    private var today: Date!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = ModelContext(container)
        today = Calendar.current.startOfDay(for: Date())
        let weekday = Calendar.current.component(.weekday, from: today)
        let settings = UserSettings()
        settings.footballDays = ActiveDays(rawValue: 1 << ((weekday + 5) % 7))
        context.insert(settings)
        seedLibrary()
        vm = makeVM()
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
    }

    private func seedLibrary() {
        let defs: [(String, MuscleGroup, Equipment, MovementPattern, Bool)] = [
            ("Barbell Bench Press", .chest, .barbell, .horizontalPush, true),
            ("Overhead Press", .shoulders, .barbell, .verticalPush, true),
            ("Barbell Row", .back, .barbell, .horizontalPull, true),
            ("Pull-Up", .back, .pullUpBar, .verticalPull, true),
            ("Barbell Squat", .quads, .barbell, .squat, true),
            ("Romanian Deadlift", .hamstrings, .barbell, .hinge, true),
            ("Tricep Pushdown", .triceps, .cable, .isolation, false),
            ("Barbell Curl", .biceps, .barbell, .isolation, false),
            ("Lateral Raise", .shoulders, .dumbbell, .isolation, false),
            ("Leg Extension", .quads, .machine, .isolation, false),
        ]
        for d in defs {
            context.insert(Exercise(name: d.0, muscleGroup: d.1, equipment: d.2, movementPattern: d.3, isCompound: d.4))
        }
        try? context.save()
    }

    /// Persisted football day, logged as played at 10:00.
    private func playedFootballAt10() -> WorkoutPlan {
        let plan = WorkoutPlan(date: today, type: .football)
        context.insert(plan)
        try? context.save()
        vm.todayPlan = plan
        let ten = Calendar.current.date(byAdding: .hour, value: 10, to: today)!
        vm.persistNonGymCompletion(whoop: nil, startTime: ten, modelContext: context)
        return plan
    }

    private func decision(gymAt: Int = 18 * 60, focus: WorkoutType? = .upper) -> ExtraGymDecision {
        let ctx = vm.extraGymContext(gymStartMin: gymAt, requestedFocus: focus, modelContext: context)!
        return ExtraGymSessionPlanner.decide(ctx)
    }

    private func footballSessions() -> [ActivitySession] {
        let football = WorkoutType.football.rawValue
        return (try? context.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.workoutType == football }
        ))) ?? []
    }

    // MARK: - T7

    func testManualLogPersistsTheChosenStartTime() throws {
        let plan = playedFootballAt10()
        let session = try XCTUnwrap(footballSessions().first)
        XCTAssertEqual(TrainingViewModel.minutesSinceMidnight(session.startTime), 600)
        XCTAssertEqual(session.source, "manual")
        XCTAssertEqual(plan.status, .completed)
    }

    // MARK: - T3

    func testAddGymSessionBuildsCompositeDay() {
        let plan = playedFootballAt10()
        plan.sessionRPE = 7
        let d = decision()
        XCTAssertTrue(vm.addGymSession(decision: d, gymStartMin: 18 * 60, modelContext: context))

        XCTAssertEqual(plan.type, d.focus)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertTrue(plan.isCompositeDay)
        XCTAssertEqual(plan.companionType, .football)
        XCTAssertEqual(plan.companionStartMin, 600)
        XCTAssertTrue(plan.companionCompleted)
        XCTAssertTrue(plan.dayTrained, "Football counts as trained even before the gym part")
        XCTAssertEqual(plan.companionSessionRPE, 7, "Soccer sRPE moves to the companion")
        XCTAssertNil(plan.sessionRPE)
        XCTAssertEqual(plan.scheduledStartMin, 18 * 60)
        XCTAssertFalse(plan.orderedExercises.isEmpty)
        XCTAssertEqual(footballSessions().count, 1, "Football ActivitySession is kept")
        XCTAssertEqual(footballSessions().first?.workoutPlanID, plan.id)
    }

    func testHeavyLowerNeverOnSoccerDay() {
        _ = playedFootballAt10()
        let d = decision(gymAt: 19 * 60, focus: .fullBody)
        XCTAssertTrue(vm.addGymSession(decision: d, gymStartMin: 19 * 60, modelContext: context))
        let names = vm.todayPlan?.orderedExercises.compactMap { $0.exercise?.name } ?? []
        XCTAssertFalse(names.contains("Barbell Squat"))
        XCTAssertFalse(names.contains("Romanian Deadlift"))
    }

    func testRemoveGymSessionRestoresFootball() {
        let plan = playedFootballAt10()
        plan.sessionRPE = 6
        XCTAssertTrue(vm.addGymSession(decision: decision(), gymStartMin: 18 * 60, modelContext: context))
        XCTAssertTrue(vm.removeGymSession(modelContext: context))

        XCTAssertEqual(plan.type, .football)
        XCTAssertEqual(plan.status, .completed)
        XCTAssertFalse(plan.isCompositeDay)
        XCTAssertEqual(plan.sessionRPE, 6, "sRPE returns to the football")
        XCTAssertTrue(plan.orderedExercises.isEmpty)
        XCTAssertEqual(footballSessions().count, 1)
    }

    func testCannotRemoveOnceASetIsLogged() {
        let plan = playedFootballAt10()
        XCTAssertTrue(vm.addGymSession(decision: decision(), gymStartMin: 18 * 60, modelContext: context))
        plan.orderedExercises.first?.orderedSets.first?.completed = true
        XCTAssertFalse(vm.removeGymSession(modelContext: context))
        XCTAssertTrue(plan.isCompositeDay)
    }

    func testAddLogsFootballFirstWhenNotLoggedYet() throws {
        let plan = WorkoutPlan(date: today, type: .football)
        context.insert(plan)
        try context.save()
        vm.todayPlan = plan
        let ten = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: 10, to: today))
        let ctx = try XCTUnwrap(vm.extraGymContext(gymStartMin: 18 * 60, soccerStart: ten, modelContext: context))
        let d = ExtraGymSessionPlanner.decide(ctx)
        XCTAssertTrue(vm.addGymSession(decision: d, gymStartMin: 18 * 60, soccerStart: ten, modelContext: context))
        XCTAssertEqual(footballSessions().count, 1)
        XCTAssertEqual(plan.companionStartMin, 600)
    }

    // MARK: - T2

    func testThrowawayVMEnsurerKeepsTheCompositeRow() throws {
        let plan = playedFootballAt10()
        XCTAssertTrue(vm.addGymSession(decision: decision(), gymStartMin: 18 * 60, modelContext: context))
        let focus = plan.type
        let exerciseCount = plan.orderedExercises.count

        // DailyResetCoordinator's ensurer: a fresh VM on every Dashboard refresh.
        let throwaway = makeVM()
        let resolved = throwaway.ensureTodayPlanPersisted(modelContext: context)
        XCTAssertTrue(resolved.plan === plan, "Same row survives the football template")
        XCTAssertEqual(resolved.plan.type, focus)
        XCTAssertEqual(resolved.plan.orderedExercises.count, exerciseCount)
        XCTAssertTrue(resolved.plan.isCompositeDay)
        // (loadWeekPlan also leaves auto-inserted future .planned rows — that
        // pre-dates this feature; only today's row is asserted here.)
        let todayRows = try context.fetch(FetchDescriptor<WorkoutPlan>()).filter {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        XCTAssertEqual(todayRows.count, 1)
    }

    // MARK: - T8

    func testCompletingTheGymPartKeepsTheFootballSession() {
        let plan = playedFootballAt10()
        XCTAssertTrue(vm.addGymSession(decision: decision(), gymStartMin: 18 * 60, modelContext: context))
        plan.status = .inProgress
        for slot in plan.orderedExercises {
            for set in slot.orderedSets where !set.isWarmup {
                set.completed = true
                set.actualWeight = set.targetWeight ?? 20
                set.actualReps = set.targetReps
            }
        }
        XCTAssertTrue(vm.persistCompletion(modelContext: context))
        XCTAssertEqual(plan.status, .completed)
        XCTAssertEqual(footballSessions().count, 1, "Football ActivitySession survives gym completion")
        XCTAssertTrue(plan.dayTrained)
    }

    // MARK: - T6

    func testScheduleProviderEmitsFootballAsSecondaryOnCompositeDay() throws {
        let plan = playedFootballAt10()
        XCTAssertTrue(vm.addGymSession(decision: decision(), gymStartMin: 18 * 60, modelContext: context))
        let week = TrainingScheduleProvider.weekSchedule(
            containing: today, trainingEngine: TrainingEngine(), whoop: MockWhoopService(),
            healthKit: MockHealthKitService(), modelContext: context
        )
        let day = try XCTUnwrap(week.first { Calendar.current.isDate($0.date, inSameDayAs: today) })
        XCTAssertEqual(day.mainType, plan.type)
        XCTAssertEqual(day.secondaryType, .football)
        let label = WeeklyTrainingSchedule.build(from: [day]).byWeekday[day.weekday]
        XCTAssertEqual(label, "\(plan.type.displayName) + Football")
    }
}
