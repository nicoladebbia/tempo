//
// NotificationInboxTests.swift
// TempoTests
//
// The in-app list of today's notifications: what is kept, what is dropped, what a
// tap on a row opens, and how the list reads from iOS.
//

import Foundation
@testable import Tempo
import Testing
import UserNotifications

// MARK: - NotificationInboxStoreTests

struct NotificationInboxStoreTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .now
    }

    private func store(_ name: String = #function) -> NotificationInboxStore {
        let suite = "NotificationInboxStoreTests.\(name)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return NotificationInboxStore(defaults: defaults)
    }

    private func item(
        _ id: String, category: String = "MEAL_REMINDER", at date: Date, read: Bool = false,
        userInfo: [AnyHashable: Any] = [:]
    ) -> InboxNotification {
        InboxNotification(
            requestID: id, title: "Title \(id)", body: "Body", category: category,
            userInfo: userInfo, deliveredAt: date, isRead: read
        )
    }

    @Test
    func aRecordedNotificationComesBackNewestFirst() {
        let store = store()
        store.record([item("a", at: at(8)), item("b", at: at(12))], now: at(13), calendar: calendar)
        let today = NotificationInboxStore.today(store.load(), now: at(13), calendar: calendar)
        #expect(today.map(\.requestID) == ["b", "a"])
    }

    @Test
    func theSameNotificationSeenTwiceIsOneRow() {
        let store = store()
        store.record([item("a", at: at(8))], now: at(9), calendar: calendar)
        store.record([item("a", at: at(8))], now: at(9), calendar: calendar)
        #expect(store.load().count == 1)
    }

    @Test
    func aReminderThatComesBackTomorrowIsANewRow() {
        let store = store()
        store.record([item("meal_1", at: at(8, day: 10)), item("meal_1", at: at(8, day: 11))], now: at(9, day: 11), calendar: calendar)
        #expect(store.load().count == 2)
        #expect(NotificationInboxStore.today(store.load(), now: at(9, day: 11), calendar: calendar).count == 1)
    }

    @Test
    func aReadMarkSurvivesTheNextRefresh() {
        let store = store()
        store.record([item("a", at: at(8))], now: at(9), calendar: calendar)
        store.markRead(requestID: "a")
        // iOS lists it again, unread, on the next refresh.
        store.record([item("a", at: at(8))], now: at(10), calendar: calendar)
        #expect(store.load().first?.isRead == true)
    }

    @Test
    func markAllReadOnlyTouchesThatDay() {
        let store = store()
        store.record([item("old", at: at(8, day: 9)), item("new", at: at(8, day: 10))], now: at(9), calendar: calendar)
        store.markAllRead(on: at(9), calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: store.load().map { ($0.requestID, $0.isRead) })
        #expect(byID["new"] == true)
        #expect(byID["old"] == false)
    }

    @Test
    func clearOnlyRemovesThatDay() {
        let store = store()
        store.record([item("old", at: at(8, day: 9)), item("new", at: at(8, day: 10))], now: at(9), calendar: calendar)
        store.clear(on: at(9), calendar: calendar)
        #expect(store.load().map(\.requestID) == ["old"])
    }

    @Test
    func oldNotificationsAreDroppedAndTheRecordIsCapped() {
        let store = store()
        let ancient = item("ancient", at: at(8, day: 1))
        let many = (0 ..< NotificationInboxStore.maxItems + 20).map { item("n\($0)", at: at(0, 0, day: 10).addingTimeInterval(Double($0))) }
        store.record([ancient] + many, now: at(12), calendar: calendar)
        let kept = store.load()
        #expect(kept.count == NotificationInboxStore.maxItems)
        #expect(!kept.contains { $0.requestID == "ancient" })
        #expect(kept.first?.requestID == "n\(NotificationInboxStore.maxItems + 19)", "the newest are kept")
    }

    @Test
    func anUnreadableRecordIsAnEmptyList() {
        let suite = "NotificationInboxStoreTests.corrupt"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaults.set(Data("nope".utf8), forKey: NotificationInboxStore.key)
        #expect(NotificationInboxStore(defaults: defaults).load().isEmpty)
    }

    // MARK: - Payload and routing

    @Test
    func thePayloadKeepsWhatTheRouterNeedsAndDropsWhatJSONCannotHold() throws {
        let info: [AnyHashable: Any] = [
            "aps": ["alert": "hi"],
            "data": ["type": "meal_plan_ready", "jobId": "x"],
            "date": Date(),
            "blob": Data([1, 2, 3]),
        ]
        let row = item("a", category: "MEAL_PLAN_READY", at: at(8), userInfo: info)
        #expect(row.userInfoJSON != nil)
        let data = try #require(row.userInfo["data"] as? [String: Any])
        #expect(data["type"] as? String == "meal_plan_ready")
        #expect(row.userInfo["date"] == nil)
        #expect(row.userInfo["blob"] == nil)
        // It survives being saved.
        let decoded = try JSONDecoder().decode(InboxNotification.self, from: JSONEncoder().encode(row))
        #expect(decoded == row)
    }

    @Test
    func aRowOpensWhatItsBannerWouldHaveOpened() {
        let meal = UUID()
        let info: [AnyHashable: Any] = [NotificationService.mealIDUserInfoKey: meal.uuidString]
        let row = item("meal", category: "MEAL_REMINDER", at: at(8), userInfo: info)
        let viaBanner = NotificationRouter.destination(
            category: "MEAL_REMINDER", action: UNNotificationDefaultActionIdentifier, userInfo: info
        )
        #expect(row.destination != nil)
        #expect(row.destination == viaBanner)
        #expect(row.destination?.meal == MealRequest(id: meal, action: .open))
    }

    @Test
    func aServerPushKeepsItsNestedData() {
        let row = item(
            "push", category: "MEAL_PLAN_READY", at: at(8),
            userInfo: ["data": ["type": "meal_plan_ready", "jobId": "x"]]
        )
        #expect(row.destination?.nutritionSection == .plan)
        #expect(row.destination?.syncPlans == true)
    }

    @Test
    func everyKnownKindHasAnIconAndAnUnknownOneStillDoes() {
        for category in NotificationTopic.allCases.flatMap(\.categoryIDs) + ["USE_IT_UP", "SUPPLEMENT_REMINDER", "SOMETHING_NEW"] {
            #expect(!item("x", category: category, at: at(8)).icon.isEmpty, "\(category)")
        }
        #expect(item("x", category: "ACCOUNTABILITY_FIRM", at: at(8)).icon == "bolt.fill")
        #expect(item("x", category: "SOMETHING_NEW", at: at(8)).icon == "bell.fill")
    }
}

// MARK: - NotificationInboxModelTests

@MainActor
struct NotificationInboxModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "NotificationInboxModelTests.\(name)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func row(_ id: String, minutesAgo: Double) -> InboxNotification {
        InboxNotification(
            requestID: id, title: id, body: "", category: "STREAK_WARNING", userInfo: [:],
            deliveredAt: now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    private func model(
        delivered: [InboxNotification] = [], status: UNAuthorizationStatus = .authorized,
        cleared: ClearedBox = ClearedBox(), defaults: UserDefaults
    ) -> NotificationInbox {
        let now = now
        return NotificationInbox(
            store: NotificationInboxStore(defaults: defaults),
            delivered: { delivered },
            authorizationStatus: { status },
            clearDelivered: { cleared.ids += $0 },
            now: { now }
        )
    }

    @MainActor
    final class ClearedBox {
        var ids: [String] = []
    }

    @Test
    func refreshReadsWhatIOSHoldsAndCountsTheUnread() async {
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], defaults: defaults())
        #expect(model.load == .idle)
        await model.refresh()
        #expect(model.load == .loaded)
        #expect(model.items.map(\.requestID) == ["b", "a"])
        #expect(model.unreadCount == 2)
        #expect(model.authorization == .authorized)
    }

    @Test
    func theListSurvivesARelaunchEvenWhenIOSNoLongerHoldsIt() async {
        let store = defaults()
        await model(delivered: [row("a", minutesAgo: 30)], defaults: store).refresh()
        let relaunched = model(delivered: [], defaults: store)
        #expect(relaunched.items.map(\.requestID) == ["a"], "readable before the first refresh")
        await relaunched.refresh()
        #expect(relaunched.items.map(\.requestID) == ["a"])
    }

    @Test
    func openingARowReadsItAndTakesItOutOfNotificationCentre() async throws {
        let cleared = ClearedBox()
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], cleared: cleared, defaults: defaults())
        await model.refresh()
        let first = try #require(model.items.first)
        model.markRead(first)
        #expect(model.unreadCount == 1)
        #expect(cleared.ids == [first.requestID])
        // iOS lists it once more on the next refresh: it stays read.
        await model.refresh()
        #expect(model.unreadCount == 1)
    }

    @Test
    func markAllReadClearsTheBadge() async {
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], defaults: defaults())
        await model.refresh()
        model.markAllRead()
        #expect(model.unreadCount == 0)
        #expect(model.items.count == 2, "read, not removed")
    }

    @Test
    func clearingTodayEmptiesTheListAndNotificationCentre() async {
        let cleared = ClearedBox()
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], cleared: cleared, defaults: defaults())
        await model.refresh()
        model.clearToday()
        #expect(model.items.isEmpty)
        #expect(Set(cleared.ids) == ["a", "b"])
    }

    @Test
    func clearTodayWithUndoHidesAtOnceButTouchesNothingUntilItEnds() async {
        let cleared = ClearedBox()
        let defaults = defaults()
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], cleared: cleared, defaults: defaults)
        await model.refresh()
        model.beginClearToday()

        #expect(model.items.isEmpty)
        #expect(model.unreadCount == 0)
        #expect(cleared.ids.isEmpty, "still in Notification Centre")
        #expect(NotificationInboxStore(defaults: defaults).load().count == 2, "still in the record")

        // A refresh in the window (the app coming back to the front) does not bring them back.
        await model.refresh()
        #expect(model.items.isEmpty)
    }

    @Test
    func undoBringsTheClearedNotificationsBackAndNothingWasDeleted() async {
        let cleared = ClearedBox()
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], cleared: cleared, defaults: defaults())
        await model.refresh()
        model.beginClearToday()
        model.undoClearToday()
        // The toast then ends: there is nothing left to clear.
        model.finishClearToday()

        #expect(model.items.map(\.requestID) == ["b", "a"])
        #expect(cleared.ids.isEmpty)
    }

    @Test
    func whenTheUndoWindowEndsTheHiddenOnesLeaveTheRecordAndNotificationCentre() async {
        let cleared = ClearedBox()
        let defaults = defaults()
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], cleared: cleared, defaults: defaults)
        await model.refresh()
        model.beginClearToday()
        model.finishClearToday()

        #expect(Set(cleared.ids) == ["a", "b"])
        #expect(model.items.isEmpty)
        #expect(NotificationInboxStore(defaults: defaults).load().isEmpty)

        // Finishing twice clears nothing more.
        model.finishClearToday()
        #expect(cleared.ids.count == 2)
    }

    @Test
    func aNotificationThatArrivesInTheUndoWindowIsNotCleared() async {
        let cleared = ClearedBox()
        let delivered = DeliveredBox()
        delivered.rows = [row("a", minutesAgo: 30)]
        let now = now
        let model = NotificationInbox(
            store: NotificationInboxStore(defaults: defaults()),
            delivered: { delivered.rows },
            authorizationStatus: { .authorized },
            clearDelivered: { cleared.ids += $0 },
            now: { now }
        )
        await model.refresh()
        model.beginClearToday()

        delivered.rows.append(row("late", minutesAgo: 1))
        await model.refresh()
        model.finishClearToday()

        #expect(cleared.ids == ["a"])
        #expect(model.items.map(\.requestID) == ["late"])
    }

    @Test
    func aReadOfIOSThatWasUnderWayWhenTheClearEndedDoesNotBringTheNotificationsBack() async {
        let cleared = ClearedBox()
        let defaults = defaults()
        // iOS still lists both: the read began before the clear went through.
        let model = model(delivered: [row("a", minutesAgo: 30), row("b", minutesAgo: 5)], cleared: cleared, defaults: defaults)
        await model.refresh()
        model.beginClearToday()
        model.finishClearToday()
        await model.refresh()

        #expect(model.items.isEmpty)
        #expect(NotificationInboxStore(defaults: defaults).load().isEmpty)
    }

    @MainActor
    final class DeliveredBox {
        var rows: [InboxNotification] = []
    }

    @Test
    func signingOutForgetsTheListEvenAfterARelaunch() async {
        let store = defaults()
        let cleared = ClearedBox()
        let first = model(delivered: [row("a", minutesAgo: 30)], cleared: cleared, defaults: store)
        await first.refresh()
        first.reset()
        #expect(first.items.isEmpty)
        #expect(cleared.ids == ["a"])
        #expect(model(delivered: [], defaults: store).items.isEmpty)
    }

    @Test
    func yesterdaysAreNotInTodaysList() async {
        let yesterday = row("old", minutesAgo: 60 * 30)
        let model = model(delivered: [yesterday, row("new", minutesAgo: 1)], defaults: defaults())
        await model.refresh()
        #expect(model.items.map(\.requestID) == ["new"])
    }

    @Test
    func aDeniedPermissionIsReportedSoThePageCanSayWhyItIsEmpty() async {
        let model = model(status: .denied, defaults: defaults())
        await model.refresh()
        #expect(model.items.isEmpty)
        #expect(model.authorization == .denied)
    }
}
