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
        let type = content.userInfo["type"] as? String
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
            await snooze(title: title, body: body, category: category, minutes: 30)
        case ("MEAL_REMINDER", _),
             ("OVERDUE_MEAL_REMINDER", _):
            await open(.nutrition)
        case ("SUPPLEMENT_REMINDER", "SUPPLEMENT_TAKEN"):
            let names = content.userInfo["supplementNames"] as? [String] ?? []
            let ids = content.userInfo["supplementIDs"] as? [String] ?? []
            await markSupplementsTaken(names: names, ids: ids)
        case ("SUPPLEMENT_REMINDER", "SUPPLEMENT_SNOOZE_15"):
            let names = content.userInfo["supplementNames"] as? [String] ?? []
            let ids = content.userInfo["supplementIDs"] as? [String] ?? []
            await snooze(title: title, body: body, category: category, minutes: 15, supplementNames: names, supplementIDs: ids)
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
    private func open(_ tab: Tab, checkIn: Bool = false) {
        guard let appState = Self.services?.appState else {
            return
        }
        appState.activeTab = tab
        if checkIn {
            appState.weeklyCheckInRequested = true
        }
    }

    private func snooze(title: String, body: String, category: String, minutes: Int, supplementNames: [String] = [], supplementIDs: [String] = []) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        if !supplementNames.isEmpty {
            content.userInfo = ["supplementNames": supplementNames, "supplementIDs": supplementIDs]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "snooze_\(UUID().uuidString)", content: content, trigger: trigger)
        )
    }

    // MARK: - Supplement actions (Lane 1 — timing engine)

    /// "Taken" on a grouped supplement reminder — marks every named supplement
    /// taken for today. Same decrement path (`SupplementReorderService.
    /// applyTaken`) an in-app tap uses. Takes the already-extracted, Sendable
    /// `[String]` rather than the raw (non-Sendable) notification `userInfo`.
    @MainActor
    private func markSupplementsTaken(names: [String], ids: [String]) async {
        guard let container = Self.modelContainer, !names.isEmpty else {
            return
        }
        SupplementReminderScheduler.markTaken(names: names, ids: ids, modelContext: container.mainContext)
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
