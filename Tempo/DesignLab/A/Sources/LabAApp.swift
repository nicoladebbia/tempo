import SwiftUI

@main
struct LabAApp: App {
    var body: some Scene {
        WindowGroup {
            Shell().preferredColorScheme(.dark)
        }
    }
}

enum STab: Hashable { case today, train, fuel, arena, capture }

struct Shell: View {
    @State private var tab: STab = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-train") { return .train }
        if args.contains("-arena") { return .arena }
        return LabScreen.requested == .food ? .fuel : .today
    }()
    @State private var showCapture = ProcessInfo.processInfo.arguments.contains("-plus")
    @State private var showLogger = LabScreen.requested == .logger

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { new in
            if new == .capture { showCapture = true } else { tab = new }
        })) {
            Tab("Today", systemImage: "scope", value: STab.today) {
                TodayView(startWorkout: { showLogger = true })
            }
            Tab("Train", systemImage: "dumbbell.fill", value: STab.train) {
                TrainView(startWorkout: { showLogger = true })
            }
            Tab("Fuel", systemImage: "fork.knife", value: STab.fuel) {
                FuelView(openCapture: { showCapture = true })
            }
            Tab("Arena", systemImage: "trophy.fill", value: STab.arena) {
                ArenaView()
            }
            if #available(iOS 27.0, *) {
                Tab("Add", systemImage: "plus", value: STab.capture, role: .prominent) { Color.clear }
            } else {
                Tab("Add", systemImage: "plus", value: STab.capture, role: .search) { Color.clear }
            }
        }
        .tint(S.accent)
        .sensoryFeedback(.selection, trigger: tab)
        .sheet(isPresented: $showCapture) {
            CaptureSheet(startWorkout: { showCapture = false; showLogger = true })
        }
        .fullScreenCover(isPresented: $showLogger) {
            LoggerView(close: { showLogger = false })
        }
    }
}
