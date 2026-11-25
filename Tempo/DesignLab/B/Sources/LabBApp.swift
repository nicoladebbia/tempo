import SwiftUI

@main
struct LabBApp: App {
    var body: some Scene {
        WindowGroup {
            Shell()
                .preferredColorScheme(.dark)
        }
    }
}

enum AppTab: Hashable { case today, train, fuel, arena, capture }

@MainActor @Observable
final class DayModel {
    var waterMl = Sample.waterMl
    var meals = Sample.meals
    var tasks = Sample.tasks.map { TaskItem(title: $0.title, done: $0.done) }
    var kcalEaten: Int { Sample.kcalEaten + meals.dropFirst(2).filter(\.eaten).reduce(0) { $0 + $1.kcal } }
    var tasksLeft: Int { tasks.filter { !$0.done }.count }

    struct TaskItem: Identifiable { let id = UUID(); let title: String; var done: Bool }

    func addWater(_ ml: Int = 250) { waterMl += ml }
}

struct Shell: View {
    @State private var tab: AppTab = Lab.flag("-train") ? .train : Lab.flag("-arena") ? .arena : LabScreen.requested == .food ? .fuel : .today
    @State private var showCapture = Lab.flag("-plus")
    @State private var showSession = LabScreen.requested == .logger
    @State private var session = Session()
    @State private var day = DayModel()
    private let mood = Mood.current

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { new in
            if new == .capture { showCapture = true } else { tab = new }
        })) {
            Tab("Today", systemImage: "sun.horizon.fill", value: AppTab.today) {
                TodayView(day: day, mood: mood, start: startSession)
            }
            Tab("Train", systemImage: "dumbbell.fill", value: AppTab.train) {
                TrainView(mood: mood, start: startSession)
            }
            Tab("Fuel", systemImage: "fork.knife", value: AppTab.fuel) {
                FuelView(day: day, mood: mood)
            }
            Tab("Arena", systemImage: "trophy.fill", value: AppTab.arena) {
                ArenaView(mood: mood)
            }
            Tab("Log", systemImage: "plus", value: AppTab.capture, role: Shell.captureRole) {
                Color.clear
            }
        }
        .tint(mood.accent)
        .modifier(SessionAccessory(session: session, mood: mood, open: { showSession = true }))
        .sheet(isPresented: $showCapture) {
            CaptureSheet(day: day, mood: mood, startSession: {
                showCapture = false
                startSession()
            })
            .presentationDetents([.height(452), .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showSession) {
            LoggerView(session: session, mood: mood)
                .preferredColorScheme(.dark)
        }
    }

    /// A separated, emphasised "+" on iOS 27; the detached search-style slot on iOS 26.
    static var captureRole: TabRole {
        if #available(iOS 27.0, *) { .prominent } else { .search }
    }

    private func startSession() {
        session.isActive = true
        showSession = true
    }
}

/// While a workout is running and minimised, it lives above the tab bar on every tab.
struct SessionAccessory: ViewModifier {
    let session: Session
    let mood: Mood
    let open: () -> Void

    func body(content: Content) -> some View {
        if session.isActive {
            content.tabViewBottomAccessory {
                Button(action: open) {
                    HStack(spacing: Tide.s3) {
                        Image(systemName: "waveform.path.ecg").font(Tide.bodyStrong).foregroundStyle(mood.accent)
                        Text(session.current.name).font(Tide.bodyStrong).foregroundStyle(Tide.text).lineLimit(1)
                        Spacer(minLength: Tide.s2)
                        Text(session.startedAt, style: .timer).font(Tide.numeral(15, .semibold)).foregroundStyle(Tide.text2)
                    }
                    .padding(.horizontal, Tide.s4)
                    .frame(maxWidth: .infinity, minHeight: Tide.hit)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open live session, \(session.current.name)")
            }
        } else {
            content
        }
    }
}
