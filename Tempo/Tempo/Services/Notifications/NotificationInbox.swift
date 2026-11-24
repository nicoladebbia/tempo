//
// NotificationInbox.swift
// Tempo
//
// Today's notifications, in the app. iOS keeps a delivered notification only
// until it is swiped away, and tells the app about one only while the app is
// open. So the list is built from two sources: what iOS still has in Notification
// Centre, and the app's own record of what it has seen (kept for a few days, so a
// swiped-away reminder is still there when you look for it).
//
// A row opens what its banner would have opened: it goes through the same
// `NotificationRouter` as a tap on the banner.
//

import Foundation
import Observation
import UserNotifications

// MARK: - InboxNotification

struct InboxNotification: Codable, Identifiable, Equatable, Sendable {
    /// The request id plus the delivery second: reminders with a fixed id come back every day.
    let id: String
    let requestID: String
    let title: String
    let body: String
    let category: String
    let deliveredAt: Date
    /// The notification's payload as JSON. Only values JSON can hold are kept; the nested
    /// `data` of a server push stays, because the router reads meal and coach ids from it.
    let userInfoJSON: Data?
    var isRead: Bool

    init(
        requestID: String, title: String, body: String, category: String,
        userInfo: [AnyHashable: Any], deliveredAt: Date, isRead: Bool = false
    ) {
        self.id = "\(requestID)|\(Int(deliveredAt.timeIntervalSince1970))"
        self.requestID = requestID
        self.title = title
        self.body = body
        self.category = category
        self.deliveredAt = deliveredAt
        self.userInfoJSON = Self.encode(userInfo)
        self.isRead = isRead
    }

    init(_ notification: UNNotification, isRead: Bool = false) {
        let content = notification.request.content
        self.init(
            requestID: notification.request.identifier, title: content.title, body: content.body,
            category: content.categoryIdentifier, userInfo: content.userInfo,
            deliveredAt: notification.date, isRead: isRead
        )
    }

    var userInfo: [AnyHashable: Any] {
        guard let userInfoJSON,
              let object = try? JSONSerialization.jsonObject(with: userInfoJSON) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    /// Where a tap on this row goes: what a tap on the banner would have opened. nil when
    /// it opens nothing (a quiet confirmation).
    var destination: NotificationDestination? {
        NotificationRouter.destination(
            category: category, action: NotificationRouter.defaultActionID, userInfo: userInfo
        )
    }

    /// A symbol for the kind of notification.
    var icon: String {
        switch category {
        case "MORNING_BRIEFING": "sunrise.fill"
        case "RECOVERY_REPORT": "heart.fill"
        case "MEAL_REMINDER",
             "OVERDUE_MEAL_REMINDER",
             "PREP_START_REMINDER",
             "DEFROST_REMINDER": "fork.knife"
        case "SUPPLEMENT_REMINDER",
             "SUPPLEMENT_REORDER": "pills.fill"
        case "USE_IT_UP": "leaf.fill"
        case "TRAINING_REMINDER": "dumbbell.fill"
        case "BEDTIME_REMINDER": "moon.fill"
        case "STREAK_WARNING": "flame.fill"
        case "WEEKLY_SUMMARY": "chart.bar.fill"
        case "ARENA_SOCIAL": "trophy.fill"
        case "WEEKLY_PLAN_PROMPT",
             "MEAL_PLAN_READY": "calendar"
        default:
            category.hasPrefix("ACCOUNTABILITY") ? "bolt.fill" : "bell.fill"
        }
    }

    private static func encode(_ userInfo: [AnyHashable: Any]) -> Data? {
        var safe: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String, JSONSerialization.isValidJSONObject([key: value]) else {
                continue
            }
            safe[key] = value
        }
        guard !safe.isEmpty else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: safe)
    }
}

// MARK: - NotificationInboxStore

/// The app's own record, in UserDefaults: small, and not worth a SwiftData schema change.
struct NotificationInboxStore {
    static let key = "tempo.notifications.inbox.v1"
    /// How many are kept, and for how long.
    static let maxItems = 100
    static let keepDays = 3

    var defaults: UserDefaults = .standard

    func load() -> [InboxNotification] {
        guard let data = defaults.data(forKey: Self.key) else {
            return []
        }
        return (try? JSONDecoder().decode([InboxNotification].self, from: data)) ?? []
    }

    func save(_ items: [InboxNotification]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Adds what has been seen. One that is already recorded keeps its read mark.
    /// Old ones are dropped, newest kept.
    @discardableResult
    func record(_ incoming: [InboxNotification], now: Date = .now, calendar: Calendar = .current) -> [InboxNotification] {
        var byID = Dictionary(load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in incoming where byID[item.id] == nil {
            byID[item.id] = item
        }
        let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: now) ?? .distantPast
        let kept = byID.values
            .filter { $0.deliveredAt >= cutoff }
            .sorted { $0.deliveredAt > $1.deliveredAt }
            .prefix(Self.maxItems)
        let result = Array(kept)
        save(result)
        return result
    }

    /// Marks every notification with this request id as read (the tap carries the id,
    /// not the delivery second).
    func markRead(requestID: String) {
        let items = load().map { item -> InboxNotification in
            var item = item
            if item.requestID == requestID {
                item.isRead = true
            }
            return item
        }
        save(items)
    }

    func markAllRead(on day: Date, calendar: Calendar = .current) {
        let items = load().map { item -> InboxNotification in
            var item = item
            if calendar.isDate(item.deliveredAt, inSameDayAs: day) {
                item.isRead = true
            }
            return item
        }
        save(items)
    }

    func clear(on day: Date, calendar: Calendar = .current) {
        save(load().filter { !calendar.isDate($0.deliveredAt, inSameDayAs: day) })
    }

    /// Today's, newest first.
    static func today(_ items: [InboxNotification], now: Date = .now, calendar: Calendar = .current) -> [InboxNotification] {
        items
            .filter { calendar.isDate($0.deliveredAt, inSameDayAs: now) }
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }
}

// MARK: - NotificationInbox

@MainActor
@Observable
final class NotificationInbox {
    static let shared = NotificationInbox()

    enum Load: Equatable {
        case idle
        case loading
        case loaded
    }

    /// Today's notifications, newest first.
    private(set) var items: [InboxNotification] = []
    private(set) var load: Load = .idle
    /// What iOS says about permission, so the page can explain an empty list.
    private(set) var authorization: UNAuthorizationStatus?

    /// How many of today's have not been opened: for the badge on a bell.
    var unreadCount: Int {
        items.count(where: { !$0.isRead })
    }

    private let store: NotificationInboxStore
    private let delivered: @MainActor () async -> [InboxNotification]
    private let authorizationStatus: @MainActor () async -> UNAuthorizationStatus
    private let clearDelivered: @MainActor ([String]) -> Void
    private let now: @MainActor () -> Date

    init(
        store: NotificationInboxStore = NotificationInboxStore(),
        delivered: @escaping @MainActor () async -> [InboxNotification] = {
            await UNUserNotificationCenter.current().deliveredNotifications().map { InboxNotification($0) }
        },
        authorizationStatus: @escaping @MainActor () async -> UNAuthorizationStatus = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        clearDelivered: @escaping @MainActor ([String]) -> Void = {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: $0)
        },
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.store = store
        self.delivered = delivered
        self.authorizationStatus = authorizationStatus
        self.clearDelivered = clearDelivered
        self.now = now
        items = NotificationInboxStore.today(store.load(), now: now())
    }

    /// Reads what iOS still holds, merges it into the record and refreshes the list.
    func refresh() async {
        if load == .idle {
            load = .loading
        }
        let seen = await delivered()
        authorization = await authorizationStatus()
        let all = store.record(seen, now: now())
        items = NotificationInboxStore.today(all, now: now())
        load = .loaded
    }

    /// A notification that arrived while the app was open.
    func noteDelivered(_ notification: UNNotification) {
        let all = store.record([InboxNotification(notification)], now: now())
        items = NotificationInboxStore.today(all, now: now())
    }

    /// Opened from its banner or Notification Centre.
    func noteOpened(requestID: String, content: UNNotificationContent, deliveredAt: Date) {
        let item = InboxNotification(
            requestID: requestID, title: content.title, body: content.body,
            category: content.categoryIdentifier, userInfo: content.userInfo,
            deliveredAt: deliveredAt, isRead: true
        )
        store.record([item], now: now())
        store.markRead(requestID: requestID)
        items = NotificationInboxStore.today(store.load(), now: now())
    }

    /// Opened from this list: it reads as seen, and leaves Notification Centre like a tapped banner does.
    func markRead(_ item: InboxNotification) {
        store.markRead(requestID: item.requestID)
        clearDelivered([item.requestID])
        items = NotificationInboxStore.today(store.load(), now: now())
    }

    func markAllRead() {
        store.markAllRead(on: now())
        items = NotificationInboxStore.today(store.load(), now: now())
    }

    /// Empties today's list, and takes the same notifications out of Notification Centre so they don't come back.
    func clearToday() {
        clearDelivered(items.map(\.requestID))
        store.clear(on: now())
        items = NotificationInboxStore.today(store.load(), now: now())
    }
}
