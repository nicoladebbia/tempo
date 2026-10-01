//
// SupplementRound1Tests.swift
// Tempo
//
// Round 1 (Lane C): supplements are keyed by ID, duplicate AI names can't trap,
// reminders respect taken state, "running low" has ONE rule, restock is honest.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SupplementRound1Tests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext {
        container.mainContext
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - Duplicate AI names

    func testDuplicateDecisionNamesAreDedupedOnRead() {
        let plan = WeeklyMealPlan(startDate: Date(), endDate: Date().addingTimeInterval(86400 * 7))
        let json = #"{"1":[{"name":"Creatine","take":true,"timing":"with breakfast"},{"name":"Creatine","take":false}]}"#
        plan.supplementDecisionsJSON = Data(json.utf8)
        let decisions = plan.supplementDecisions[1] ?? []
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.take, true, "First decision wins")
        XCTAssertEqual(SupplementDecision.dedupedByName([.init(name: "A", take: true), .init(name: "A", take: false)]).count, 1)
    }

    func testDayContextBuildDoesNotTrapOnDuplicateDecisionNames() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let plan = WeeklyMealPlan(startDate: today, endDate: today.addingTimeInterval(86400 * 7))
        plan.isActive = true
        ctx.insert(plan)
        let json = #"{"1":[{"name":"Creatine","take":true},{"name":"Creatine","take":true}],"2":[{"name":"Creatine","take":true},{"name":"Creatine","take":true}],"3":[{"name":"Creatine","take":true},{"name":"Creatine","take":true}],"4":[{"name":"Creatine","take":true},{"name":"Creatine","take":true}],"5":[{"name":"Creatine","take":true},{"name":"Creatine","take":true}],"6":[{"name":"Creatine","take":true},{"name":"Creatine","take":true}],"7":[{"name":"Creatine","take":true},{"name":"Creatine","take":true}]}"#
        plan.supplementDecisionsJSON = Data(json.utf8)
        try ctx.save()
        let context = SupplementDayContext.build(date: today, modelContext: ctx)
        XCTAssertEqual(context.planDecisions.count <= 1, true)
    }

    // MARK: - Keyed by ID

    func testTwoSameNamedSupplementsKeepSeparateTicks() {
        let a = Supplement(name: "Whey", kind: .protein, servingsRemaining: 20)
        let b = Supplement(name: "Whey", kind: .protein, servingsRemaining: 20)
        ctx.insert(a); ctx.insert(b)
        SupplementIntakeStore.toggle(supplementID: a.id, name: "Whey", in: ctx)
        let taken = SupplementIntakeStore.takenIDs(on: Date(), in: ctx)
        XCTAssertTrue(taken.contains(a.id))
        XCTAssertFalse(taken.contains(b.id), "Same name must not light up the other row")
        XCTAssertEqual(a.servingsRemaining, 19)
        XCTAssertEqual(b.servingsRemaining, 20, "Decrement hits the tapped item only")
        SupplementIntakeStore.toggle(supplementID: a.id, name: "Whey", in: ctx)
        XCTAssertEqual(a.servingsRemaining, 20)
        XCTAssertTrue(SupplementIntakeStore.takenIDs(on: Date(), in: ctx).isEmpty)
    }

    func testRenameDoesNotOrphanTodaysTick() {
        let s = Supplement(name: "Creatine", kind: .creatine)
        ctx.insert(s)
        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        s.name = "Creatine Monohydrate"
        XCTAssertTrue(SupplementIntakeStore.takenIDs(on: Date(), in: ctx).contains(s.id))
        // Un-tick after rename (UI passes the new name) removes the right row.
        SupplementIntakeStore.toggle(supplementID: s.id, name: s.name, in: ctx)
        XCTAssertTrue((try? ctx.fetch(FetchDescriptor<SupplementIntakeLog>()))?.isEmpty == true)
    }

    func testLegacyNameOnlyLogStillCountsAndBackfills() throws {
        let s = Supplement(name: "Creatine", kind: .creatine)
        ctx.insert(s)
        ctx.insert(SupplementIntakeLog(supplementName: "Creatine", day: Date())) // pre-ID row
        try ctx.save()
        XCTAssertTrue(SupplementIntakeStore.takenIDs(on: Date(), in: ctx).contains(s.id))
        SupplementIntakeStore.backfillIDs(in: ctx)
        let rows = try ctx.fetch(FetchDescriptor<SupplementIntakeLog>())
        XCTAssertEqual(rows.first?.supplementID, s.id)
    }

    func testNotificationTakenActionFallsBackToNameWithoutIDs() {
        let s = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 10)
        ctx.insert(s)
        // Old already-scheduled notification: names only.
        SupplementReminderScheduler.markTaken(names: ["Creatine"], modelContext: ctx)
        XCTAssertEqual(s.servingsRemaining, 9)
        // Idempotent; and a new-style payload hits the same row.
        SupplementReminderScheduler.markTaken(names: ["Creatine"], ids: [s.id.uuidString], modelContext: ctx)
        XCTAssertEqual(s.servingsRemaining, 9)
        let rows = (try? ctx.fetch(FetchDescriptor<SupplementIntakeLog>())) ?? []
        XCTAssertEqual(rows.count, 1)
    }

    func testDaysLeftCountsLogsByIDAcrossARename() {
        let s = Supplement(name: "New Name", kind: .other, servingsRemaining: 14)
        let cal = Calendar.current
        let logs = (0 ..< 7).map { i in
            SupplementIntakeLog(
                supplementName: "Old Name", supplementID: s.id,
                day: cal.date(byAdding: .day, value: -i, to: Date())!
            )
        }
        let left = SupplementReorderService.daysLeft(for: s, recentLogs: logs)
        XCTAssertNotNil(left, "History survives the rename")
    }

    // MARK: - Reminders respect taken state

    func testReminderRebuildSkipsTakenDoseButKeepsTomorrow() async throws {
        let creatine = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30)
        ctx.insert(creatine)
        try ctx.save()
        let notifications = MockNotificationService()
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let now = startOfToday.addingTimeInterval(60)
        let todayKey = TempoDateFormatters.isoDate.string(from: startOfToday)

        await SupplementReminderScheduler.rebuild(notifications: notifications, modelContext: ctx, now: now)
        let before = notifications.scheduledNotifications.filter { $0.category.contains(todayKey) }
        XCTAssertFalse(before.isEmpty, "Untaken daily dose is reminded today")

        SupplementIntakeStore.toggle(supplementID: creatine.id, name: creatine.name, day: now, in: ctx)
        await SupplementReminderScheduler.rebuild(notifications: notifications, modelContext: ctx, now: now)
        let after = notifications.scheduledNotifications.filter { $0.category.hasPrefix("supplement_reminder_") }
        XCTAssertFalse(after.contains { $0.category.contains(todayKey) }, "Taken → no more nagging today")
        XCTAssertFalse(after.isEmpty, "Tomorrow's reminder is still scheduled")
    }

    // MARK: - One low-stock rule

    func testRunningLowAgreesWithReorderRule() {
        let low = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 6, takeDaily: true)
        XCTAssertTrue(low.isRunningLow, "6 servings daily = 6 days ≤ 7 → low, same as the banner")
        XCTAssertTrue(SupplementReorderService.needsReorder(for: low, recentLogs: []))
        let fine = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30, takeDaily: true)
        XCTAssertFalse(fine.isRunningLow)
        XCTAssertFalse(SupplementReorderService.needsReorder(for: fine, recentLogs: []))
        // The old rule (≤5 servings) called 7 servings fine while the banner
        // (≤7 days) called it low.
        let seven = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 7, takeDaily: true)
        XCTAssertEqual(seven.isRunningLow, SupplementReorderService.needsReorder(for: seven, recentLogs: []))
    }

    // MARK: - Restock honesty

    func testRestockWithUnknownContainerSizeChangesNothing() {
        let s = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 2)
        XCTAssertFalse(SupplementReorderService.restock(s))
        XCTAssertNil(s.lastRestockedAt, "No fake new cycle")
        XCTAssertEqual(s.servingsRemaining, 2)
        s.servingsPerContainer = 90
        XCTAssertTrue(SupplementReorderService.restock(s))
        XCTAssertEqual(s.servingsRemaining, 92)
        XCTAssertNotNil(s.lastRestockedAt)
    }
}
