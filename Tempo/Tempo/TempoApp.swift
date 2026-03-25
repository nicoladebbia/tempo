import SwiftUI
import SwiftData

@main
struct TempoApp: App {
    let container: ModelContainer
    @State private var services: ServiceContainer

    init() {
        do {
            container = try TempoModelContainer.create()
            try ExerciseLibraryLoader.loadIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        _services = State(initialValue: ServiceContainer.live())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(services)
        }
        .modelContainer(container)
    }
}
