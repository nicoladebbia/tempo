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

    private func snooze(title: String, body: String, category: String, minutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "snooze_\(UUID().uuidString)", content: content, trigger: trigger)
        )
    }
}
