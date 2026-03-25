import SwiftUI
import SwiftData
import UIKit

// MARK: - App Delegate
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

// MARK: - App

@main
struct TempoApp: App {
    @UIApplicationDelegateAdaptor(TempoAppDelegate.self) var appDelegate
    let container: ModelContainer
    @State private var services: ServiceContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try TempoModelContainer.create()
            try ExerciseLibraryLoader.loadIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        let apiClient = APIClient()
        let serviceContainer = ServiceContainer.live(apiClient: apiClient)
        _services = State(initialValue: serviceContainer)

        // Wire push registration service to AppDelegate
        TempoAppDelegate.pushRegistration = serviceContainer.pushRegistration
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
            }
        }
    }

    // MARK: - HealthKit Background Setup
    // Per INTEGRATION_SPECS.md Section 2.4 — enable background delivery on launch.

    private func setupHealthKitBackground() async {
        guard let healthKit = services.healthKit as? HealthKitService else { return }
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
        guard let healthKit = services.healthKit as? HealthKitService else { return }
        await healthKit.verifyPermissionsOnLaunch()
    }
}
