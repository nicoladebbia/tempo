//
// DeloadStatusTests.swift
// Tempo
//
// QA bug B — the Dashboard greeted a brand-new user with "Deload week" (its
// own week-of-year % 5 rule fired on week 40 for everyone) while Training said
// full volume. Both now resolve through `isDeloadWeek(on:modelContext:)`.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class DeloadStatusTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let engine = TrainingEngine()

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
    }

    private func seedAthlete(createdWeeksAgo weeks: Int, autoDeload: Bool = true) -> Date {
        let now = Date()
        let profile = UserProfile(appleID: "a", username: "u", displayName: "Athlete")
        profile.createdAt = Calendar.current.date(byAdding: .day, value: -7 * weeks, to: now)!
        let settings = UserSettings()
        settings.autoDeload = autoDeload
        settings.deloadFrequencyWeeks = 5
        settings.userProfile = profile
        context.insert(profile)
        context.insert(settings)
        try? context.save()
        return now
    }

    func testBrandNewAthleteIsNotDeloading() {
        let now = seedAthlete(createdWeeksAgo: 0)
        XCTAssertFalse(engine.isDeloadWeek(on: now, modelContext: context))
    }

    func testFifthWeekIsDeload() {
        let now = seedAthlete(createdWeeksAgo: 5)
        XCTAssertTrue(engine.isDeloadWeek(on: now, modelContext: context))
    }

    func testAutoDeloadOffNeverDeloads() {
        let now = seedAthlete(createdWeeksAgo: 5, autoDeload: false)
        XCTAssertFalse(engine.isDeloadWeek(on: now, modelContext: context))
    }
}
