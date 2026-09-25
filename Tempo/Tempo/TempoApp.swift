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
                // One-shot purge of Whoop demo data older builds saved as real.
                WhoopDemoDataCleanup.runIfNeeded(container: container)
            }
            #if DEBUG
                // Guided run mode — UI-test-only fixture (see
                // GuidedRunUITestSeed's header); no-ops unless launched with
                // its launch argument.
                GuidedRunUITestSeed.seedIfRequested(context: container.mainContext)
            #endif
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        // ServiceContainer.live builds the APIClient itself so it can wire
        // the AuthInterceptor (Bearer-token attachment) at APIClient init.
        let serviceContainer = ServiceContainer.live()
        // §22 — the watch action router needs a real ModelContext to act on
        // (mark a non-negotiable done, log a meal eaten, ...); wire it here,
        // immediately, using the SAME context `.modelContainer(container)`
        // hands every view via `@Environment(\.modelContext)`.
        serviceContainer.configure(modelContext: container.mainContext)
        _services = State(initialValue: serviceContainer)

        // Wire push registration service to AppDelegate
        TempoAppDelegate.pushRegistration = serviceContainer.pushRegistration

        // Per BUILD_PLAN — register BG tasks before scene activation per Apple
        // guidance, then arm the daily reset handler.
        let containerRef = container
        // Inject the workout-plan ensurer so the daily reset (and any
        // first-launch Dashboard open) persists today's WorkoutPlan via
        // the Training tab's own generate-and-persist path. Keeps the
        // Dashboard Move quadrant and the Training tab on one source of
        // truth. A throwaway TrainingViewModel is fine — the ensure path
        // is stateless w.r.t. the VM's session state.
        let trainingEngineRef = serviceContainer.trainingEngine
        let whoopRef = serviceContainer.whoop
        let healthKitRef = serviceContainer.healthKit
        DailyResetCoordinator.workoutPlanEnsurer = { @MainActor modelContext in
            let vm = TrainingViewModel(
                trainingEngine: trainingEngineRef,
                whoop: whoopRef,
                healthKit: healthKitRef
            )
            vm.ensureTodayPlanPersisted(modelContext: modelContext)
        }
        // §4: let the daily reset fire a missed-log nudge when yesterday
        // reads as a forgotten log. Decoupled via a closure so the
        // coordinator doesn't depend on NotificationService directly.
        let notificationsRef = serviceContainer.notifications
        DailyResetCoordinator.missedLogNotifier = { @MainActor in
            (notificationsRef as? NotificationService)?.scheduleMissedLogReminder()
        }
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
                // Fix #12 — rebuild the rolling 7-day trainer-session
                // reminder window on every foreground return (matches, a
                // recovery swing, or a program edit made while backgrounded
                // can all change which of the next 7 days actually fire).
                TrainerSessionReminderScheduler.reschedule(
                    notifications: services.notifications,
                    trainingEngine: services.trainingEngine,
                    whoop: services.whoop,
                    healthKit: services.healthKit,
                    modelContext: container.mainContext
                )
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
