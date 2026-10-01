//
// TempoNotificationDelegate.swift
// Tempo
//
// What happens when a notification is tapped or one of its buttons is
// pressed. Before this, no delegate existed — every action button (Log Meal,
// Delay 30min, …) did nothing and foreground notifications were silent.
//

import Foundation
import os
import SwiftData
import UserNotifications

final class TempoNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = TempoNotificationDelegate()

    @MainActor
    static var services: ServiceContainer?
    @MainActor
    static var modelContainer: ModelContainer?

    private let logger = Logger(subsystem: "app.tempo", category: "NotificationDelegate")

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let action = response.actionIdentifier
        let type = Self.pushType(from: content.userInfo)
        let mealID = content.userInfo[NotificationService.mealIDUserInfoKey] as? String
        let title = content.title
        let body = content.body
        logger.info("Notification action \(action, privacy: .public) in \(category, privacy: .public)")

        switch (category, action) {
        case (WeeklyPlanReminder.categoryID, WeeklyPlanReminder.buildActionID):
            await buildNextWeek()
        case (WeeklyPlanReminder.categoryID, _):
            await open(.nutrition, checkIn: true)
        case (WeeklyPlanReminder.readyCategoryID, _):
            await open(.nutrition)
            await syncPlans()
        case ("MEAL_REMINDER", "DELAY_30MIN"):
            await snooze(title: title, body: body, category: category, minutes: 30, mealID: mealID)
        case ("OVERDUE_MEAL_REMINDER", NotificationService.overdueAteActionID):
            await resolveOverdueMeal(content.userInfo[NotificationService.mealIDUserInfoKey] as? String, ate: true)
        case ("OVERDUE_MEAL_REMINDER", NotificationService.overdueSkippedActionID):
            await resolveOverdueMeal(content.userInfo[NotificationService.mealIDUserInfoKey] as? String, ate: false)
        case ("MEAL_REMINDER", _),
             ("OVERDUE_MEAL_REMINDER", _),
             ("DEFROST_REMINDER", _),
             ("PREP_START_REMINDER", _):
            if let request = Self.mealRequest(category: category, action: action, mealID: mealID) {
                await open(.nutrition, meal: request)
            } else if !Self.isQuietMealAction(action) {
                await open(.nutrition)
            }
        case ("SUPPLEMENT_REMINDER", "SUPPLEMENT_TAKEN"):
            let names = content.userInfo["supplementNames"] as? [String] ?? []
            let ids = content.userInfo["supplementIDs"] as? [String] ?? []
            await markSupplementsTaken(
                names: names, ids: ids,
                deliveredAt: Self.supplementDay(userInfo: content.userInfo, delivered: response.notification.date)
            )
        case ("SUPPLEMENT_REMINDER", "SUPPLEMENT_SNOOZE_15"):
            let names = content.userInfo["supplementNames"] as? [String] ?? []
            let ids = content.userInfo["supplementIDs"] as? [String] ?? []
            await snooze(
                title: title, body: body, category: category, minutes: 15, supplementNames: names, supplementIDs: ids,
                originalDelivery: Self.supplementDay(userInfo: content.userInfo, delivered: response.notification.date)
            )
        case ("SUPPLEMENT_REMINDER", _):
            await open(.nutrition)
        case ("SUPPLEMENT_REORDER", "SUPPLEMENT_ADD_TO_LIST"):
            let name = content.userInfo["supplementName"] as? String
            await addLowSupplementToGroceryList(supplementName: name)
        case ("SUPPLEMENT_REORDER", "SUPPLEMENT_RESTOCKED"):
            let name = content.userInfo["supplementName"] as? String
            let id = (content.userInfo["supplementID"] as? String).flatMap(UUID.init(uuidString:))
            await restockSupplement(supplementName: name, supplementID: id)
        case ("SUPPLEMENT_REORDER", _):
            await open(.nutrition)
        default:
            if type == "meal_plan_ready" {
                await open(.nutrition)
                await syncPlans()
            }
        }
    }

    /// Server pushes nest their custom keys under `"data"` (`{"aps":…,"data":{"type":…}}`);
    /// locally scheduled notifications put them at the top level. Read `data.type` first,
    /// fall back to top-level `type`.
    static func pushType(from userInfo: [AnyHashable: Any]) -> String? {
        if let data = userInfo["data"] as? [String: Any], let type = data["type"] as? String {
            return type
        }
        return userInfo["type"] as? String
    }

    // MARK: - Actions

    /// "Yes, build it" — runs with the app in the background: build the
    /// prompt, queue the server job, done. The server pushes when it's ready.
    @MainActor
    private func buildNextWeek() async {
        guard let services = Self.services, let container = Self.modelContainer else {
            return
        }
        do {
            try await WeeklyPlanService.shared.requestWeek(modelContext: container.mainContext, deps: PlanDeps(services))
        } catch {
            logger.error("Sunday build failed to start: \(error.localizedDescription, privacy: .public)")
            let reason = (error as? LocalizedError)?.errorDescription ?? "Open Tempo to try again."
            await WeeklyPlanReminder.notify(title: "Couldn't start next week's plan", body: reason)
        }
    }

    @MainActor
    private func syncPlans() async {
        guard let services = Self.services, let container = Self.modelContainer else {
            return
        }
        await WeeklyPlanService.shared.sync(modelContext: container.mainContext, deps: PlanDeps(services))
    }

    @MainActor
    private func open(_ tab: Tab, checkIn: Bool = false, meal: MealRequest? = nil) {
        guard let appState = Self.services?.appState else {
            return
        }
        appState.activeTab = tab
        if checkIn {
            appState.weeklyCheckInRequested = true
        }
        if let meal {
            appState.requestedMeal = meal
        }
    }

    /// What a meal notification tap / button should show: "Log meal" opens
    /// Mark eaten for that meal, everything else that carries a meal id (a
    /// tap, "View meal") opens the meal. Nil when there is no meal id.
    static func mealRequest(category: String, action: String, mealID: String?) -> MealRequest? {
        guard let mealID, let uuid = UUID(uuidString: mealID) else {
            return nil
        }
        switch (category, action) {
        case ("MEAL_REMINDER", "LOG_MEAL"):
            return MealRequest(id: uuid, action: .markEaten)
        case (_, _) where isQuietMealAction(action):
            return nil
        default:
            return MealRequest(id: uuid, action: .open)
        }
    }

    /// Buttons that act without opening a meal.
    static func isQuietMealAction(_ action: String) -> Bool {
        action == "DONE" || action == "DELAY_15MIN" || action == "DELAY_30MIN"
    }

    /// The moment a supplement reminder was first delivered. A snoozed copy
    /// carries it forward so a snooze that crosses midnight keeps its day.
    static let supplementDeliveredKey = "supplementDeliveredAt"

    static func supplementDay(userInfo: [AnyHashable: Any], delivered: Date) -> Date {
        (userInfo[supplementDeliveredKey] as? Double).map(Date.init(timeIntervalSince1970:)) ?? delivered
    }

    private func snooze(
        title: String, body: String, category: String, minutes: Int,
        supplementNames: [String] = [], supplementIDs: [String] = [], originalDelivery: Date? = nil,
        mealID: String? = nil
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        if !supplementNames.isEmpty {
            content.userInfo = [
                "supplementNames": supplementNames,
                "supplementIDs": supplementIDs,
                Self.supplementDeliveredKey: (originalDelivery ?? Date()).timeIntervalSince1970,
            ]
        }
        if let mealID {
            // A snoozed meal reminder still opens its meal.
            content.userInfo = [NotificationService.mealIDUserInfoKey: mealID]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                // Supplement snoozes carry their supplement IDs so a tick can cancel them.
                identifier: supplementNames.isEmpty
                    ? "snooze_\(UUID().uuidString)"
                    : SupplementReminderScheduler.snoozeIdentifier(supplementIDs: supplementIDs),
                content: content,
                trigger: trigger
            )
        )
    }

    // MARK: - Supplement actions (Lane 1 — timing engine)

    /// "Ate it" / "Skipped" on an overdue-meal check-in — the same
    /// `MealOutcomeService` path as Mark Eaten / Skip in Nutrition (pantry,
    /// shift, rebalance, reminders, Dashboard).
    @MainActor
    private func resolveOverdueMeal(_ id: String?, ate: Bool) async {
        guard let container = Self.modelContainer else {
            return
        }
        let env = MealOutcomeService.Env.live(
            modelContext: container.mainContext,
            notifications: Self.services?.notifications,
            whoop: Self.services?.whoop
        )
        Self.resolveOverdueMeal(id: id, ate: ate, env: env)
    }

    /// A meal already resolved (eaten in the app meanwhile, or removed by a
    /// rebuild) is left alone. Returns true when the meal changed.
    @MainActor
    @discardableResult
    static func resolveOverdueMeal(id: String?, ate: Bool, env: MealOutcomeService.Env) -> Bool {
        guard let id, let uuid = UUID(uuidString: id) else {
            return false
        }
        var descriptor = FetchDescriptor<PlannedMeal>(predicate: #Predicate<PlannedMeal> { $0.id == uuid })
        descriptor.fetchLimit = 1
        guard let meal = try? env.modelContext.fetch(descriptor).first,
              meal.status == .planned || meal.status == .modified
        else {
            return false
        }
        do {
            if ate {
                try MealOutcomeService.markEaten(meal, env: env)
            } else {
                try MealOutcomeService.skip(meal, env: env, rebalance: true)
            }
            return true
        } catch {
            Logger(subsystem: "app.tempo", category: "NotificationDelegate")
                .error("Overdue meal action failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// "Taken" on a grouped supplement reminder — marks every named supplement
    /// taken for the day the reminder was DELIVERED (a 23:50 reminder tapped at
    /// 00:10 still counts for the day it was about). Same decrement path
    /// (`SupplementReorderService.applyTaken`) an in-app tap uses. Takes the
    /// already-extracted, Sendable `[String]` rather than the raw
    /// (non-Sendable) notification `userInfo`.
    @MainActor
    private func markSupplementsTaken(names: [String], ids: [String], deliveredAt: Date) async {
        guard let container = Self.modelContainer, !names.isEmpty else {
            return
        }
        SupplementReminderScheduler.markTaken(names: names, ids: ids, modelContext: container.mainContext, now: deliveredAt)
    }

    /// "Add to grocery list" on a running-low alert.
    @MainActor
    private func addLowSupplementToGroceryList(supplementName: String?) async {
        guard let container = Self.modelContainer, let name = supplementName else {
            return
        }
        let context = container.mainContext
        _ = try? PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: name,
            displayName: name,
            quantity: 1,
            unit: .pieces,
            modelContext: context
        )
        open(.nutrition)
    }

    /// "Restocked" on a running-low alert — adds a container and starts a new
    /// cycle. Looks the item up by ID (falling back to the name for alerts
    /// scheduled before IDs existed). When the item has no container size on
    /// record the count can't be updated, so nothing is stamped and the app
    /// opens on Nutrition to enter it — silently "restocking" 0 servings used
    /// to reset the cycle while leaving the shelf at "running low".
    @MainActor
    private func restockSupplement(supplementName: String?, supplementID: UUID?) async {
        guard let container = Self.modelContainer, supplementName != nil || supplementID != nil else {
            return
        }
        let context = container.mainContext
        guard let supplement = SupplementIntakeStore.supplement(id: supplementID, name: supplementName ?? "", in: context) else {
            return
        }
        if SupplementReorderService.restock(supplement) {
            try? context.save()
            NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
        } else {
            open(.nutrition)
        }
    }
}
