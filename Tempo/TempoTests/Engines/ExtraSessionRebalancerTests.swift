//
// ExtraSessionRebalancerTests.swift
// Tempo
//
// Tomorrow after "soccer + extra gym": no same-muscle stacking, hard combined
// load lightens, pre-match tomorrow goes to mobility; and the week-assembly
// hook applies it from a persisted composite row.
//

import SwiftData
@testable import Tempo
import XCTest

final class ExtraSessionRebalancerTests: XCTestCase {
    func testPullAfterPullBecomesPush() {
        let a = ExtraSessionRebalancer.adjust(
            tomorrow: .pull, extraFocus: .pull, extraIntensity: .easy, soccerLoad: .moderate
        )
        XCTAssertEqual(a?.newType, .push)
        XCTAssertTrue(a?.note.hasPrefix("Adjusted") == true)
    }

    func testPushTomorrowAfterPullIsFine() {
        XCTAssertNil(ExtraSessionRebalancer.adjust(
            tomorrow: .push, extraFocus: .pull, extraIntensity: .easy, soccerLoad: .moderate
        ))
    }

    func testAnyUpperAfterFullBodyIsSwapped() {
        for t in [WorkoutType.push, .pull, .upper] {
            let a = ExtraSessionRebalancer.adjust(
                tomorrow: t, extraFocus: .fullBody, extraIntensity: .easy, soccerLoad: .easy
            )
            XCTAssertEqual(a?.newType, .legs, "\(t)")
        }
    }

    func testPushTomorrowAfterUpperGoesToLegs() {
        let a = ExtraSessionRebalancer.adjust(
            tomorrow: .push, extraFocus: .upper, extraIntensity: .easy, soccerLoad: .easy
        )
        XCTAssertEqual(a?.newType, .legs)
    }

    func testPreMatchTomorrowGoesToMobility() {
        let a = ExtraSessionRebalancer.adjust(
            tomorrow: .pull, extraFocus: .pull, extraIntensity: .moderate, soccerLoad: .hard,
            tomorrowIsPreMatch: true
        )
        XCTAssertEqual(a?.newType, .mobility)
    }

    func testHardCombinedLoadWithoutOverlapIsNotDoubleCounted() {
        XCTAssertNil(ExtraSessionRebalancer.adjust(
            tomorrow: .legs, extraFocus: .push, extraIntensity: .moderate, soccerLoad: .hard
        ), "The brain already sees football + gym next morning")
    }

    func testEasyAfterEasyIsUntouched() {
        XCTAssertNil(ExtraSessionRebalancer.adjust(
            tomorrow: .legs, extraFocus: .push, extraIntensity: .easy, soccerLoad: .moderate
        ))
    }

    func testNonGymTomorrowIsUntouched() {
        XCTAssertNil(ExtraSessionRebalancer.adjust(
            tomorrow: .football, extraFocus: .push, extraIntensity: .moderate, soccerLoad: .hard
        ))
    }
}

@MainActor
final class ExtraSessionRebalanceIntegrationTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
    }

    private func composite(_ context: ModelContext, on day: Date, focus: WorkoutType) -> WorkoutPlan {
        let plan = WorkoutPlan(date: day, type: focus)
        plan.companionType = .football
        plan.companionCompleted = true
        plan.companionStartMin = 600
        plan.addedPartIntensityRaw = SessionIntensity.moderate.rawValue
        plan.companionSessionRPE = 8
        context.insert(plan)
        try? context.save()
        return plan
    }

    func testWeekAssemblyRebalancesTheDayAfterAPersistedCompositeDay() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        _ = composite(context, on: today, focus: .pull)

        let tomorrowPlan = WorkoutPlan(date: tomorrow, type: .pull)
        makeVM().applyExtraSessionRebalance(to: [tomorrowPlan], monday: today, modelContext: context)

        XCTAssertEqual(tomorrowPlan.type, .push)
        XCTAssertEqual(tomorrowPlan.recoveryAdjustment, 1.0, "No load scaling, only the muscle swap")
        XCTAssertTrue(tomorrowPlan.notes?.hasPrefix("Adjusted") == true)
    }

    func testPastCompositeWithGymNeverDoneDoesNotRebalance() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        _ = composite(context, on: yesterday, focus: .pull) // still .planned, in the past
        let todayPlan = WorkoutPlan(date: today, type: .pull)
        makeVM().applyExtraSessionRebalance(to: [todayPlan], monday: yesterday, modelContext: context)
        XCTAssertEqual(todayPlan.type, .pull)
    }

    func testNoCompositeNoChange() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrowPlan = WorkoutPlan(date: cal.date(byAdding: .day, value: 1, to: today)!, type: .pull)
        makeVM().applyExtraSessionRebalance(to: [tomorrowPlan], monday: today, modelContext: context)
        XCTAssertEqual(tomorrowPlan.type, .pull)
        XCTAssertEqual(tomorrowPlan.recoveryAdjustment, 1.0)
    }

    func testTrainerProgramDayIsNeverRebalanced() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        _ = composite(context, on: today, focus: .pull)
        let tomorrowPlan = WorkoutPlan(date: cal.date(byAdding: .day, value: 1, to: today)!, type: .pull)
        tomorrowPlan.programSessionKey = "week1-day2"
        makeVM().applyExtraSessionRebalance(to: [tomorrowPlan], monday: today, modelContext: context)
        XCTAssertEqual(tomorrowPlan.type, .pull)
    }

    func testNextMorningBrainInputsIncludeGymPartAndHarderRPE() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let plan = composite(context, on: yesterday, focus: .push)
        plan.status = .completed
        plan.sessionRPE = 6
        plan.durationMinutes = 50
        try context.save()

        let vm = makeVM()
        XCTAssertTrue(vm.fetchYesterdaySessions(modelContext: context).contains { $0.workoutType == "push" })
        XCTAssertEqual(vm.fetchYesterdaySessionRPE(modelContext: context), 8, "max(gym 6, soccer 8)")
    }
}
