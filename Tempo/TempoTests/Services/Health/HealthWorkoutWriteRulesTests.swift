//
// HealthWorkoutWriteRulesTests.swift
// Tempo
//
// Apple Health workout writes: no duplicates over an existing (Watch/other)
// workout, gym calorie estimate, guided runs saved as running with their
// real span.
//

@testable import Tempo
import HealthKit
import XCTest

final class HealthWorkoutWriteRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ minutes: Double) -> Date {
        t0.addingTimeInterval(minutes * 60)
    }

    // MARK: - Dedupe

    func testWatchWorkoutCoveringTheGymSessionIsADuplicate() {
        XCTAssertTrue(HealthWorkoutDedupe.isDuplicate(
            start: at(0), end: at(60), existing: [(at(-2), at(58))]
        ))
    }

    func testOurOwnEarlierWriteOfTheSameSessionIsADuplicate() {
        XCTAssertTrue(HealthWorkoutDedupe.isDuplicate(
            start: at(0), end: at(60), existing: [(at(0), at(60))]
        ))
    }

    func testShortWalkBrushingTheEdgeIsNotADuplicate() {
        XCTAssertFalse(HealthWorkoutDedupe.isDuplicate(
            start: at(0), end: at(60), existing: [(at(55), at(70))]
        ), "5 min overlap of a 60 min session is below the 10 min bar")
    }

    func testShortSessionUsesHalfItsLength() {
        // 12 min run: threshold is 6 min.
        XCTAssertTrue(HealthWorkoutDedupe.isDuplicate(
            start: at(0), end: at(12), existing: [(at(5), at(30))]
        ))
        XCTAssertFalse(HealthWorkoutDedupe.isDuplicate(
            start: at(0), end: at(12), existing: [(at(8), at(30))]
        ))
    }

    func testNoExistingWorkoutsIsNotADuplicate() {
        XCTAssertFalse(HealthWorkoutDedupe.isDuplicate(start: at(0), end: at(60), existing: []))
    }

    // MARK: - Gym calories

    func testStrengthKcalIsMET35TimesBodyweightTimesHours() {
        XCTAssertEqual(HealthWorkoutDedupe.strengthKcal(bodyweightKg: 80, durationSeconds: 3600), 280)
        XCTAssertEqual(HealthWorkoutDedupe.strengthKcal(bodyweightKg: 70, durationSeconds: 2700), 184)
    }

    func testStrengthKcalIsZeroWithoutBodyweight() {
        XCTAssertEqual(HealthWorkoutDedupe.strengthKcal(bodyweightKg: nil, durationSeconds: 3600), 0)
        XCTAssertEqual(HealthWorkoutDedupe.strengthKcal(bodyweightKg: 0, durationSeconds: 3600), 0)
    }

    // MARK: - Activity type

    func testGuidedRunTypeStringMapsToRunning() {
        XCTAssertEqual(HealthKitService.mapStringToHKActivityType("running"), .running)
        XCTAssertEqual(HealthKitService.mapStringToHKActivityType("run"), .running)
        XCTAssertEqual(HealthKitService.mapStringToHKActivityType("strength"), .traditionalStrengthTraining)
    }

    func testCalorieAndDistanceAreWritable() {
        XCTAssertTrue(HealthKitConstants.writeTypes.contains(HKQuantityType(.activeEnergyBurned)))
        XCTAssertTrue(HealthKitConstants.writeTypes.contains(HKQuantityType(.distanceWalkingRunning)))
    }

    // MARK: - Guided run span

    func testGuidedRunSpanUsesRealStartAndEndNotSaveTime() {
        let span = GuidedRunHealthSpan.resolve(
            startedAt: at(0), endedAt: at(30), trackedSeconds: 900, now: at(45)
        )
        XCTAssertEqual(span.start, at(0))
        XCTAssertEqual(span.end, at(30), "the summary sat open 15 min — that's not run time")
    }

    func testGuidedRunSpanFallsBackToTrackedTimeEndingAtFinish() {
        let span = GuidedRunHealthSpan.resolve(
            startedAt: nil, endedAt: at(30), trackedSeconds: 600, now: at(45)
        )
        XCTAssertEqual(span.start, at(20))
        XCTAssertEqual(span.end, at(30))
    }
}
