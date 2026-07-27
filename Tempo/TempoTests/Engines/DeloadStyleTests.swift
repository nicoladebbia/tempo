//
// DeloadStyleTests.swift
// Tempo
//
// §19.3 — the three deload styles. Pins: volume-cut halves working sets and
// keeps the weight; intensity-cut keeps the sets and drops the weight 40%;
// full-rest turns every gym day of a deload week into mobility (football and
// rest days untouched); nil stored style decodes to intensity-cut (the
// original behavior); and the Auto Deload toggle actually gates the deload
// (it used to be saved but never read).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class DeloadStyleTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            ExerciseHistory.self,
            PlannedExercise.self,
            PlannedSet.self,
            PredictionLog.self,
            AdaptiveProfile.self,
            UserSettings.self,
            UserProfile.self,
            BodyComposition.self,
            SetFeedback.self,
            Match.self,
            ActivitySession.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVM(engine: TrainingEngineProtocol = MockTrainingEngine()) -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: engine,
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    /// Settings row with the given style raw, plus a chest compound in the
    /// library and an empty .push plan ready to populate.
    private func seed(
        styleRaw: String?, context: ModelContext
    ) -> WorkoutPlan {
        let settings = UserSettings()
        settings.deloadStyleRaw = styleRaw
        context.insert(settings)

        let bench = Exercise(name: "Barbell Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush,
                             isCompound: true)
        context.insert(bench)

        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        try? context.save()
        return plan
    }

    // MARK: - Population styles (mock engine prescribes 80 kg)

    func testVolumeCutHalvesSetsKeepsWeight() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(styleRaw: DeloadStyle.volumeCut.rawValue, context: context)
        vm.isDeloadWeek = true

        vm.populateExercises(for: plan, modelContext: context)

        let working = plan.orderedExercises.first?.orderedSets.filter { !$0.isWarmup } ?? []
        XCTAssertEqual(working.count, 2, "Primary compound 4 working sets → halved to 2")
        XCTAssertEqual(working.first?.targetWeight, 80, "Volume-cut keeps the full weight")
    }

    func testIntensityCutKeepsSetsDropsWeight() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(styleRaw: DeloadStyle.intensityCut.rawValue, context: context)
        vm.isDeloadWeek = true

        vm.populateExercises(for: plan, modelContext: context)

        let working = plan.orderedExercises.first?.orderedSets.filter { !$0.isWarmup } ?? []
        XCTAssertEqual(working.count, 4, "Intensity-cut keeps all working sets")
        XCTAssertEqual(working.first?.targetWeight ?? 0, 47.5, accuracy: 0.01,
                       "80 × 0.6 = 48 → rounded to 47.5")
    }

    func testNilStyleDefaultsToIntensityCut() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(styleRaw: nil, context: context)
        vm.isDeloadWeek = true

        vm.populateExercises(for: plan, modelContext: context)

        let working = plan.orderedExercises.first?.orderedSets.filter { !$0.isWarmup } ?? []
        XCTAssertEqual(working.count, 4)
        XCTAssertEqual(working.first?.targetWeight ?? 0, 47.5, accuracy: 0.01,
                       "Pre-existing stores (nil style) keep the original 0.6× behavior")
    }

    func testNoDeloadWeekLeavesPrescriptionAlone() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(styleRaw: DeloadStyle.volumeCut.rawValue, context: context)
        vm.isDeloadWeek = false

        vm.populateExercises(for: plan, modelContext: context)

        let working = plan.orderedExercises.first?.orderedSets.filter { !$0.isWarmup } ?? []
        XCTAssertEqual(working.count, 4, "Style only applies during a deload week")
        XCTAssertEqual(working.first?.targetWeight, 80)
    }

    // MARK: - Settings surface

    func testAutoDeloadOffAndStyleReadThroughLoad() throws {
        let context = try makeContext()
        let vm = makeVM()
        let settings = UserSettings()
        settings.autoDeload = false
        settings.deloadStyleRaw = DeloadStyle.fullRest.rawValue
        context.insert(settings)
        try context.save()

        let loaded = vm.loadDeloadSettings(modelContext: context)
        XCTAssertFalse(loaded.enabled, "The Auto Deload toggle must gate the deload")
        XCTAssertEqual(loaded.style, .fullRest)
    }

    // MARK: - Full rest (real engine — the transform runs on the week)

    func testFullRestTurnsGymDaysIntoMobilityOnDeloadWeek() throws {
        let context = try makeContext()
        let vm = makeVM(engine: TrainingEngine())

        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2
        let thisMonday = cal.date(from: comps) ?? Date()
        // Training started exactly 8 weeks before → week 8 of a 4-week cycle
        // is a deload week.
        let start = cal.date(byAdding: .weekOfYear, value: -8, to: thisMonday) ?? thisMonday

        let profile = UserProfile(appleID: "test", username: "test", displayName: "Test")
        profile.createdAt = start
        context.insert(profile)
        let settings = UserSettings()
        settings.deloadStyleRaw = DeloadStyle.fullRest.rawValue
        settings.deloadFrequencyWeeks = 4
        settings.userProfile = profile
        context.insert(settings)
        try context.save()

        let plans = vm.previewWeekPlans(startingMonday: thisMonday, modelContext: context)

        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { !$0.type.isGymWorkout },
                      "A full-rest deload week has zero gym days")
        XCTAssertTrue(plans.contains { $0.type == .mobility },
                      "Gym days became mobility, not blank")
    }

    func testFullRestLeavesOrdinaryWeeksAlone() throws {
        let context = try makeContext()
        let vm = makeVM(engine: TrainingEngine())

        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2
        let thisMonday = cal.date(from: comps) ?? Date()
        // 7 weeks in on a 4-week cycle → NOT a deload week.
        let start = cal.date(byAdding: .weekOfYear, value: -7, to: thisMonday) ?? thisMonday

        let profile = UserProfile(appleID: "test", username: "test", displayName: "Test")
        profile.createdAt = start
        context.insert(profile)
        let settings = UserSettings()
        settings.deloadStyleRaw = DeloadStyle.fullRest.rawValue
        settings.deloadFrequencyWeeks = 4
        settings.userProfile = profile
        context.insert(settings)
        try context.save()

        let plans = vm.previewWeekPlans(startingMonday: thisMonday, modelContext: context)

        XCTAssertTrue(plans.contains { $0.type.isGymWorkout },
                      "Ordinary weeks keep their gym days under full-rest style")
    }
}
