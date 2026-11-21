//
// PreMatchWeighInPlanTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class PreMatchWeighInPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }

    func testFiresSixtyMinutesBeforeKickoff() {
        let r = PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 5)], now: now, lastWeighIn: nil)
        XCTAssertEqual(r.map(\.fireDate), [at(hours: 4)])
    }

    func testSkipsReminderAlreadyInThePast() {
        // Kickoff in 40 minutes: the reminder time (-20 min) is gone.
        XCTAssertTrue(PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 40.0 / 60)], now: now, lastWeighIn: nil).isEmpty)
        // Exactly now is not "after now".
        XCTAssertTrue(PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 1)], now: now, lastWeighIn: nil).isEmpty)
    }

    func testOnlyTheNextSevenDays() {
        let inside = at(hours: 7 * 24 + 1) // fire = exactly 7 days out
        let outside = at(hours: 7 * 24 + 1.1)
        let r = PreMatchWeighInPlan.reminders(kickoffs: [inside, outside], now: now, lastWeighIn: nil)
        XCTAssertEqual(r.map(\.kickoff), [inside])
    }

    func testDeduplicatesAndSorts() {
        let a = at(hours: 30), b = at(hours: 30.2), c = at(hours: 10)
        let r = PreMatchWeighInPlan.reminders(kickoffs: [a, b, c, c], now: now, lastWeighIn: nil)
        XCTAssertEqual(r.map(\.kickoff), [c, a])
    }

    func testSkipsWhenWeighedWithin90MinutesBeforeFiring() {
        let kickoff = at(hours: 3) // fires at +2 h
        XCTAssertTrue(PreMatchWeighInPlan.reminders(kickoffs: [kickoff], now: now, lastWeighIn: at(hours: 0.6)).isEmpty)
        XCTAssertEqual(PreMatchWeighInPlan.reminders(kickoffs: [kickoff], now: now, lastWeighIn: at(hours: 0.4)).count, 1)
    }

    func testOldWeighInDoesNotSuppress() {
        XCTAssertEqual(PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 3)], now: now, lastWeighIn: at(hours: -20)).count, 1)
    }

    func testIdentifiersAreStablePerKickoff() {
        let a = PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 5)], now: now, lastWeighIn: nil)
        let b = PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 5)], now: now, lastWeighIn: nil)
        XCTAssertEqual(a.first?.identifier, b.first?.identifier)
        XCTAssertTrue(a.first?.identifier.hasPrefix(PreMatchWeighInPlan.idPrefix) == true)
    }

    func testFootballBlockKeepsWallClockTimeAcrossDST() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // 2026-11-01: clocks go back. A 15:00 block must stay 15:00 local.
        let day = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let out = PreMatchWeighInPlan.kickoffs(matchKickoffs: [], footballBlocks: [(day: day, startMinuteOfDay: 15 * 60)], calendar: cal)
        let parts = cal.dateComponents([.hour, .minute], from: try XCTUnwrap(out.first))
        XCTAssertEqual(parts.hour, 15)
        XCTAssertEqual(parts.minute, 0)
        // 2027-03-14: clocks go forward.
        let spring = try XCTUnwrap(cal.date(from: DateComponents(year: 2027, month: 3, day: 14)))
        let out2 = PreMatchWeighInPlan.kickoffs(matchKickoffs: [], footballBlocks: [(day: spring, startMinuteOfDay: 15 * 60)], calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: try XCTUnwrap(out2.first)), 15)
    }

    func testKickoffsMergeMatchesAndFootballBlocks() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let day = cal.startOfDay(for: now)
        let out = PreMatchWeighInPlan.kickoffs(
            matchKickoffs: [at(hours: 2)], footballBlocks: [(day: day, startMinuteOfDay: 19 * 60)], calendar: cal
        )
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[1], day.addingTimeInterval(19 * 3600))
    }
}

// MARK: - Scheduler (real notification center, in-memory data)

import SwiftData
import UserNotifications

@MainActor
final class PreMatchWeighInSchedulerTests: XCTestCase {
    private func pendingIDs() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(PreMatchWeighInPlan.idPrefix) }
    }

    private func store(on: Bool = true) -> RecoveryCoachStore {
        let s = RecoveryCoachStore(defaults: UserDefaults(suiteName: "prematch-\(UUID().uuidString)")!, key: "k")
        s.update { $0.preMatchReminderOn = on }
        return s
    }

    /// These schedule REAL notifications, which iOS refuses for an app that isn't allowed to notify
    /// (a fresh simulator). Skip there with the reason instead of failing on the environment.
    override func setUp() async throws {
        try await super.setUp()
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        try XCTSkipUnless(
            status == .authorized || status == .provisional || status == .ephemeral,
            "Notifications not allowed on this simulator (status \(status.rawValue)); run `scripts/sim.sh qa --local` once and tap Allow"
        )
    }

    override func tearDown() async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: await pendingIDs())
        try await super.tearDown()
    }

    func testSchedulesOnceForAMatchAndNeverDuplicates() async throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let now = Date()
        container.mainContext.insert(Match(kickoff: now.addingTimeInterval(3 * 3600)))
        try container.mainContext.save()
        let s = store()
        await PreMatchWeighInScheduler.rebuild(modelContext: container.mainContext, healthKit: nil, store: s, now: now)
        await PreMatchWeighInScheduler.rebuild(modelContext: container.mainContext, healthKit: nil, store: s, now: now)
        let ids = await pendingIDs()
        XCTAssertEqual(ids.count, 1, "rebuilding twice must not duplicate")
        let request = await UNUserNotificationCenter.current().pendingNotificationRequests().first { $0.identifier == ids.first }
        XCTAssertEqual(request?.content.categoryIdentifier, "PRE_MATCH_WEIGHIN")
    }

    func testToggleOffRemovesThem() async throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let now = Date()
        container.mainContext.insert(Match(kickoff: now.addingTimeInterval(3 * 3600)))
        try container.mainContext.save()
        let s = store()
        await PreMatchWeighInScheduler.rebuild(modelContext: container.mainContext, healthKit: nil, store: s, now: now)
        let afterFirst = await pendingIDs()
        XCTAssertEqual(afterFirst.count, 1)
        s.update { $0.preMatchReminderOn = false }
        await PreMatchWeighInScheduler.rebuild(modelContext: container.mainContext, healthKit: nil, store: s, now: now)
        let afterOff = await pendingIDs()
        XCTAssertTrue(afterOff.isEmpty)
    }

    func testRecentManualWeighInSuppressesTheReminder() async throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let now = Date()
        container.mainContext.insert(Match(kickoff: now.addingTimeInterval(3 * 3600)))
        try container.mainContext.save()
        let s = store()
        s.addManualWeighIn(CoachWeighIn(time: now.addingTimeInterval(-10 * 60), kg: 78, source: "manual"), now: now)
        await PreMatchWeighInScheduler.rebuild(modelContext: container.mainContext, healthKit: nil, store: s, now: now)
        // Weighed 10 min ago; the reminder fires in 2 h, 2 h 10 min after the weigh-in: still wanted.
        let first = await pendingIDs()
        XCTAssertEqual(first.count, 1)
        // A kickoff in 1 h 30 min fires in 30 min, 40 min after the weigh-in: skipped.
        container.mainContext.insert(Match(kickoff: now.addingTimeInterval(90 * 60)))
        try container.mainContext.save()
        await PreMatchWeighInScheduler.rebuild(modelContext: container.mainContext, healthKit: nil, store: s, now: now)
        let found = await pendingIDs()
        XCTAssertEqual(found.count, 1)
    }

    func testFootballBlockInTheDayPlanIsUsed() async throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let ctx = container.mainContext
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        let tomorrow = cal.startOfDay(for: now.addingTimeInterval(24 * 3600))
        let plan = DayPlan(date: tomorrow, blocks: [])
        let block = TimeBlock(kind: .football, startMinuteOfDay: 19 * 60, endMinuteOfDay: 20 * 60 + 30, title: "Football")
        plan.blocks.append(block)
        ctx.insert(plan)
        try ctx.save()
        await PreMatchWeighInScheduler.rebuild(modelContext: ctx, healthKit: nil, store: store(), now: now)
        let found = await pendingIDs()
        XCTAssertEqual(found.count, 1)
    }
}
