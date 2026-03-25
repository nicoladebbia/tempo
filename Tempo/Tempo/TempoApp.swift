import SwiftUI
import SwiftData

@main
struct TempoApp: App {
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
        _services = State(initialValue: ServiceContainer.live(apiClient: apiClient))
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
