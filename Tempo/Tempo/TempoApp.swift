import SwiftUI
import SwiftData

@main
struct TempoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [])
    }
}
