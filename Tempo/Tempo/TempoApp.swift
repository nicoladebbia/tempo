import SwiftUI
import SwiftData

@main
struct TempoApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try TempoModelContainer.create()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
