//
// MealReminderTests.swift
// Tempo
//
// Round 2 lane P: a pre-meal reminder 15 minutes before every planned meal,
// gated by the Meal Reminders switch, cancelled on eat / skip, and a
// notification tap that opens THAT meal.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class MealReminderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    /// 08:00 today — every test meal sits later than that.
    private var now: Date {
        calendar.date(byAdding: .hour, value: 8, to: today) ?? today
    }

    private func plan(active: Bool = true) -> WeeklyMealPlan {
        let p = WeeklyMealPlan(startDate: today, endDate: calendar.date(byAdding: .day, value: 6, to: today) ?? today)
        p.isActive = active
        context.insert(p)
        return p
    }

    @discardableResult
    private func meal(
        _ name: String, day: Int = 0, time: String = "12:00",
        status: MealStatus = .planned, in plan: WeeklyMealPlan
    ) -> PlannedMeal {
        let m = PlannedMeal(
            dayDate: calendar.date(byAdding: .day, value: day, to: today) ?? today,
            mealNumber: 1, mealName: name, scheduledTime: time,
            foods: [], totalCalories: 500, totalProtein: 30, totalCarbs: 50, totalFat: 15,
            status: status, mealPlan: plan
        )
        context.insert(m)
        return m
    }

    private func settings(mealReminders: Bool) {
        let s = UserSettings()
        s.mealRemindersEnabled = mealReminders
        context.insert(s)
    }

    // MARK: - Scheduling

    func testRemindsFifteenMinutesBeforeEveryPlannedOrModifiedMeal() throws {
        let p = plan()
        let lunch = meal("Lunch", time: "12:00", in: p)
        let dinner = meal("Dinner", time: "19:30", status: .modified, in: p)
        meal("Breakfast", time: "07:00", status: .eaten, in: p)
        meal("Snack", time: "16:00", status: .skipped, in: p)
        let tomorrow = meal("Lunch", day: 1, time: "13:00", in: p)
        let mock = MockNotificationService()

        settings(mealReminders: true)
        MealReminderPlanner.reschedule(modelContext: context, notifications: mock, now: now)

        let reminders = mock.scheduledNotifications.filter { $0.category == "meal_reminder" }
        XCTAssertEqual(reminders.count, 3, "eaten / skipped meals get none")
        let byMeal = Dictionary(uniqueKeysWithValues: reminders.compactMap { r in r.mealID.map { ($0, r.triggerDate) } })
        XCTAssertEqual(byMeal[lunch.id], at(day: 0, "11:45"))
        XCTAssertEqual(byMeal[dinner.id], at(day: 0, "19:15"))
        XCTAssertEqual(byMeal[tomorrow.id], at(day: 1, "12:45"))
        XCTAssertEqual(reminders.map(\.triggerDate), reminders.map(\.triggerDate).sorted(), "soonest first")
    }

    func testPastReminderAndInactivePlanAreSkipped() {
        let old = plan(active: false)
        meal("Lunch", time: "12:00", in: old)
        let p = plan()
        meal("Early", time: "08:10", in: p) // 07:55 fire time is before "now"
        let mock = MockNotificationService()
        settings(mealReminders: true)
        MealReminderPlanner.reschedule(modelContext: context, notifications: mock, now: now)
        XCTAssertTrue(mock.scheduledNotifications.filter { $0.category == "meal_reminder" }.isEmpty)
    }

    func testSwitchOffSchedulesNothingAndClearsPending() {
        let p = plan()
        meal("Lunch", in: p)
        let mock = MockNotificationService()
        mock.scheduleMealReminder(mealID: UUID(), mealName: "Old", fireDate: now.addingTimeInterval(3600))
        settings(mealReminders: false)
        MealReminderPlanner.reschedule(modelContext: context, notifications: mock, now: now)
        XCTAssertTrue(mock.scheduledNotifications.isEmpty)

        // Turning it on schedules.
        let s = try? context.fetch(FetchDescriptor<UserSettings>()).first
        s?.mealRemindersEnabled = true
        MealReminderPlanner.reschedule(modelContext: context, notifications: mock, now: now)
        XCTAssertEqual(mock.scheduledNotifications.count, 1)
    }

    func testRescheduleReplacesStaleReminders() {
        let p = plan()
        let lunch = meal("Lunch", in: p)
        let mock = MockNotificationService()
        settings(mealReminders: true)
        MealReminderPlanner.reschedule(modelContext: context, notifications: mock, now: now)
        lunch.scheduledTime = "13:00"
        MealReminderPlanner.reschedule(modelContext: context, notifications: mock, now: now)
        XCTAssertEqual(mock.scheduledNotifications.count, 1, "no duplicates")
        XCTAssertEqual(mock.scheduledNotifications.first?.triggerDate, at(day: 0, "12:45"))
    }

    // MARK: - Cancel on eat / skip

    func testEatingAndSkippingCancelTheMealsReminder() throws {
        let p = plan()
        let lunch = meal("Lunch", time: "12:00", in: p)
        let dinner = meal("Dinner", time: "19:00", in: p)
        let mock = MockNotificationService()
        settings(mealReminders: true)
        MealReminderPlanner.reschedule(modelContext: context, notifications: mock, now: now)
        XCTAssertEqual(mock.scheduledNotifications.count, 2)

        let env = MealOutcomeService.Env(modelContext: context, notifications: mock)
        // Eaten on time: a late-evening run would otherwise post an
        // off-schedule replan whose real-clock reschedule drops the 19:00 dinner.
        let lunchTime = calendar.date(byAdding: .hour, value: 12, to: today) ?? now
        try MealOutcomeService.markEaten(lunch, at: lunchTime, pantry: .none, env: env)
        XCTAssertEqual(mock.scheduledNotifications.compactMap(\.mealID), [dinner.id])
        try MealOutcomeService.skip(dinner, env: env)
        XCTAssertTrue(mock.scheduledNotifications.isEmpty)
    }

    // MARK: - Routing

    func testRoutingOpensThatMeal() {
        let id = UUID()
        let key = id.uuidString
        XCTAssertEqual(
            TempoNotificationDelegate.mealRequest(category: "MEAL_REMINDER", action: "LOG_MEAL", mealID: key),
            MealRequest(id: id, action: .markEaten)
        )
        for category in ["MEAL_REMINDER", "OVERDUE_MEAL_REMINDER", "DEFROST_REMINDER", "PREP_START_REMINDER"] {
            XCTAssertEqual(
                TempoNotificationDelegate.mealRequest(
                    category: category, action: "com.apple.UNNotificationDefaultActionIdentifier", mealID: key
                ),
                MealRequest(id: id, action: .open), category
            )
        }
        XCTAssertEqual(
            TempoNotificationDelegate.mealRequest(category: "DEFROST_REMINDER", action: "VIEW_MEAL", mealID: key),
            MealRequest(id: id, action: .open)
        )
        XCTAssertNil(TempoNotificationDelegate.mealRequest(category: "DEFROST_REMINDER", action: "DONE", mealID: key))
        XCTAssertNil(TempoNotificationDelegate.mealRequest(category: "MEAL_REMINDER", action: "LOG_MEAL", mealID: nil))
        XCTAssertNil(TempoNotificationDelegate.mealRequest(category: "MEAL_REMINDER", action: "LOG_MEAL", mealID: "nope"))
    }

    func testRequestedMealLookupHandlesDeletedMeal() {
        let p = plan()
        let m = meal("Lunch", in: p)
        XCTAssertEqual(RequestedMealView.meal(id: m.id, in: context)?.id, m.id)
        XCTAssertNil(RequestedMealView.meal(id: UUID(), in: context))
    }

    func testAppStateHoldsTheRequest() {
        let state = AppState(authService: AuthService())
        let id = UUID()
        state.requestedMeal = MealRequest(id: id, action: .markEaten)
        XCTAssertEqual(state.requestedMeal?.id, id)
    }

    // MARK: - Helpers

    private func at(day: Int, _ hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard let base = calendar.date(byAdding: .day, value: day, to: today) else {
            return nil
        }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base)
    }
}
