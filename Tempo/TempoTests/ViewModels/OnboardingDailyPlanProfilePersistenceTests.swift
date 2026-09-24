//
// OnboardingDailyPlanProfilePersistenceTests.swift
// Tempo
//
// The eating window captured in onboarding must land in LOCAL SwiftData (the
// meal planner reads it from there), as exactly one row: re-entering the
// complete step or re-running onboarding updates it instead of inserting a
// duplicate that an unordered `.first` could pick.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class OnboardingDailyPlanProfilePersistenceTests: XCTestCase {
    // OnboardingViewModel persists step/data to UserDefaults; the test host
    // shares defaults with the dev app on this simulator, so put them back.
    private let keys = ["tempo.onboarding.step", "tempo.onboarding.data"]
    private var saved: [String: Any] = [:]
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        for key in keys {
            UserDefaults.standard.set(saved[key], forKey: key)
        }
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func allProfiles() throws -> [UserDailyPlanProfile] {
        try context.fetch(FetchDescriptor<UserDailyPlanProfile>())
    }

    private func makeVM(start: Int, end: Int, skip: Bool, postWorkout: Bool) -> OnboardingViewModel {
        let vm = OnboardingViewModel()
        vm.eatingWindowPreset = .sixteenEight
        vm.eatingWindowStartMinutes = start
        vm.eatingWindowEndMinutes = end
        vm.breakfastSkipped = skip
        vm.postWorkoutMandatory = postWorkout
        return vm
    }

    func testFirstPersistInsertsEatingWindowLocally() throws {
        let vm = makeVM(start: 12 * 60, end: 20 * 60, skip: true, postWorkout: false)
        try vm.persistDailyPlanProfile(in: context)

        let rows = try allProfiles()
        XCTAssertEqual(rows.count, 1)
        let profile = try XCTUnwrap(UserDailyPlanProfile.current(in: context))
        XCTAssertEqual(profile.eatingWindowStartMinutes, 12 * 60)
        XCTAssertEqual(profile.eatingWindowEndMinutes, 20 * 60)
        XCTAssertEqual(profile.eatingWindowPreset, .sixteenEight)
        XCTAssertTrue(profile.breakfastSkipped)
        XCTAssertFalse(profile.postWorkoutMandatory)
    }

    func testRepersistUpdatesInPlaceWithoutDuplicate() throws {
        let first = makeVM(start: 12 * 60, end: 20 * 60, skip: true, postWorkout: false)
        first.classBlocks = [
            OnboardingClassBlock(weekday: 2, startMinuteOfDay: 540, endMinuteOfDay: 600, courseCode: "CS101"),
        ]
        try first.persistDailyPlanProfile(in: context)

        let second = makeVM(start: 8 * 60, end: 18 * 60, skip: false, postWorkout: true)
        second.classBlocks = [
            OnboardingClassBlock(weekday: 3, startMinuteOfDay: 600, endMinuteOfDay: 660, courseCode: "MA201"),
        ]
        try second.persistDailyPlanProfile(in: context)

        let rows = try allProfiles()
        XCTAssertEqual(rows.count, 1)
        let profile = try XCTUnwrap(rows.first)
        XCTAssertEqual(profile.eatingWindowStartMinutes, 8 * 60)
        XCTAssertEqual(profile.eatingWindowEndMinutes, 18 * 60)
        XCTAssertFalse(profile.breakfastSkipped)
        XCTAssertTrue(profile.postWorkoutMandatory)
        XCTAssertEqual(profile.classBlocks.map(\.courseCode), ["MA201"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ClassBlock>()).count, 1, "old class blocks removed")
    }

    func testPersistCollapsesLegacyDuplicates() throws {
        // Older builds inserted a new row on every complete-step appearance.
        context.insert(UserDailyPlanProfile(eatingWindowStartMinutes: 7 * 60))
        context.insert(UserDailyPlanProfile(eatingWindowStartMinutes: 9 * 60))
        try context.save()

        let vm = makeVM(start: 11 * 60, end: 19 * 60, skip: true, postWorkout: true)
        try vm.persistDailyPlanProfile(in: context)

        let rows = try allProfiles()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.eatingWindowStartMinutes, 11 * 60)
    }

    func testCurrentPicksMostRecentlyUpdatedRow() throws {
        let old = UserDailyPlanProfile(eatingWindowStartMinutes: 7 * 60)
        old.updatedAt = Date(timeIntervalSinceNow: -3600)
        let fresh = UserDailyPlanProfile(eatingWindowStartMinutes: 13 * 60)
        context.insert(old)
        context.insert(fresh)
        try context.save()

        XCTAssertEqual(UserDailyPlanProfile.current(in: context)?.eatingWindowStartMinutes, 13 * 60)
    }

    func testCurrentIsNilBeforeOnboarding() {
        XCTAssertNil(UserDailyPlanProfile.current(in: context))
    }
}
