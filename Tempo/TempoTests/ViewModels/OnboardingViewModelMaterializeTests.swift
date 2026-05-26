//
// OnboardingViewModelMaterializeTests.swift
// Tempo
//
// Phase 10b2 (overnight 2026-05-26) — covers the bridge from onboarding-only
// fields to the SwiftData models the rest of the app reads from. Before this
// bridge existed, primaryGoal / preferredSplit / experienceLevel /
// studyTarget / mealTarget were collected, persisted to UserDefaults, and
// then `complete()` deleted the blob — every new user shipped with default
// PPL split + no DietaryProfile.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class OnboardingViewModelMaterializeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var vm: OnboardingViewModel!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: UserSettings.self, DietaryProfile.self, NonNegotiable.self,
            UserProfile.self,
            configurations: config
        )
        context = ModelContext(container)
        // Clear any UserDefaults state so loadPersistedData() in init() is a no-op.
        UserDefaults.standard.removeObject(forKey: "tempo.onboarding.data")
        UserDefaults.standard.removeObject(forKey: "tempo.onboarding.step")
        vm = OnboardingViewModel()
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        vm = nil
        try await super.tearDown()
    }

    // MARK: - UserSettings bridge

    func testMaterialize_mapsPreferredSplitOntoUserSettings() throws {
        vm.preferredSplit = "Full Body"

        vm.materializeUserModelsIfNeeded(modelContext: context)

        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(settings.trainingSplit, .fullBody)
    }

    func testMaterialize_unknownSplitKeepsPPLDefault() throws {
        vm.preferredSplit = "I Don't Know"

        vm.materializeUserModelsIfNeeded(modelContext: context)

        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(settings.trainingSplit, .pushPullLegs)
    }

    func testMaterialize_updatesExistingUserSettingsRowInPlace() throws {
        // Pre-existing row (ContentView.ensureUserProfile() may have inserted one).
        let pre = UserSettings()
        context.insert(pre)
        try context.save()

        vm.preferredSplit = "Bro Split"
        vm.materializeUserModelsIfNeeded(modelContext: context)

        let rows = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(rows.count, 1, "must not duplicate UserSettings rows")
        XCTAssertEqual(rows[0].trainingSplit, .bro)
    }

    // MARK: - DietaryProfile bridge

    func testMaterialize_createsDietaryProfileWithMappedGoal() throws {
        vm.primaryGoal = "Build Muscle"
        vm.experienceLevel = "Advanced"
        vm.daysPerWeek = 5

        vm.materializeUserModelsIfNeeded(modelContext: context)

        let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<DietaryProfile>()).first)
        XCTAssertEqual(profile.primaryGoal, .leanGain)
        XCTAssertEqual(profile.skillLevel, .advanced)
        XCTAssertEqual(profile.trainingFrequency, 5)
    }

    func testMaterialize_loseFatMapsToCut() throws {
        vm.primaryGoal = "Lose Fat"
        vm.materializeUserModelsIfNeeded(modelContext: context)
        let p = try XCTUnwrap(try context.fetch(FetchDescriptor<DietaryProfile>()).first)
        XCTAssertEqual(p.primaryGoal, .cut)
    }

    func testMaterialize_stayHealthyMapsToMaintain() throws {
        vm.primaryGoal = "Stay Healthy"
        vm.materializeUserModelsIfNeeded(modelContext: context)
        let p = try XCTUnwrap(try context.fetch(FetchDescriptor<DietaryProfile>()).first)
        XCTAssertEqual(p.primaryGoal, .maintain)
    }

    func testMaterialize_doesNotOverwriteExistingDietaryProfile() throws {
        // User previously opened DietaryProfileSetupView and set up a profile.
        let existing = DietaryProfile(primaryGoal: .cut, trainingFrequency: 3, skillLevel: .beginner)
        context.insert(existing)
        try context.save()

        vm.primaryGoal = "Build Muscle"
        vm.experienceLevel = "Advanced"
        vm.materializeUserModelsIfNeeded(modelContext: context)

        let rows = try context.fetch(FetchDescriptor<DietaryProfile>())
        XCTAssertEqual(rows.count, 1, "must not insert a second DietaryProfile")
        XCTAssertEqual(rows[0].primaryGoal, .cut, "existing profile must not be overwritten")
        XCTAssertEqual(rows[0].skillLevel, .beginner)
    }

    // MARK: - NonNegotiable seeding

    func testMaterialize_seedsNonNegotiablesFromOnboardingTargets() throws {
        vm.studyTarget = 90
        vm.mealTarget = 5
        vm.sleepTargetHours = 7.5

        vm.materializeUserModelsIfNeeded(modelContext: context)

        let nns = try context.fetch(FetchDescriptor<NonNegotiable>())
        XCTAssertEqual(nns.count, 4)
        let byType = Dictionary(uniqueKeysWithValues: nns.map { ($0.type, $0) })
        XCTAssertEqual(byType[.study]?.targetValue, 90)
        XCTAssertEqual(byType[.meals]?.targetValue, 5)
        XCTAssertEqual(byType[.sleep]?.targetValue, 7.5)
        XCTAssertEqual(byType[.train]?.targetValue, 1) // training NN is always 1/day
    }

    func testMaterialize_doesNotDuplicateExistingNonNegotiables() throws {
        // User configured Study manually before reaching complete-step.
        let pre = NonNegotiable(name: "Study", type: .study, icon: "book.fill", targetValue: 60, trackingMethod: .timer, order: 0)
        context.insert(pre)
        try context.save()

        vm.studyTarget = 180

        vm.materializeUserModelsIfNeeded(modelContext: context)

        let studyRows = try context.fetch(FetchDescriptor<NonNegotiable>()).filter { $0.type == .study }
        XCTAssertEqual(studyRows.count, 1)
        XCTAssertEqual(studyRows[0].targetValue, 60, "must respect user-set value, not overwrite from onboarding")
    }

    // MARK: - Idempotency

    func testMaterialize_isIdempotent() throws {
        vm.primaryGoal = "Build Muscle"
        vm.preferredSplit = "PPL"
        vm.studyTarget = 120
        vm.mealTarget = 4

        vm.materializeUserModelsIfNeeded(modelContext: context)
        vm.materializeUserModelsIfNeeded(modelContext: context)
        vm.materializeUserModelsIfNeeded(modelContext: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DietaryProfile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NonNegotiable>()).count, 4)
    }
}
