//
// TempoApp.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - TempoAppDelegate

// Per BUILD_PLAN step 12.1 — Handle remote notification device token callbacks.

class TempoAppDelegate: NSObject, UIApplicationDelegate {
    /// Shared push registration service, set by TempoApp on init.
    static var pushRegistration: PushRegistrationService?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Self.pushRegistration?.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.pushRegistration?.didFailToRegisterForRemoteNotifications(error: error)
    }
}

// MARK: - TempoApp

@main
struct TempoApp: App {
    @UIApplicationDelegateAdaptor(TempoAppDelegate.self)
    var appDelegate
    let container: ModelContainer
    @State
    private var services: ServiceContainer
    @Environment(\.scenePhase)
    private var scenePhase

    init() {
        do {
            container = try TempoModelContainer.create()
            if !ProcessInfo.processInfo.environment.keys.contains("XCTestBundlePath") {
                try ExerciseLibraryLoader.loadIfNeeded(context: container.mainContext)
                try AchievementLibrary.loadIfNeeded(context: container.mainContext)
                // One-shot backfill of NonNegotiableProgress.wasSkipped from
                // the legacy sentinel encoding. Idempotent.
                DailyResetCoordinator.backfillWasSkippedIfNeeded(container: container)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        let apiClient = APIClient()
        let serviceContainer = ServiceContainer.live(apiClient: apiClient)
        _services = State(initialValue: serviceContainer)

        // Wire push registration service to AppDelegate
        TempoAppDelegate.pushRegistration = serviceContainer.pushRegistration

        // Per BUILD_PLAN — register BG tasks before scene activation per Apple
        // guidance, then arm the daily reset handler.
        let containerRef = container
        serviceContainer.backgroundSync.dailyResetHandler = { @Sendable in
            await DailyResetCoordinator.runIfNeeded(container: containerRef)
        }
        serviceContainer.backgroundSync.registerBackgroundTasks()
        serviceContainer.backgroundSync.scheduleDailyReset()

        // Make NavigationBar fully transparent so .toolbar(.hidden) doesn't
        // leave a phantom inset on iOS 26.
        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.backgroundColor = .clear
        transparent.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = transparent
        UINavigationBar.appearance().scrollEdgeAppearance = transparent
        UINavigationBar.appearance().compactAppearance = transparent
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(services)
                .task {
                    await setupHealthKitBackground()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await verifyHealthKitPermissions()
                }
                // Phase 3 — proactively refresh Whoop tokens on foreground so
                // the first API call doesn't 401 → refresh → retry.
                let whoop = services.whoop
                Task {
                    try? await whoop.refreshIfNeeded()
                }
                // Per BUILD_PLAN step 12.2 — Cancel pending escalation
                // notifications when the user opens the app (anti-spam).
                if let notifService = services.notifications as? NotificationService {
                    notifService.cancelPendingEscalationsOnForeground()
                }
                // Run any missed daily reset (e.g., BG task got starved).
                let containerRef = container
                Task {
                    await DailyResetCoordinator.runIfNeeded(container: containerRef)
                }
            }
        }
    }

    // MARK: - HealthKit Background Setup

    // Per INTEGRATION_SPECS.md Section 2.4 — enable background delivery on launch.

    private func setupHealthKitBackground() async {
        guard let healthKit = services.healthKit as? HealthKitService else {
            return
        }
        do {
            try await healthKit.enableBackgroundDelivery()
            healthKit.setupObserverQueries()
        } catch {
            // Non-fatal: background delivery is a nice-to-have
        }
    }

    // MARK: - Permission Verification on Foreground

    // Per INTEGRATION_SPECS.md Section 2.1 — verify permissions on every foreground return.

    private func verifyHealthKitPermissions() async {
        guard let healthKit = services.healthKit as? HealthKitService else {
            return
        }
        await healthKit.verifyPermissionsOnLaunch()
    }
}
