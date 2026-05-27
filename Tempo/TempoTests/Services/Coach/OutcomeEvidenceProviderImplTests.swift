//
// OutcomeEvidenceProviderImplTests.swift
// Tempo
//
// Coach v2.1 Phase 8a — verifies the real grader's per-tool evidence
// rules against synthetic SwiftData state. The HK sleep reader is a
// deterministic stub.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class OutcomeEvidenceProviderImplTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WeeklyMealPlan.self,
            PlannedMeal.self,
            WorkoutPlan.self,
            PlannedExercise.self,
            PlannedSet.self,
            LearnedPreference.self,
            LearnedOutcome.self,
            PendingOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - moveMeal

    func testMoveMeal_eatenNearNewTime_followedThrough() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = makeMeal(scheduled: "20:30", in: context)
        // Set actualEatenAt = 20:35 on the meal's day.
        let dayStart = Calendar.current.startOfDay(for: meal.dayDate)
        meal.actualEatenAt = Calendar.current.date(
            bySettingHour: 20, minute: 35, second: 0, of: dayStart
        )
        meal.status = .eaten
        try context.save()

        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let payload = Data(
            #"{"mealID":"\#(meal.id.uuidString)","newTimeHHmm":"20:30"}"#.utf8
        )
        let evidence = try await provider.fetchEvidence(
            for: "moveMeal",
            payload: payload,
            decisionDate: meal.dayDate,
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .followedThrough)
    }

    func testMoveMeal_skippedMeal_abandoned() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = makeMeal(scheduled: "20:30", in: context)
        meal.status = .skipped
        try context.save()

        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let payload = Data(
            #"{"mealID":"\#(meal.id.uuidString)","newTimeHHmm":"20:30"}"#.utf8
        )
        let evidence = try await provider.fetchEvidence(
            for: "moveMeal",
            payload: payload,
            decisionDate: meal.dayDate,
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .abandoned)
    }

    func testMoveMeal_stillPlannedAtEvaluation_abandoned() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = makeMeal(scheduled: "20:30", in: context)
        try context.save()
        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let payload = Data(
            #"{"mealID":"\#(meal.id.uuidString)","newTimeHHmm":"20:30"}"#.utf8
        )
        let evidence = try await provider.fetchEvidence(
            for: "moveMeal",
            payload: payload,
            decisionDate: meal.dayDate,
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .abandoned)
    }

    func testMoveMeal_deletedMeal_abandoned() async throws {
        let container = try makeContainer()
        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let bogusID = UUID()
        let payload = Data(
            #"{"mealID":"\#(bogusID.uuidString)","newTimeHHmm":"20:30"}"#.utf8
        )
        let evidence = try await provider.fetchEvidence(
            for: "moveMeal",
            payload: payload,
            decisionDate: Date(),
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .abandoned)
    }

    // MARK: - skipMeal

    func testSkipMeal_stayedSkipped_followedThrough() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = makeMeal(scheduled: "12:30", in: context)
        meal.status = .skipped
        try context.save()
        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let payload = Data(#"{"mealID":"\#(meal.id.uuidString)"}"#.utf8)
        let evidence = try await provider.fetchEvidence(
            for: "skipMeal",
            payload: payload,
            decisionDate: meal.dayDate,
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .followedThrough)
    }

    func testSkipMeal_userAteAnyway_abandoned() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = makeMeal(scheduled: "12:30", in: context)
        meal.status = .eaten
        try context.save()
        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let payload = Data(#"{"mealID":"\#(meal.id.uuidString)"}"#.utf8)
        let evidence = try await provider.fetchEvidence(
            for: "skipMeal",
            payload: payload,
            decisionDate: meal.dayDate,
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .abandoned)
    }

    // MARK: - swapDayType

    func testSwapDayType_workoutCompleted_followedThrough() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let day = Calendar.current.startOfDay(for: Date())
        let workout = WorkoutPlan(date: day, type: .push, status: .completed)
        context.insert(workout)
        try context.save()

        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let isoDate = ISO8601DateFormatter.dateOnly.string(from: day)
        let payload = Data(
            #"{"date":"\#(isoDate)","newType":"strength","scaleMacros":false}"#.utf8
        )
        let evidence = try await provider.fetchEvidence(
            for: "swapDayType",
            payload: payload,
            decisionDate: day,
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .followedThrough)
    }

    func testSwapDayType_noWorkoutForDay_abandoned() async throws {
        let container = try makeContainer()
        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let isoDate = ISO8601DateFormatter.dateOnly.string(from: Date())
        let payload = Data(
            #"{"date":"\#(isoDate)","newType":"strength","scaleMacros":false}"#.utf8
        )
        let evidence = try await provider.fetchEvidence(
            for: "swapDayType",
            payload: payload,
            decisionDate: Date(),
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .abandoned)
    }

    // MARK: - shiftBedtime

    func testShiftBedtime_actualNearTarget_followedThrough() async throws {
        let container = try makeContainer()
        let target = ISO8601DateFormatter.dateOnly.string(from: Date())
        let reader = ScriptedSleepReader()
        // Bedtime requested 22:30; actual 22:25 → within 30min.
        let bedDate = Calendar.current.date(
            bySettingHour: 22, minute: 25, second: 0, of: Date()
        )!
        reader.next = HKSleepReading(
            inBedStart: bedDate,
            inBedEnd: bedDate.addingTimeInterval(8 * 3600),
            totalHours: 7.5
        )
        let provider = OutcomeEvidenceProviderImpl(
            modelContainer: container,
            sleepReader: reader
        )
        let payload = Data(#"{"date":"\#(target)","newBedtimeHHmm":"22:30"}"#.utf8)
        let evidence = try await provider.fetchEvidence(
            for: "shiftBedtime",
            payload: payload,
            decisionDate: Date(),
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .followedThrough)
    }

    func testShiftBedtime_noSleepData_unclear() async throws {
        let container = try makeContainer()
        let provider = OutcomeEvidenceProviderImpl(
            modelContainer: container,
            sleepReader: NoopHKSleepReader()
        )
        let target = ISO8601DateFormatter.dateOnly.string(from: Date())
        let payload = Data(#"{"date":"\#(target)","newBedtimeHHmm":"22:30"}"#.utf8)
        let evidence = try await provider.fetchEvidence(
            for: "shiftBedtime",
            payload: payload,
            decisionDate: Date(),
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .unclear)
    }

    func testShiftBedtime_goodSleepDespiteWrongTime_goodSleep() async throws {
        let container = try makeContainer()
        let target = ISO8601DateFormatter.dateOnly.string(from: Date())
        let reader = ScriptedSleepReader()
        // Actual 00:30, target 22:30 → 120min off, but 8h total.
        let bedDate = Calendar.current.date(
            bySettingHour: 0, minute: 30, second: 0, of: Date()
        )!
        reader.next = HKSleepReading(
            inBedStart: bedDate,
            inBedEnd: bedDate.addingTimeInterval(8 * 3600),
            totalHours: 8.0
        )
        let provider = OutcomeEvidenceProviderImpl(
            modelContainer: container,
            sleepReader: reader
        )
        let payload = Data(#"{"date":"\#(target)","newBedtimeHHmm":"22:30"}"#.utf8)
        let evidence = try await provider.fetchEvidence(
            for: "shiftBedtime",
            payload: payload,
            decisionDate: Date(),
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .goodSleep)
    }

    // MARK: - Unknown tool

    func testUnknownTool_unclear() async throws {
        let container = try makeContainer()
        let provider = OutcomeEvidenceProviderImpl(modelContainer: container)
        let evidence = try await provider.fetchEvidence(
            for: "doesNotExist",
            payload: Data(),
            decisionDate: Date(),
            evaluationDate: Date()
        )
        XCTAssertEqual(evidence.outcome, .unclear)
    }

    // MARK: - Fixture helpers

    private func makeMeal(
        scheduled: String,
        in context: ModelContext
    ) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: Calendar.current.startOfDay(for: Date()),
            mealNumber: 3,
            mealName: "Dinner",
            scheduledTime: scheduled,
            totalCalories: 600,
            totalProtein: 35,
            totalCarbs: 60,
            totalFat: 18
        )
        context.insert(meal)
        return meal
    }
}

// MARK: - ScriptedSleepReader

final class ScriptedSleepReader: HKSleepReader, @unchecked Sendable {
    var next: HKSleepReading?
    func sleepEnding(on _: Date) async throws -> HKSleepReading? { next }
}

// MARK: - ISO8601DateFormatter dateOnly

extension ISO8601DateFormatter {
    /// `ISO8601DateFormatter` is not Sendable but Apple documents it as
    /// thread-safe in practice. nonisolated(unsafe) opts out of the
    /// Swift 6 concurrency check; tests run on a single thread anyway.
    nonisolated(unsafe) static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}
